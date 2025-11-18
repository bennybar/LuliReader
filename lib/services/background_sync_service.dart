import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'storage_service.dart';
import 'sync_service.dart';
import 'freshrss_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  // Ensure Flutter is initialized in this background isolate before
  // using plugins like shared_preferences, sqflite, etc.
  WidgetsFlutterBinding.ensureInitialized();

  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundSync] callbackDispatcher started for task: $task');
    try {
      final storage = StorageService();
      final config = await storage.getUserConfig();

      if (config != null) {
        final intervalMinutes = config.backgroundSyncIntervalMinutes;
        final minInterval = intervalMinutes < 15 ? 15 : intervalMinutes;
        final api = FreshRSSService();
        api.setConfig(config);

        final syncService = SyncService();
        syncService.setUserConfig(config);

        // Perform sync (also updates last sync timestamp and badges)
        final startedAt = DateTime.now();
        debugPrint('[BackgroundSync] Running syncAll from background task');
        await syncService.syncAll(fetchFullContent: true);
        final finishedAt = DateTime.now();
        final duration = finishedAt.difference(startedAt);
        await _logBackgroundSync(
          storage: storage,
          timestamp: finishedAt,
          minIntervalMinutes: minInterval,
          message:
              'Background sync completed in ${duration.inSeconds}s (task=$task)',
        );

        // On iOS we emulate periodic work by re-scheduling a one-off task
        // after each successful run, using the user's configured interval.
        if (Platform.isIOS) {
          debugPrint(
              '[BackgroundSync] Re-scheduling iOS one-off background task in $minInterval minutes');
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

      debugPrint('[BackgroundSync] Background task completed successfully');
      return Future.value(true);
    } catch (e) {
      debugPrint('[BackgroundSync] Background task failed: $e');
      try {
        final storage = StorageService();
        final now = DateTime.now();
        final config = await storage.getUserConfig();
        final intervalMinutes =
            config?.backgroundSyncIntervalMinutes ?? 15;
        final minInterval =
            intervalMinutes < 15 ? 15 : intervalMinutes;
        await _logBackgroundSync(
          storage: storage,
          timestamp: now,
          minIntervalMinutes: minInterval,
          message: 'Background sync FAILED: $e (task=$task)',
        );
      } catch (_) {
        // Ignore logging failures in background isolate.
      }
      return Future.value(false);
    }
  });
}

Future<void> _logBackgroundSync({
  required StorageService storage,
  required DateTime timestamp,
  required int minIntervalMinutes,
  required String message,
}) async {
  final lastLog = await storage.getLastSyncLogTimestamp();
  if (lastLog != null) {
    final elapsed = timestamp.difference(lastLog);
    if (elapsed < Duration(minutes: minIntervalMinutes)) {
      debugPrint(
          '[BackgroundSync] Skipping log entry (last logged ${elapsed.inMinutes} minutes ago)');
      return;
    }
  }

  final line = '[${timestamp.toIso8601String()}] $message';
  await storage.appendSyncLogEntry(line);
  await storage.saveLastSyncLogTimestamp(timestamp);
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

