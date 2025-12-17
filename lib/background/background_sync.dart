import 'package:workmanager/workmanager.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../services/account_service.dart';
import '../services/local_rss_service.dart';
import '../services/shared_preferences_service.dart';
import '../database/database_helper.dart';
import '../database/account_dao.dart';
import '../database/group_dao.dart';
import '../database/article_dao.dart';
import '../database/feed_dao.dart';
import '../services/freshrss_service.dart';
import '../services/freshrss_sync_service.dart';
import '../services/rss_helper.dart';
import '../services/rss_service.dart';
import '../services/sync_log_service.dart';
import '../services/sync_coordinator.dart';

const String kBackgroundSyncTask = 'background_sync_task';

/// Registers periodic background sync. Interval is in minutes.
/// Note: Android minimum interval is 15 minutes.
/// 
/// This uses WorkManager's built-in constraints which are checked BEFORE the task runs,
/// making it more efficient than manual checks. The task will only run when:
/// - Network is available (WiFi if requiresWiFi=true, any connection otherwise)
/// - Device is charging (if requiresCharging=true)
Future<void> registerBackgroundSync(int minutes, {bool requiresCharging = false, bool requiresWiFi = false}) async {
  print('[BACKGROUND_SYNC] Registering periodic sync with interval: $minutes minutes (requiresCharging=$requiresCharging, requiresWiFi=$requiresWiFi)');
  
  if (minutes <= 0) {
    print('[BACKGROUND_SYNC] Sync interval is 0 or negative, cancelling');
    await Workmanager().cancelByUniqueName(kBackgroundSyncTask);
    return;
  }
  
  // Android minimum interval is 15 minutes for periodic tasks
  final actualMinutes = minutes < 15 ? 15 : minutes;
  print('[BACKGROUND_SYNC] Using interval: $actualMinutes minutes (Android minimum: 15)');
  
  // Use NetworkType.unmetered (WiFi) if WiFi is required, otherwise allow any connection
  final networkType = requiresWiFi ? NetworkType.unmetered : NetworkType.connected;
  print('[BACKGROUND_SYNC] Network type: ${requiresWiFi ? "WiFi only (unmetered)" : "Any connection"}');
  
  try {
    // Check if work is already registered to avoid unnecessary cancellations
    // Note: workmanager package may not support getWorkInfosByUniqueName, so we'll
    // use a simpler approach: always cancel and re-register for consistency
    await Workmanager().cancelByUniqueName(kBackgroundSyncTask);
    
    await Workmanager().registerPeriodicTask(
      kBackgroundSyncTask,
      kBackgroundSyncTask,
      frequency: Duration(minutes: actualMinutes),
      // Let WorkManager run ASAP; it will still respect min interval for subsequent runs
      // (no initialDelay keeps first execution from being deferred a full period)
      constraints: Constraints(
        networkType: networkType,
        requiresBatteryNotLow: false,
        requiresCharging: requiresCharging, // WorkManager checks this BEFORE running
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );
    print('[BACKGROUND_SYNC] Periodic task registered successfully with constraints (charging=$requiresCharging, WiFi=$requiresWiFi)');
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
/// 
/// NOTE: By the time this function runs, WorkManager has already verified that:
/// - Network is available (and WiFi if required)
/// - Device is charging (if required)
/// So we don't need to check these constraints again here.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Ensure Flutter bindings are ready so plugins (prefs/db/http) work on background isolate
    WidgetsFlutterBinding.ensureInitialized();
    print('[BACKGROUND_SYNC] Task triggered: $task');
    if (task != kBackgroundSyncTask) {
      print('[BACKGROUND_SYNC] Task name mismatch, expected: $kBackgroundSyncTask');
      return Future.value(false);
    }

    try {
      // Initialize singletons/services first to get account settings
      final prefs = SharedPreferencesService();
      await prefs.init();
      final accountId = await prefs.getInt('currentAccountId');
      print('[BACKGROUND_SYNC] Account ID from prefs: $accountId');
      if (accountId == null) {
        print('[BACKGROUND_SYNC] No account ID found, aborting');
        return Future.value(false);
      }

      final databaseHelper = DatabaseHelper.instance;
      await databaseHelper.database; // ensure DB opened

      final accountDao = AccountDao();
      final groupDao = GroupDao();
      final accountService = AccountService(accountDao, groupDao, prefs);
      final account = await accountService.getById(accountId);
      if (account == null) {
        print('[BACKGROUND_SYNC] Account not found for ID: $accountId');
        return Future.value(false);
      }

      // WorkManager constraints have already been checked, so we can proceed directly
      // If we reach here, it means:
      // - Network is available (and WiFi if account.syncOnlyOnWiFi is true)
      // - Device is charging (if account.syncOnlyWhenCharging is true)
      print('[BACKGROUND_SYNC] Starting sync for account: ${account.name} (constraints already verified by WorkManager)');

      final articleDao = ArticleDao();
      final feedDao = FeedDao();
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
      final freshRssService = FreshRssService(http.Client());
      final freshRssSyncService = FreshRssSyncService(
        freshRssService,
        articleDao,
        feedDao,
        groupDao,
        accountDao,
        rssService,
      );
      final syncCoordinator = SyncCoordinator(
        accountDao,
        localRssService,
        freshRssSyncService,
      );

      final articleDaoBefore = ArticleDao();
      final countBefore = await articleDaoBefore.countByAccountId(account.id!);
      print('[BACKGROUND_SYNC] Articles before sync: $countBefore');
      
      await syncCoordinator.syncAccount(account.id!);
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
        note: 'Background sync completed',
      ));
      
      return Future.value(true);
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
      return Future.value(false);
    }
  });
}

