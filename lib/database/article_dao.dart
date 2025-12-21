import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/article.dart';
import '../models/article_sort.dart';
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
      // Check for existing article by syncHash first (if available), then fall back to link check
      List<Map<String, dynamic>> existing = [];
      
      if (article.syncHash != null && article.syncHash!.isNotEmpty) {
        // Check by syncHash (preferred method for duplicate detection)
        existing = await db.query(
          'article',
          where: 'syncHash = ? AND accountId = ?',
          whereArgs: [article.syncHash, article.accountId],
          limit: 1,
        );
      }
      
      // Fall back to link check if syncHash check found nothing (for backward compatibility)
      if (existing.isEmpty) {
        existing = await db.query(
          'article',
          where: 'link = ? AND accountId = ?',
          whereArgs: [article.link, article.accountId],
          limit: 1,
        );
      }
      
      // Also check for same title in the same feed (prevents re-uploads of same article with new date)
      // Use case-insensitive comparison and trim whitespace
      if (existing.isEmpty) {
        existing = await db.rawQuery(
          '''
          SELECT * FROM article 
          WHERE TRIM(UPPER(title)) = TRIM(UPPER(?)) 
          AND feedId = ? 
          AND accountId = ?
          LIMIT 1
          ''',
          [article.title, article.feedId, article.accountId],
        );
      }

      if (existing.isEmpty) {
        try {
          // Check one more time if article with this ID already exists (primary key check)
          // This catches cases where the ID might have been reused
          final idCheck = await db.query(
            'article',
            where: 'id = ?',
            whereArgs: [article.id],
            limit: 1,
          );
          
          if (idCheck.isNotEmpty) {
            final existingById = Article.fromMap(idCheck.first);
            print('[ARTICLE_DAO] Article with ID ${article.id} already exists! Existing isUnread=${existingById.isUnread}, Existing title=${existingById.title}');
            // Skip insertion - article already exists with this ID
            // Preserve its read status by not updating it
            continue;
          }
          
          final articleMap = article.toMap();
          print('[ARTICLE_DAO] Inserting article: id=${article.id}, title=${article.title}, accountId=${article.accountId}');
          print('[ARTICLE_DAO] Article map accountId: ${articleMap['accountId']} (type: ${articleMap['accountId'].runtimeType})');
          await db.insert('article', articleMap, conflictAlgorithm: ConflictAlgorithm.fail);
          
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
        // Article already exists - preserve read status and update metadata if needed
        final existingArticle = Article.fromMap(existing.first);
        
        // Log what we found for debugging
        print('[ARTICLE_DAO] Article already exists: existingId=${existingArticle.id}, newId=${article.id}, existingIsUnread=${existingArticle.isUnread}, existingSyncHash=${existingArticle.syncHash}');
        
        // CRITICAL: Preserve read status - if existing article was read, make sure it stays read
        // The existing article's read status should already be preserved since we're not inserting
        // But let's ensure we don't accidentally mark it as unread by verifying the existing state
        
        // Update syncHash if it's missing (for backward compatibility)
        if (article.syncHash != null && article.syncHash!.isNotEmpty) {
          if (existingArticle.syncHash == null || existingArticle.syncHash!.isEmpty) {
            try {
              await db.update(
                'article',
                {'syncHash': article.syncHash},
                where: 'id = ?',
                whereArgs: [existingArticle.id],
              );
              print('[ARTICLE_DAO] Updated syncHash for existing article: ${existingArticle.id}');
            } catch (e) {
              print('[ARTICLE_DAO] Error updating syncHash: $e');
            }
          }
        }
        
        // If somehow the existing article became unread (shouldn't happen), preserve its read status
        // But we shouldn't need this since we're not inserting/updating it
        
        print('[ARTICLE_DAO] Skipped duplicate article: ${article.title} (existing ID: ${existingArticle.id})');
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
      {
        'isUnread': 0,
        'updateAt': DateTime.now().toUtc().toIso8601String(),
      },
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

  /// Sets updateAt to current date for all read articles that have NULL updateAt
  /// This helps with backward compatibility for articles marked as read before this feature
  Future<int> setUpdateAtForNullReadArticles(int accountId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    
    // Update all read articles (isUnread = 0) that have NULL updateAt to set it to now
    return await db.update(
      'article',
      {'updateAt': now},
      where: 'accountId = ? AND isUnread = 0 AND updateAt IS NULL',
      whereArgs: [accountId],
    );
  }

  /// Deletes read articles that were marked as read more than [keepReadItemsDays] days ago
  /// Only deletes articles that are not starred
  Future<int> deleteOldReadArticles(int accountId, int keepReadItemsDays) async {
    final db = await _dbHelper.database;
    final cutoffDate = DateTime.now().subtract(Duration(days: keepReadItemsDays));
    final cutoffDateStr = cutoffDate.toIso8601String();
    
    // Delete read articles (isUnread = 0) that are not starred and were marked as read before cutoff date
    // Only delete if updateAt is set (when it was marked as read) and is older than cutoff
    return await db.delete(
      'article',
      where: 'accountId = ? AND isUnread = 0 AND isStarred = 0 AND updateAt IS NOT NULL AND updateAt < ?',
      whereArgs: [accountId, cutoffDateStr],
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

  /// Search articles with full-text search across title, content, and author
  /// Supports filters: feedId, date range, starred, unread
  Future<List<Article>> search({
    required int accountId,
    required String query,
    String? feedId,
    DateTime? startDate,
    DateTime? endDate,
    bool? starred,
    bool? unread,
    int limit = 500,
  }) async {
    final db = await _dbHelper.database;
    
    // Build WHERE clause
    final whereParts = <String>['accountId = ?'];
    final whereArgs = <dynamic>[accountId];
    
    // Add search query
    if (query.isNotEmpty) {
      whereParts.add('(title LIKE ? OR shortDescription LIKE ? OR rawDescription LIKE ? OR author LIKE ? OR fullContent LIKE ?)');
      final searchPattern = '%$query%';
      whereArgs.addAll([searchPattern, searchPattern, searchPattern, searchPattern, searchPattern]);
    }
    
    // Add feed filter
    if (feedId != null && feedId.isNotEmpty) {
      whereParts.add('feedId = ?');
      whereArgs.add(feedId);
    }
    
    // Add date range filter
    if (startDate != null) {
      whereParts.add('date >= ?');
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      whereParts.add('date <= ?');
      whereArgs.add(endDate.toIso8601String());
    }
    
    // Add starred filter
    if (starred != null) {
      whereParts.add('isStarred = ?');
      whereArgs.add(starred ? 1 : 0);
    }
    
    // Add unread filter
    if (unread != null) {
      whereParts.add('isUnread = ?');
      whereArgs.add(unread ? 1 : 0);
    }
    
    final whereClause = whereParts.join(' AND ');
    
    final maps = await db.query(
      'article',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'date DESC',
      limit: limit,
    );
    
    return maps.map((map) => Article.fromMap(map)).toList();
  }

  /// Batch mark articles as read
  Future<int> batchMarkAsRead(List<String> articleIds) async {
    if (articleIds.isEmpty) return 0;
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final placeholders = articleIds.map((_) => '?').join(',');
    return await db.rawUpdate(
      'UPDATE article SET isUnread = 0, updateAt = ? WHERE id IN ($placeholders)',
      [now, ...articleIds],
    );
  }

  /// Batch mark articles as unread
  Future<int> batchMarkAsUnread(List<String> articleIds) async {
    if (articleIds.isEmpty) return 0;
    final db = await _dbHelper.database;
    final placeholders = articleIds.map((_) => '?').join(',');
    return await db.rawUpdate(
      'UPDATE article SET isUnread = 1 WHERE id IN ($placeholders)',
      articleIds,
    );
  }

  /// Batch star articles
  Future<int> batchStar(List<String> articleIds) async {
    if (articleIds.isEmpty) return 0;
    final db = await _dbHelper.database;
    final placeholders = articleIds.map((_) => '?').join(',');
    return await db.rawUpdate(
      'UPDATE article SET isStarred = 1 WHERE id IN ($placeholders)',
      articleIds,
    );
  }

  /// Batch unstar articles
  Future<int> batchUnstar(List<String> articleIds) async {
    if (articleIds.isEmpty) return 0;
    final db = await _dbHelper.database;
    final placeholders = articleIds.map((_) => '?').join(',');
    return await db.rawUpdate(
      'UPDATE article SET isStarred = 0 WHERE id IN ($placeholders)',
      articleIds,
    );
  }

  /// Batch delete articles
  Future<int> batchDelete(List<String> articleIds) async {
    if (articleIds.isEmpty) return 0;
    final db = await _dbHelper.database;
    final placeholders = articleIds.map((_) => '?').join(',');
    return await db.rawDelete(
      'DELETE FROM article WHERE id IN ($placeholders)',
      articleIds,
    );
  }

  /// Get articles with sorting
  Future<List<Article>> getArticlesWithSort({
    required int accountId,
    required ArticleSortOption sortOption,
    String? feedId,
    bool? unread,
    bool? starred,
    int limit = 500,
  }) async {
    final db = await _dbHelper.database;
    
    final whereParts = <String>['accountId = ?'];
    final whereArgs = <dynamic>[accountId];
    
    if (feedId != null && feedId.isNotEmpty) {
      whereParts.add('feedId = ?');
      whereArgs.add(feedId);
    }
    
    if (unread != null) {
      whereParts.add('isUnread = ?');
      whereArgs.add(unread ? 1 : 0);
    }
    
    if (starred != null) {
      whereParts.add('isStarred = ?');
      whereArgs.add(starred ? 1 : 0);
    }
    
    final whereClause = whereParts.join(' AND ');
    
    // Build ORDER BY clause
    String orderBy;
    switch (sortOption) {
      case ArticleSortOption.dateDesc:
        orderBy = 'date DESC';
        break;
      case ArticleSortOption.dateAsc:
        orderBy = 'date ASC';
        break;
      case ArticleSortOption.titleAsc:
        orderBy = 'title ASC';
        break;
      case ArticleSortOption.titleDesc:
        orderBy = 'title DESC';
        break;
      case ArticleSortOption.authorAsc:
        orderBy = 'author ASC, date DESC';
        break;
      case ArticleSortOption.authorDesc:
        orderBy = 'author DESC, date DESC';
        break;
      case ArticleSortOption.feedAsc:
      case ArticleSortOption.feedDesc:
        // For feed sorting, we need to join with feed table
        // This is handled separately with a raw query
        orderBy = 'date DESC';
        break;
    }
    
    List<Map<String, dynamic>> maps;
    
    if (sortOption == ArticleSortOption.feedAsc || sortOption == ArticleSortOption.feedDesc) {
      // Use raw query with JOIN for feed sorting
      final feedOrder = sortOption == ArticleSortOption.feedAsc ? 'ASC' : 'DESC';
      final query = '''
        SELECT a.* FROM article a
        INNER JOIN feed f ON a.feedId = f.id
        WHERE ${whereClause.replaceAll('accountId = ?', 'a.accountId = ?')}
        ORDER BY f.name $feedOrder, a.date DESC
        LIMIT ?
      ''';
      maps = await db.rawQuery(query, [...whereArgs, limit]);
    } else {
      maps = await db.query(
        'article',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
      );
    }
    
    return maps.map((map) => Article.fromMap(map)).toList();
  }
}

