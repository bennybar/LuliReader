import 'dart:io';

import 'package:workmanager/workmanager.dart';

import 'storage_service.dart';
import 'sync_service.dart';
import 'freshrss_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final storage = StorageService();
      final config = await storage.getUserConfig();

      if (config != null) {
        final api = FreshRSSService();
        api.setConfig(config);

        final syncService = SyncService();
        syncService.setUserConfig(config);

        // Perform sync (also updates last sync timestamp and badges)
        await syncService.syncAll(fetchFullContent: true);

        // On iOS we emulate periodic work by re-scheduling a one-off task
        // after each successful run, using the user's configured interval.
        if (Platform.isIOS) {
          final intervalMinutes = config.backgroundSyncIntervalMinutes;
          final minInterval = intervalMinutes < 15 ? 15 : intervalMinutes;
          await Workmanager().registerOneOffTask(
            BackgroundSyncService.taskName,
            BackgroundSyncService.taskName,
            initialDelay: Duration(minutes: minInterval),
            constraints: Constraints(
              networkType: NetworkType.connected,
            ),
          );
        }
      }

      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

class BackgroundSyncService {
  static const String taskName = 'backgroundSync';

  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> scheduleSync(int intervalMinutes) async {
    await Workmanager().cancelByUniqueName(taskName);
    
    // Convert minutes to minimum interval (15 minutes is minimum for periodic tasks)
    final minInterval = intervalMinutes < 15 ? 15 : intervalMinutes;
    
    // On Android we can use true periodic tasks.
    if (Platform.isAndroid) {
      await Workmanager().registerPeriodicTask(
        taskName,
        taskName,
        frequency: Duration(minutes: minInterval),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    } else if (Platform.isIOS) {
      // iOS does not support periodic tasks in the same way; schedule a one-off
      // task and let the callback reschedule itself.
      await Workmanager().registerOneOffTask(
        taskName,
        taskName,
        initialDelay: Duration(minutes: minInterval),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    }
  }

  static Future<void> cancelSync() async {
    await Workmanager().cancelByUniqueName(taskName);
  }
}

