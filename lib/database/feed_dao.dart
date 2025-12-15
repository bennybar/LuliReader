import '../database/database_helper.dart';
import '../models/feed.dart';
import '../models/article.dart';

class FeedDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insert(Feed feed) async {
    final db = await _dbHelper.database;
    await db.insert('feed', feed.toMap());
  }

  Future<void> insertList(List<Feed> feeds) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final feed in feeds) {
      batch.insert('feed', feed.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<Feed?> getById(String id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'feed',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return Feed.fromMap(maps.first);
  }

  Future<List<Feed>> getAll(int accountId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'feed',
      where: 'accountId = ?',
      whereArgs: [accountId],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Feed.fromMap(map)).toList();
  }

  Future<List<Feed>> getByGroupId(int accountId, String groupId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'feed',
      where: 'accountId = ? AND groupId = ?',
      whereArgs: [accountId, groupId],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Feed.fromMap(map)).toList();
  }

  Future<int> update(Feed feed) async {
    final db = await _dbHelper.database;
    return await db.update(
      'feed',
      feed.toMap(),
      where: 'id = ?',
      whereArgs: [feed.id],
    );
  }

  Future<int> delete(String id) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'feed',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> isFeedExist(String url) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'feed',
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  Future<List<Article>> getArchivedArticles(String feedId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'article',
      where: 'feedId = ? AND isUnread = 0',
      whereArgs: [feedId],
    );
    return maps.map((map) => Article.fromMap(map)).toList();
  }
}

