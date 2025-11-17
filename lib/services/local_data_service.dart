import 'package:flutter/foundation.dart';

import '../utils/image_utils.dart';
import 'database_service.dart';
import 'offline_cache_service.dart';

class LocalDataService {
  LocalDataService._internal();
  static final LocalDataService _instance = LocalDataService._internal();
  factory LocalDataService() => _instance;

  final DatabaseService _databaseService = DatabaseService();
  final OfflineCacheService _offlineCacheService = OfflineCacheService();

  Future<void> clearAllLocalData() async {
    try {
      await _offlineCacheService.deleteAllOfflineCache();
    } catch (e) {
      debugPrint('Offline cache delete failed: $e');
    }

    try {
      await _databaseService.deleteDatabaseFile();
    } catch (e) {
      debugPrint('Database delete failed: $e');
    }

    try {
      await ImageUtils.clearCaches();
    } catch (e) {
      debugPrint('Image cache clear failed: $e');
    }
  }
}


