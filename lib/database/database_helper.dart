import 'package:sqflite/sqflite.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:path/path.dart';
import '../models/account.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/group.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('luli_reader.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    print('[DB_HELPER] Database path: $path');
    print('[DB_HELPER] Database file exists: ${await sqflite.databaseExists(path)}');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Account table
    await db.execute('''
      CREATE TABLE account (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type INTEGER NOT NULL,
        updateAt TEXT,
        lastArticleId TEXT,
        syncInterval INTEGER DEFAULT 30,
        syncOnStart INTEGER DEFAULT 0,
        syncOnlyOnWiFi INTEGER DEFAULT 0,
        syncOnlyWhenCharging INTEGER DEFAULT 0,
        keepArchived INTEGER DEFAULT 2592000000,
        syncBlockList TEXT DEFAULT '',
        isFullContent INTEGER DEFAULT 0,
        swipeStartAction INTEGER DEFAULT 2,
        swipeEndAction INTEGER DEFAULT 1
      )
    ''');

    // Group table
    await db.execute('''
      CREATE TABLE "group" (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        accountId INTEGER NOT NULL,
        isRtl INTEGER,
        FOREIGN KEY (accountId) REFERENCES account (id) ON DELETE CASCADE ON UPDATE CASCADE
      )
    ''');

    // Feed table
    await db.execute('''
      CREATE TABLE feed (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT,
        url TEXT NOT NULL,
        groupId TEXT NOT NULL,
        accountId INTEGER NOT NULL,
        isNotification INTEGER DEFAULT 0,
        isFullContent INTEGER DEFAULT 0,
        isBrowser INTEGER DEFAULT 0,
        isRtl INTEGER,
        FOREIGN KEY (groupId) REFERENCES "group" (id) ON DELETE CASCADE ON UPDATE CASCADE,
        FOREIGN KEY (accountId) REFERENCES account (id) ON DELETE CASCADE ON UPDATE CASCADE
      )
    ''');

    // Article table
    await db.execute('''
      CREATE TABLE article (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        title TEXT NOT NULL,
        author TEXT,
        rawDescription TEXT NOT NULL,
        shortDescription TEXT NOT NULL,
        img TEXT,
        link TEXT NOT NULL,
        feedId TEXT NOT NULL,
        accountId INTEGER NOT NULL,
        isUnread INTEGER DEFAULT 1,
        isStarred INTEGER DEFAULT 0,
        isReadLater INTEGER DEFAULT 0,
        updateAt TEXT,
        fullContent TEXT,
        FOREIGN KEY (feedId) REFERENCES feed (id) ON DELETE CASCADE ON UPDATE CASCADE
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_article_feedId ON article(feedId)');
    await db.execute('CREATE INDEX idx_article_accountId ON article(accountId)');
    await db.execute('CREATE INDEX idx_feed_groupId ON feed(groupId)');
    await db.execute('CREATE INDEX idx_feed_accountId ON feed(accountId)');
    await db.execute('CREATE INDEX idx_group_accountId ON "group"(accountId)');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add isRtl column to feed table
      try {
        await db.execute('ALTER TABLE feed ADD COLUMN isRtl INTEGER');
      } catch (e) {
        // Column might already exist
        print('Error adding isRtl to feed: $e');
      }
      // Add isRtl column to group table
      try {
        await db.execute('ALTER TABLE "group" ADD COLUMN isRtl INTEGER');
      } catch (e) {
        // Column might already exist
        print('Error adding isRtl to group: $e');
      }
      // Add swipe gesture columns to account table
      try {
        await db.execute('ALTER TABLE account ADD COLUMN swipeStartAction INTEGER DEFAULT 2');
      } catch (e) {
        print('Error adding swipeStartAction to account: $e');
      }
      try {
        await db.execute('ALTER TABLE account ADD COLUMN swipeEndAction INTEGER DEFAULT 1');
      } catch (e) {
        print('Error adding swipeEndAction to account: $e');
      }
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}

