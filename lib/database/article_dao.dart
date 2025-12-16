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
    print('[ARTICLE_DAO] insertListIfNotExist: ${articles.length} articles for feed ${feed.name} (id=${feed.id})');
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
        try {
          final articleMap = article.toMap();
          print('[ARTICLE_DAO] Inserting article: id=${article.id}, accountId=${article.accountId} (type: ${article.accountId.runtimeType})');
          print('[ARTICLE_DAO] Article map accountId: ${articleMap['accountId']} (type: ${articleMap['accountId'].runtimeType})');
          await db.insert('article', articleMap);
          
          // Verify insertion immediately with a small delay to ensure commit
          await Future.delayed(const Duration(milliseconds: 10));
          final verify = await db.query(
            'article',
            where: 'id = ?',
            whereArgs: [article.id],
            limit: 1,
          );
          if (verify.isNotEmpty) {
            final verifiedAccountId = verify.first['accountId'];
            print('[ARTICLE_DAO] ✓ Verified article inserted: id=${article.id}, accountId=$verifiedAccountId (type: ${verifiedAccountId.runtimeType})');
            newArticles.add(article);
          } else {
            print('[ARTICLE_DAO] ✗ ERROR: Article not found after insertion! id=${article.id}');
            // Try raw query
            final rawVerify = await db.rawQuery(
              'SELECT * FROM article WHERE id = ?',
              [article.id],
            );
            print('[ARTICLE_DAO] Raw query verification: ${rawVerify.length} rows');
          }
        } catch (e, stackTrace) {
          print('[ARTICLE_DAO] ERROR inserting article ${article.id}: $e');
          print('[ARTICLE_DAO] Stack trace: $stackTrace');
        }
      } else {
        print('[ARTICLE_DAO] Article already exists: ${article.id}');
      }
    }

    print('[ARTICLE_DAO] Inserted ${newArticles.length} new articles');
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
    print('[ARTICLE_DAO] getUnread called: accountId=$accountId, limit=$limit');
    final db = await _dbHelper.database;
    final maps = await db.query(
      'article',
      where: 'accountId = ? AND isUnread = 1',
      whereArgs: [accountId],
      orderBy: 'date DESC',
      limit: limit,
    );
    print('[ARTICLE_DAO] getUnread returned ${maps.length} articles');
    return maps.map((map) => Article.fromMap(map)).toList();
  }

  Future<List<Article>> getStarred(int accountId, {int limit = 100}) async {
    print('[ARTICLE_DAO] getStarred called: accountId=$accountId, limit=$limit');
    final db = await _dbHelper.database;
    final maps = await db.query(
      'article',
      where: 'accountId = ? AND isStarred = 1',
      whereArgs: [accountId],
      orderBy: 'date DESC',
      limit: limit,
    );
    print('[ARTICLE_DAO] getStarred returned ${maps.length} articles');
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

  Future<int> countByAccountId(int accountId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM article WHERE accountId = ?',
      [accountId],
    );
    return result.first['count'] as int;
  }

  Future<int> countByFeedId(String feedId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM article WHERE feedId = ?',
      [feedId],
    );
    if (result.isNotEmpty && result.first['cnt'] != null) {
      return (result.first['cnt'] as int?) ?? 0;
    }
    return 0;
  }

  Future<Article?> latestByFeedId(String feedId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'article',
      where: 'feedId = ?',
      whereArgs: [feedId],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Article.fromMap(maps.first);
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
    print('[ARTICLE_DAO] getAllArticles called: accountId=$accountId (type: ${accountId.runtimeType}), limit=$limit');
    final db = await _dbHelper.database;
    print('[ARTICLE_DAO] Database opened, querying articles...');
    
    // First, check what accountIds actually exist in the database
    final accountIdCheck = await db.rawQuery('SELECT DISTINCT accountId FROM article LIMIT 10');
    print('[ARTICLE_DAO] Distinct accountIds in database: $accountIdCheck');
    
    // Also check total count
    final totalCount = await db.rawQuery('SELECT COUNT(*) as count FROM article');
    print('[ARTICLE_DAO] Total article count in database: ${totalCount.first['count']}');
    
    // Check count by accountId
    final countByAccount = await db.rawQuery(
      'SELECT accountId, COUNT(*) as count FROM article GROUP BY accountId',
    );
    print('[ARTICLE_DAO] Article count by accountId: $countByAccount');
    
    // Try query with integer
    var maps = await db.query(
      'article',
      where: 'accountId = ?',
      whereArgs: [accountId],
      orderBy: 'date DESC',
      limit: limit,
    );
    print('[ARTICLE_DAO] Query with accountId=$accountId (int) returned ${maps.length} rows');
    
    // If empty, try with string
    if (maps.isEmpty) {
      print('[ARTICLE_DAO] Trying query with accountId as string...');
      maps = await db.query(
        'article',
        where: 'accountId = ?',
        whereArgs: [accountId.toString()],
        orderBy: 'date DESC',
        limit: limit,
      );
      print('[ARTICLE_DAO] Query with accountId="${accountId.toString()}" (string) returned ${maps.length} rows');
    }
    
    // If still empty, get all articles and check
    if (maps.isEmpty) {
      print('[ARTICLE_DAO] WARNING: No articles found for accountId=$accountId');
      final allMaps = await db.query('article', limit: 10);
      print('[ARTICLE_DAO] Total articles in database: ${allMaps.length}');
      if (allMaps.isNotEmpty) {
        for (int i = 0; i < allMaps.length && i < 3; i++) {
          final map = allMaps[i];
          print('[ARTICLE_DAO] Sample article[$i]: id=${map['id']}, accountId=${map['accountId']} (type: ${map['accountId'].runtimeType}), title=${map['title']}');
        }
        // Try to find articles with matching accountId using raw query
        final rawQuery = await db.rawQuery(
          'SELECT * FROM article WHERE accountId = ? LIMIT 10',
          [accountId],
        );
        print('[ARTICLE_DAO] Raw query with accountId=$accountId returned ${rawQuery.length} rows');
        if (rawQuery.isEmpty) {
          // Try casting
          final castQuery = await db.rawQuery(
            'SELECT * FROM article WHERE CAST(accountId AS INTEGER) = ? LIMIT 10',
            [accountId],
          );
          print('[ARTICLE_DAO] Cast query returned ${castQuery.length} rows');
          maps = castQuery;
        } else {
          maps = rawQuery;
        }
      }
    } else {
      print('[ARTICLE_DAO] First article: id=${maps.first['id']}, title=${maps.first['title']}, accountId=${maps.first['accountId']} (type: ${maps.first['accountId'].runtimeType})');
    }
    
    final articles = maps.map((map) {
      try {
        return Article.fromMap(map);
      } catch (e) {
        print('[ARTICLE_DAO] ERROR parsing article: $e, map=$map');
        rethrow;
      }
    }).toList();
    print('[ARTICLE_DAO] Parsed ${articles.length} articles successfully');
    return articles;
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

