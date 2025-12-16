import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SyncLogEntry {
  final DateTime timestamp;
  final String type; // 'manual', 'background', 'startup'
  final bool success;
  final String? error;
  final int? articlesSynced;

  SyncLogEntry({
    required this.timestamp,
    required this.type,
    required this.success,
    this.error,
    this.articlesSynced,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'success': success,
      'error': error,
      'articlesSynced': articlesSynced,
    };
  }

  factory SyncLogEntry.fromJson(Map<String, dynamic> json) {
    return SyncLogEntry(
      timestamp: DateTime.parse(json['timestamp']),
      type: json['type'],
      success: json['success'],
      error: json['error'],
      articlesSynced: json['articlesSynced'],
    );
  }
}

class SyncLogService {
  static const String _logKey = 'sync_log_entries';
  static const int _maxEntries = 100;

  Future<void> addLogEntry(SyncLogEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final logsJson = prefs.getStringList(_logKey) ?? [];
    
    final newLogJson = jsonEncode(entry.toJson());
    logsJson.insert(0, newLogJson);
    
    // Keep only the last _maxEntries entries
    if (logsJson.length > _maxEntries) {
      logsJson.removeRange(_maxEntries, logsJson.length);
    }
    
    await prefs.setStringList(_logKey, logsJson);
  }

  Future<List<SyncLogEntry>> getLogEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final logsJson = prefs.getStringList(_logKey) ?? [];
    
    return logsJson.map((jsonStr) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return SyncLogEntry.fromJson(json);
      } catch (e) {
        return null;
      }
    }).whereType<SyncLogEntry>().toList();
  }

  Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_logKey);
  }
}

