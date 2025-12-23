import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/feed.dart';

class BlacklistEntry {
  final int? id;
  final String pattern;
  final String? feedId; // null means all feeds
  final int accountId;

  BlacklistEntry({
    this.id,
    required this.pattern,
    this.feedId,
    required this.accountId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pattern': pattern,
      'feedId': feedId,
      'accountId': accountId,
    };
  }

  factory BlacklistEntry.fromMap(Map<String, dynamic> map) {
    return BlacklistEntry(
      id: map['id'] as int?,
      pattern: map['pattern'] as String,
      feedId: map['feedId'] as String?,
      accountId: map['accountId'] as int,
    );
  }

  BlacklistEntry copyWith({
    int? id,
    String? pattern,
    String? feedId,
    int? accountId,
  }) {
    return BlacklistEntry(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      feedId: feedId ?? this.feedId,
      accountId: accountId ?? this.accountId,
    );
  }
}

class BlacklistDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insert(BlacklistEntry entry) async {
    final db = await _dbHelper.database;
    return await db.insert('blacklist', entry.toMap());
  }

  Future<List<BlacklistEntry>> getAll(int accountId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'blacklist',
      where: 'accountId = ?',
      whereArgs: [accountId],
      orderBy: 'pattern ASC',
    );
    return maps.map((map) => BlacklistEntry.fromMap(map)).toList();
  }

  Future<BlacklistEntry?> getById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'blacklist',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return BlacklistEntry.fromMap(maps.first);
  }

  Future<int> update(BlacklistEntry entry) async {
    final db = await _dbHelper.database;
    return await db.update(
      'blacklist',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'blacklist',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Check if an article title matches any blacklist pattern for the given feed/account
  /// Returns true if the article should be blocked
  Future<bool> isBlocked(String articleId, String title, String feedId, int accountId) async {
    final db = await _dbHelper.database;
    
    // Check if this article is in the exception list first
    final exceptionMaps = await db.query(
      'blacklist_exception',
      where: 'articleId = ? AND accountId = ?',
      whereArgs: [articleId, accountId],
    );
    if (exceptionMaps.isNotEmpty) {
      return false; // Article is in exception list, don't block
    }
    
    // Get all blacklist entries for this account
    final maps = await db.query(
      'blacklist',
      where: 'accountId = ?',
      whereArgs: [accountId],
    );
    
    final entries = maps.map((map) => BlacklistEntry.fromMap(map)).toList();
    
    for (final entry in entries) {
      // Check if this entry applies to this feed (or all feeds)
      if (entry.feedId != null && entry.feedId != feedId) {
        continue; // This entry is for a different feed
      }
      
      // Check if title contains the pattern (case-insensitive)
      if (title.toLowerCase().contains(entry.pattern.toLowerCase())) {
        return true; // Blocked
      }
    }
    
    return false; // Not blocked
  }

  /// Add an article to the exception list (release it from blacklist)
  Future<void> addException(String articleId, int accountId) async {
    final db = await _dbHelper.database;
    await db.insert(
      'blacklist_exception',
      {
        'articleId': articleId,
        'accountId': accountId,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Remove an article from the exception list
  Future<void> removeException(String articleId, int accountId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'blacklist_exception',
      where: 'articleId = ? AND accountId = ?',
      whereArgs: [articleId, accountId],
    );
  }

  /// Get all blocked articles (articles that match blacklist but aren't in exception)
  /// Note: This only returns articles that are currently in the database.
  /// Articles blocked during sync are never inserted, so they won't appear here.
  /// This method is useful for viewing articles that were blocked before the blacklist was added.
  Future<List<Map<String, dynamic>>> getBlockedArticles(int accountId) async {
    final db = await _dbHelper.database;
    
    // Get all blacklist entries
    final blacklistEntries = await getAll(accountId);
    if (blacklistEntries.isEmpty) {
      return [];
    }
    
    // Get all exceptions
    final exceptionMaps = await db.query(
      'blacklist_exception',
      where: 'accountId = ?',
      whereArgs: [accountId],
    );
    final exceptionIds = exceptionMaps.map((e) => e['articleId'] as String).toSet();
    
    // Get all articles for this account
    final articleMaps = await db.query(
      'article',
      where: 'accountId = ?',
      whereArgs: [accountId],
      orderBy: 'date DESC',
    );
    
    // Find articles that match blacklist patterns
    final blockedArticles = <Map<String, dynamic>>[];
    
    for (final articleMap in articleMaps) {
      final title = articleMap['title'] as String;
      final articleId = articleMap['id'] as String;
      
      // Skip if in exception list
      if (exceptionIds.contains(articleId)) {
        continue;
      }
      
      // Check if title matches any blacklist pattern
      for (final entry in blacklistEntries) {
        if (title.toLowerCase().contains(entry.pattern.toLowerCase())) {
          // Check if this entry applies to this feed
          final feedId = articleMap['feedId'] as String;
          if (entry.feedId == null || entry.feedId == feedId) {
            // Get feed name
            final feedMaps = await db.query(
              'feed',
              where: 'id = ?',
              whereArgs: [feedId],
              limit: 1,
            );
            final feedName = feedMaps.isNotEmpty ? feedMaps.first['name'] as String : 'Unknown';
            
            blockedArticles.add({
              'id': articleId,
              'title': title,
              'feedId': feedId,
              'feedName': feedName,
              'date': articleMap['date'] as String,
              'blacklistPattern': entry.pattern,
            });
            break; // Only add once per article
          }
        }
      }
    }
    
    return blockedArticles;
  }
}

