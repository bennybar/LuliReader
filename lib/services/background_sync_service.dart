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
        
        // Perform sync
        await syncService.syncAll(fetchFullContent: true);

        // Persist last sync time and update badge count after sync
        await storage.saveLastSyncTimestamp(DateTime.now());
        await NotificationService.updateBadgeCount();
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
    
    // Schedule periodic task
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: Duration(minutes: minInterval),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  static Future<void> cancelSync() async {
    await Workmanager().cancelByUniqueName(taskName);
  }
}

