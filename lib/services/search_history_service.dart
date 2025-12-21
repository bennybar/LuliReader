import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryService {
  static const String _keyPrefix = 'search_history_';
  static const int _maxHistoryItems = 20;

  Future<List<String>> getSearchHistory(int accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix$accountId';
    final history = prefs.getStringList(key) ?? [];
    return history.reversed.toList(); // Return most recent first
  }

  Future<void> addSearchQuery(int accountId, String query) async {
    if (query.trim().isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix$accountId';
    final history = prefs.getStringList(key) ?? [];
    
    // Remove duplicate if exists
    history.remove(query.trim());
    
    // Add to beginning
    history.insert(0, query.trim());
    
    // Limit to max items
    if (history.length > _maxHistoryItems) {
      history.removeRange(_maxHistoryItems, history.length);
    }
    
    await prefs.setStringList(key, history);
  }

  Future<void> clearSearchHistory(int accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix$accountId';
    await prefs.remove(key);
  }

  Future<void> removeSearchQuery(int accountId, String query) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix$accountId';
    final history = prefs.getStringList(key) ?? [];
    history.remove(query);
    await prefs.setStringList(key, history);
  }
}






