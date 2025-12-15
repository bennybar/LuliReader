import '../database/database_helper.dart';
import '../models/article.dart';
import '../models/feed.dart';

class ArticleDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insert(Article article) async {
    final db = await _dbHelper.database;
    await db.insert('article', article.toMap());
  }

  Future<List<Article>> insertListIfNotExist({
    required List<Article> articles,
    required Feed feed,
  }) async {
    final db = await _dbHelper.database;
    final List<Article> newArticles = [];

    for (final article in articles) {
      final existing = await db.query(
        'article',
        where: 'link = ? AND accountId = ?',
        whereArgs: [article.link, article.accountId],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.insert('article', article.toMap());
        newArticles.add(article);
      }
    }

    return newArticles;
  }

  Future<Article?> getById(String id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'article',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return Article.fromMap(maps.first);
  }

  Future<List<Article>> getByFeedId(String feedId, {int limit = 100}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'article',
      where: 'feedId = ?',
      whereArgs: [feedId],
      orderBy: 'date DESC',
      limit: limit,
    );
    return maps.map((map) => Article.fromMap(map)).toList();
  }

  Future<List<Article>> getUnread(int accountId, {int limit = 100}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'article',
      where: 'accountId = ? AND isUnread = 1',
      whereArgs: [accountId],
      orderBy: 'date DESC',
      limit: limit,
    );
    return maps.map((map) => Article.fromMap(map)).toList();
  }

  Future<List<Article>> getStarred(int accountId, {int limit = 100}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'article',
      where: 'accountId = ? AND isStarred = 1',
      whereArgs: [accountId],
      orderBy: 'date DESC',
      limit: limit,
    );
    return maps.map((map) => Article.fromMap(map)).toList();
  }

  Future<int> update(Article article) async {
    final db = await _dbHelper.database;
    return await db.update(
      'article',
      article.toMap(),
      where: 'id = ?',
      whereArgs: [article.id],
    );
  }

  Future<int> markAsRead(String id) async {
    final db = await _dbHelper.database;
    return await db.update(
      'article',
      {'isUnread': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> markAsUnread(String id) async {
    final db = await _dbHelper.database;
    return await db.update(
      'article',
      {'isUnread': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> toggleStarred(String id) async {
    final db = await _dbHelper.database;
    final article = await getById(id);
    if (article == null) return 0;
    return await db.update(
      'article',
      {'isStarred': article.isStarred ? 0 : 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(String id) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'article',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteOldArticles(int accountId, DateTime beforeDate) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'article',
      where: 'accountId = ? AND date < ? AND isUnread = 0 AND isStarred = 0',
      whereArgs: [accountId, beforeDate.toIso8601String()],
    );
  }

  Future<List<Article>> getAllArticles(int accountId, {int limit = 500}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'article',
      where: 'accountId = ?',
      whereArgs: [accountId],
      orderBy: 'date DESC',
      limit: limit,
    );
    return maps.map((map) => Article.fromMap(map)).toList();
  }

  Future<ArticleWithFeed?> getWithFeed(String articleId) async {
    final db = await _dbHelper.database;
    final article = await getById(articleId);
    if (article == null) return null;

    final feedMaps = await db.query(
      'feed',
      where: 'id = ?',
      whereArgs: [article.feedId],
      limit: 1,
    );

    if (feedMaps.isEmpty) return null;
    final feed = Feed.fromMap(feedMaps.first);
    return ArticleWithFeed(article: article, feed: feed as dynamic);
  }
}

