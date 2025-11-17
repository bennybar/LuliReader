import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_config.dart';

class StorageService {
  static const String _keyUserConfig = 'user_config';
  static const String _keyIsLoggedIn = 'is_logged_in';

  Future<void> saveUserConfig(UserConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserConfig, jsonEncode(config.toMap()));
    await prefs.setBool(_keyIsLoggedIn, true);
  }

  Future<UserConfig?> getUserConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString(_keyUserConfig);
    if (configJson != null) {
      return UserConfig.fromMap(jsonDecode(configJson));
    }
    return null;
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserConfig);
    await prefs.setBool(_keyIsLoggedIn, false);
  }

  Future<void> saveBackgroundSyncInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('background_sync_interval', minutes);
    
    // Update user config if exists
    final config = await getUserConfig();
    if (config != null) {
      await saveUserConfig(config.copyWith(backgroundSyncIntervalMinutes: minutes));
    }
  }

  Future<int> getBackgroundSyncInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('background_sync_interval') ?? 60;
  }

  Future<void> saveArticleFetchLimit(int limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('article_fetch_limit', limit);
    
    // Update user config if exists
    final config = await getUserConfig();
    if (config != null) {
      await saveUserConfig(config.copyWith(articleFetchLimit: limit));
    }
  }

  Future<int> getArticleFetchLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('article_fetch_limit') ?? 200;
  }
}

