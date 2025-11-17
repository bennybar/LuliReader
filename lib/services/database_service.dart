import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/article.dart';
import '../models/feed.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'lulireader.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Feeds table
    await db.execute('''
      CREATE TABLE feeds (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        websiteUrl TEXT,
        iconUrl TEXT,
        lastSyncDate TEXT,
        unreadCount INTEGER DEFAULT 0,
        lastArticleDate TEXT
      )
    ''');

    // Articles table
    await db.execute('''
      CREATE TABLE articles (
        id TEXT PRIMARY KEY,
        feedId TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT,
        summary TEXT,
        author TEXT,
        publishedDate TEXT NOT NULL,
        updatedDate TEXT,
        link TEXT,
        imageUrl TEXT,
        isRead INTEGER DEFAULT 0,
        isStarred INTEGER DEFAULT 0,
        lastSyncedAt TEXT,
        FOREIGN KEY (feedId) REFERENCES feeds (id) ON DELETE CASCADE
      )
    ''');

    // Indexes
    await db.execute('CREATE INDEX idx_articles_feedId ON articles(feedId)');
    await db.execute('CREATE INDEX idx_articles_publishedDate ON articles(publishedDate DESC)');
    await db.execute('CREATE INDEX idx_articles_isRead ON articles(isRead)');
    await db.execute('CREATE INDEX idx_articles_isStarred ON articles(isStarred)');
  }

  // Feed operations
  Future<void> insertFeed(Feed feed) async {
    final db = await database;
    await db.insert('feeds', feed.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Feed>> getAllFeeds() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('feeds', orderBy: 'title ASC');
    return List.generate(maps.length, (i) => Feed.fromMap(maps[i]));
  }

  Future<Feed?> getFeed(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'feeds',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Feed.fromMap(maps.first);
  }

  Future<void> updateFeed(Feed feed) async {
    final db = await database;
    await db.update('feeds', feed.toMap(), where: 'id = ?', whereArgs: [feed.id]);
  }

  Future<void> deleteFeed(String id) async {
    final db = await database;
    await db.delete('feeds', where: 'id = ?', whereArgs: [id]);
  }

  // Article operations
  Future<void> insertArticle(Article article) async {
    final db = await database;
    await db.insert('articles', article.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertArticles(List<Article> articles) async {
    final db = await database;
    final batch = db.batch();
    for (var article in articles) {
      batch.insert(
        'articles',
        article.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    print('Upserted ${articles.length} articles');
  }

  Future<List<Article>> getArticles({
    String? feedId,
    bool? isRead,
    bool? isStarred,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    String where = '1=1';
    List<dynamic> whereArgs = [];

    if (feedId != null) {
      where += ' AND feedId = ?';
      whereArgs.add(feedId);
    }
    if (isRead != null) {
      where += ' AND isRead = ?';
      whereArgs.add(isRead ? 1 : 0);
    }
    if (isStarred != null) {
      where += ' AND isStarred = ?';
      whereArgs.add(isStarred ? 1 : 0);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'publishedDate DESC',
      limit: limit,
      offset: offset,
    );
    return List.generate(maps.length, (i) => Article.fromMap(maps[i]));
  }

  Future<Article?> getArticle(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'articles',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Article.fromMap(maps.first);
  }

  Future<void> updateArticle(Article article) async {
    final db = await database;
    await db.update('articles', article.toMap(), where: 'id = ?', whereArgs: [article.id]);
  }

  Future<void> markArticleAsRead(String id, bool isRead) async {
    final db = await database;
    await db.update(
      'articles',
      {'isRead': isRead ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markArticleAsStarred(String id, bool isStarred) async {
    final db = await database;
    await db.update(
      'articles',
      {'isStarred': isStarred ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markMultipleArticlesAsRead(List<String> ids, bool isRead) async {
    final db = await database;
    final batch = db.batch();
    for (var id in ids) {
      batch.update(
        'articles',
        {'isRead': isRead ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> markAllArticlesAsRead(bool isRead) async {
    final db = await database;
    await db.update('articles', {'isRead': isRead ? 1 : 0});
  }

  Future<int> getUnreadCount({String? feedId}) async {
    final db = await database;
    String where = 'isRead = 0';
    List<dynamic> whereArgs = [];
    if (feedId != null) {
      where += ' AND feedId = ?';
      whereArgs.add(feedId);
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM articles WHERE $where',
      whereArgs,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }

  Future<List<String>> getAllArticleIds() async {
    final db = await database;
    final result = await db.query(
      'articles',
      columns: ['id'],
    );
    return result.map((row) => row['id'] as String).toList();
  }
}

