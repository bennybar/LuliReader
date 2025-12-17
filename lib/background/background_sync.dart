import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
Future<void> registerBackgroundSync(int minutes, {bool requiresCharging = false, bool requiresWiFi = false}) async {
  print('[BACKGROUND_SYNC] Registering periodic sync with interval: $minutes minutes (requiresCharging=$requiresCharging, requiresWiFi=$requiresWiFi)');
  await Workmanager().cancelByUniqueName(kBackgroundSyncTask);
  if (minutes <= 0) {
    print('[BACKGROUND_SYNC] Sync interval is 0 or negative, cancelling');
    return;
  }
  
  // Android minimum interval is 15 minutes for periodic tasks
  final actualMinutes = minutes < 15 ? 15 : minutes;
  print('[BACKGROUND_SYNC] Using interval: $actualMinutes minutes (Android minimum: 15)');
  
  // Use NetworkType.unmetered (WiFi) if WiFi is required, otherwise allow any connection
  final networkType = requiresWiFi ? NetworkType.unmetered : NetworkType.connected;
  print('[BACKGROUND_SYNC] Network type: ${requiresWiFi ? "WiFi only (unmetered)" : "Any connection"}');
  
  try {
    await Workmanager().registerPeriodicTask(
      kBackgroundSyncTask,
      kBackgroundSyncTask,
      frequency: Duration(minutes: actualMinutes),
      initialDelay: Duration(minutes: 1), // Start checking after 1 minute
      constraints: Constraints(
        networkType: networkType,
        requiresBatteryNotLow: false,
        requiresCharging: requiresCharging,
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
      // Initialize singletons/services first to get account settings
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
      final accountService = AccountService(accountDao, groupDao, prefs);
      final account = await accountService.getById(accountId);
      if (account == null) {
        print('[BACKGROUND_SYNC] Account not found for ID: $accountId');
        return false;
      }

      // Check WiFi requirement BEFORE attempting sync
      if (account.syncOnlyOnWiFi) {
        print('[BACKGROUND_SYNC] Checking WiFi connection (WiFi-only mode enabled)...');
        final connectivity = Connectivity();
        final connectivityResult = await connectivity.checkConnectivity();
        final isWifi = connectivityResult.contains(ConnectivityResult.wifi);
        if (!isWifi) {
          print('[BACKGROUND_SYNC] Sync skipped: WiFi-only mode enabled but not on WiFi (connection: $connectivityResult)');
          return false; // Return false to indicate task should not retry immediately
        }
        print('[BACKGROUND_SYNC] WiFi connection confirmed');
      }

      // Check charging requirement BEFORE attempting sync
      if (account.syncOnlyWhenCharging) {
        print('[BACKGROUND_SYNC] Checking charging status (charging-only mode enabled)...');
        final battery = Battery();
        final batteryState = await battery.batteryState;
        final isCharging = batteryState == BatteryState.charging || batteryState == BatteryState.full;
        if (!isCharging) {
          print('[BACKGROUND_SYNC] Sync skipped: Charging-only mode enabled but device is not charging (batteryState: $batteryState)');
          return false; // Return false to indicate task should not retry immediately
        }
        print('[BACKGROUND_SYNC] Device is charging');
      }

      final battery = Battery();
      final batteryState = await battery.batteryState;
      final isCharging = batteryState == BatteryState.charging || batteryState == BatteryState.full;
      print('[BACKGROUND_SYNC] Starting sync for account: ${account.name} (requiresChargingSetting=${account.syncOnlyWhenCharging}, requiresWiFiSetting=${account.syncOnlyOnWiFi}, batteryState=$batteryState, isCharging=$isCharging)');

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
        note: 'batteryState=$batteryState, isCharging=$isCharging, requiresChargingSetting=${account.syncOnlyWhenCharging}',
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

