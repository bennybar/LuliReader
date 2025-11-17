import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_config.dart';
import '../models/swipe_action.dart';

class StorageService {
  static const String _keyUserConfig = 'user_config';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyAutoMarkRead = 'auto_mark_read';
  static const String _keySwipeLeftAction = 'swipe_left_action';
  static const String _keySwipeRightAction = 'swipe_right_action';
  static const String _keyLastSyncAt = 'last_sync_at';
  static const String _keyShowStarredTab = 'show_starred_tab';
  static const String _keyPreviewLines = 'preview_lines';
  static const String _keyDefaultTab = 'default_tab';

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

  Future<void> saveAutoMarkRead(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoMarkRead, value);
  }

  Future<bool> getAutoMarkRead() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoMarkRead) ?? true;
  }

  Future<void> saveSwipeLeftAction(SwipeAction action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySwipeLeftAction, action.storageValue);
  }

  Future<void> saveSwipeRightAction(SwipeAction action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySwipeRightAction, action.storageValue);
  }

  Future<SwipeAction> getSwipeLeftAction() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keySwipeLeftAction);
    return swipeActionFromString(stored);
  }

  Future<SwipeAction> getSwipeRightAction() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keySwipeRightAction);
    return swipeActionFromString(stored ?? 'toggle_star');
  }

  Future<void> saveShowStarredTab(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowStarredTab, value);
  }

  Future<bool> getShowStarredTab() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowStarredTab) ?? true;
  }

  Future<void> saveLastSyncTimestamp(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSyncAt, timestamp.toIso8601String());
  }

  Future<DateTime?> getLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyLastSyncAt);
    if (value == null) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePreviewLines(int lines) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPreviewLines, lines.clamp(1, 4));
  }

  Future<int> getPreviewLines() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyPreviewLines) ?? 3;
  }

  Future<void> saveDefaultTab(String tabId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultTab, tabId);
  }

  Future<String> getDefaultTab() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDefaultTab) ?? 'home';
  }
}

