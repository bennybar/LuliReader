import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;

import '../services/account_service.dart';
import '../services/local_rss_service.dart';
import '../services/shared_preferences_service.dart';
import '../database/database_helper.dart';
import '../database/account_dao.dart';
import '../database/group_dao.dart';
import '../database/article_dao.dart';
import '../database/feed_dao.dart';
import '../services/rss_helper.dart';
import '../services/rss_service.dart';
import '../services/sync_log_service.dart';

const String kBackgroundSyncTask = 'background_sync_task';

/// Registers periodic background sync. Interval is in minutes.
/// Note: Android minimum interval is 15 minutes.
Future<void> registerBackgroundSync(int minutes) async {
  print('[BACKGROUND_SYNC] Registering periodic sync with interval: $minutes minutes');
  await Workmanager().cancelByUniqueName(kBackgroundSyncTask);
  if (minutes <= 0) {
    print('[BACKGROUND_SYNC] Sync interval is 0 or negative, cancelling');
    return;
  }
  
  // Android minimum interval is 15 minutes for periodic tasks
  final actualMinutes = minutes < 15 ? 15 : minutes;
  print('[BACKGROUND_SYNC] Using interval: $actualMinutes minutes (Android minimum: 15)');
  
  try {
    await Workmanager().registerPeriodicTask(
      kBackgroundSyncTask,
      kBackgroundSyncTask,
      frequency: Duration(minutes: actualMinutes),
      initialDelay: Duration(minutes: 1), // Start checking after 1 minute
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );
    print('[BACKGROUND_SYNC] Periodic task registered successfully');
  } catch (e, stackTrace) {
    // Log error but don't throw - background sync is best effort
    print('[BACKGROUND_SYNC] Error registering periodic task: $e');
    print('[BACKGROUND_SYNC] Stack trace: $stackTrace');
  }
}

Future<void> cancelBackgroundSync() async {
  await Workmanager().cancelByUniqueName(kBackgroundSyncTask);
}

/// Background entrypoint used by Workmanager.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('[BACKGROUND_SYNC] Task triggered: $task');
    if (task != kBackgroundSyncTask) {
      print('[BACKGROUND_SYNC] Task name mismatch, expected: $kBackgroundSyncTask');
      return false;
    }

    try {
      // Initialize singletons/services
      final prefs = SharedPreferencesService();
      await prefs.init();
      final accountId = await prefs.getInt('currentAccountId');
      print('[BACKGROUND_SYNC] Account ID from prefs: $accountId');
      if (accountId == null) {
        print('[BACKGROUND_SYNC] No account ID found, aborting');
        return false;
      }

      final databaseHelper = DatabaseHelper.instance;
      await databaseHelper.database; // ensure DB opened

      final accountDao = AccountDao();
      final groupDao = GroupDao();
      final articleDao = ArticleDao();
      final feedDao = FeedDao();
      final accountService = AccountService(accountDao, groupDao, prefs);
      final account = await accountService.getById(accountId);
      if (account == null) {
        print('[BACKGROUND_SYNC] Account not found for ID: $accountId');
        return false;
      }

      print('[BACKGROUND_SYNC] Starting sync for account: ${account.name}');
      final rssHelper = RssHelper(http.Client());
      final rssService = RssService(http.Client());
      final localRssService = LocalRssService(
        articleDao,
        feedDao,
        groupDao,
        accountDao,
        rssHelper,
        rssService,
        http.Client(),
      );

      final articleDaoBefore = ArticleDao();
      final countBefore = await articleDaoBefore.countByAccountId(account.id!);
      print('[BACKGROUND_SYNC] Articles before sync: $countBefore');
      
      await localRssService.sync(account.id!);
      await accountService.updateAccount(account.copyWith(updateAt: DateTime.now()));
      
      final articleDaoAfter = ArticleDao();
      final countAfter = await articleDaoAfter.countByAccountId(account.id!);
      final articlesSynced = countAfter - countBefore;
      print('[BACKGROUND_SYNC] Sync completed. Articles synced: $articlesSynced');
      
      final syncLog = SyncLogService();
      await syncLog.addLogEntry(SyncLogEntry(
        timestamp: DateTime.now(),
        type: 'background',
        success: true,
        articlesSynced: articlesSynced,
      ));
      
      return true;
    } catch (e, stackTrace) {
      print('[BACKGROUND_SYNC] Error during sync: $e');
      print('[BACKGROUND_SYNC] Stack trace: $stackTrace');
      try {
        final syncLog = SyncLogService();
        await syncLog.addLogEntry(SyncLogEntry(
          timestamp: DateTime.now(),
          type: 'background',
          success: false,
          error: e.toString(),
        ));
      } catch (_) {}
      return false;
    }
  });
}

