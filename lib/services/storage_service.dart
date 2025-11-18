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
  static const String _keyArticleFontSize = 'article_font_size';
  static const String _keySwipeAllowsDelete = 'swipe_allows_delete';
  static const String _keyDeletedArticleIds = 'deleted_article_ids';
  static const String _keySyncLogEntries = 'sync_log_entries';
  static const String _keyLastSyncLogTimestamp = 'last_sync_log_timestamp';
  static const String _keyArticleListPadding = 'article_list_padding';

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
      await saveUserConfig(
        config.copyWith(backgroundSyncIntervalMinutes: minutes),
      );
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

  Future<void> saveArticleFontSize(double size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyArticleFontSize, size.clamp(14.0, 24.0));
  }

  Future<double> getArticleFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyArticleFontSize) ?? 16.0;
  }

  Future<void> saveArticleListPadding(double padding) async {
    final prefs = await SharedPreferences.getInstance();
    final clamped = padding.clamp(8.0, 32.0);
    await prefs.setDouble(_keyArticleListPadding, clamped);
  }

  Future<double> getArticleListPadding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyArticleListPadding) ?? 16.0;
  }

  Future<void> saveSwipeAllowsDelete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySwipeAllowsDelete, value);
  }

  Future<bool> getSwipeAllowsDelete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySwipeAllowsDelete) ?? false;
  }

  Future<List<String>> getDeletedArticleIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyDeletedArticleIds) ?? <String>[];
  }

  Future<void> addDeletedArticleId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_keyDeletedArticleIds) ?? <String>[];
    if (existing.contains(id)) return;
    existing.add(id);
    await prefs.setStringList(_keyDeletedArticleIds, existing);
  }

  /// Append a line to the background sync log, keeping only the most recent
  /// 100 entries to avoid unbounded growth.
  Future<void> appendSyncLogEntry(String line) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_keySyncLogEntries) ?? <String>[];
    existing.add(line);
    const maxEntries = 100;
    final trimmed =
        existing.length > maxEntries
            ? existing.sublist(existing.length - maxEntries)
            : existing;
    await prefs.setStringList(_keySyncLogEntries, trimmed);
  }

  Future<List<String>> getSyncLogEntries() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keySyncLogEntries) ?? <String>[];
  }

  Future<void> clearSyncLogEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySyncLogEntries);
  }

  Future<void> saveLastSyncLogTimestamp(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyLastSyncLogTimestamp,
      timestamp.toIso8601String(),
    );
  }

  Future<DateTime?> getLastSyncLogTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLastSyncLogTimestamp);
    if (raw == null) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }
}
