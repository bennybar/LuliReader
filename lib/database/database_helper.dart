import 'package:sqflite/sqflite.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:path/path.dart';
import '../models/account.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/group.dart';
import '../utils/link_normalizer.dart';

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
      version: 8,
      onConfigure: (db) async {
        // Enable foreign key cascade (e.g., deleting a feed removes its articles).
        await db.execute('PRAGMA foreign_keys = ON');
      },
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
        apiEndpoint TEXT,
        username TEXT,
        password TEXT,
        authToken TEXT,
        syncInterval INTEGER DEFAULT 30,
        syncOnStart INTEGER DEFAULT 0,
        syncOnlyOnWiFi INTEGER DEFAULT 0,
        syncOnlyWhenCharging INTEGER DEFAULT 0,
        keepArchived INTEGER DEFAULT 2592000000,
        syncBlockList TEXT DEFAULT '',
        isFullContent INTEGER DEFAULT 0,
        swipeStartAction INTEGER DEFAULT 2,
        swipeEndAction INTEGER DEFAULT 1,
        defaultScreen INTEGER DEFAULT 1,
        lastFlowFilter TEXT DEFAULT 'all',
        maxPastDays INTEGER DEFAULT 10
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
        normalizedLink TEXT,
        feedId TEXT NOT NULL,
        accountId INTEGER NOT NULL,
        isUnread INTEGER DEFAULT 1,
        isStarred INTEGER DEFAULT 0,
        isReadLater INTEGER DEFAULT 0,
        updateAt TEXT,
        fullContent TEXT,
        syncHash TEXT,
        FOREIGN KEY (feedId) REFERENCES feed (id) ON DELETE CASCADE ON UPDATE CASCADE
      )
    ''');

    // Read history table - used to prevent resurfacing of previously read items
    await db.execute('''
      CREATE TABLE read_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountId INTEGER NOT NULL,
        feedId TEXT,
        link TEXT,
        normalizedLink TEXT,
        syncHash TEXT,
        title TEXT,
        readAt TEXT NOT NULL
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_article_feedId ON article(feedId)');
    await db.execute('CREATE INDEX idx_article_accountId ON article(accountId)');
    await db.execute('CREATE INDEX idx_article_syncHash ON article(syncHash)');
    await db.execute('CREATE INDEX idx_article_normalizedLink ON article(normalizedLink)');
    await db.execute('CREATE INDEX idx_read_history_accountId ON read_history(accountId)');
    await db.execute('CREATE INDEX idx_read_history_lookup ON read_history(accountId, syncHash, link, feedId)');
    await db.execute('CREATE UNIQUE INDEX idx_read_history_unique_link ON read_history(accountId, link)');
    await db.execute('CREATE UNIQUE INDEX idx_read_history_unique_syncHash ON read_history(accountId, syncHash)');
    await db.execute('CREATE UNIQUE INDEX idx_read_history_unique_normallink ON read_history(accountId, normalizedLink)');
    await db.execute('CREATE INDEX idx_feed_groupId ON feed(groupId)');
    await db.execute('CREATE INDEX idx_feed_accountId ON feed(accountId)');
    await db.execute('CREATE INDEX idx_group_accountId ON "group"(accountId)');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      // Add defaultScreen and lastFlowFilter columns to account table
      try {
        await db.execute('ALTER TABLE account ADD COLUMN defaultScreen INTEGER DEFAULT 1');
      } catch (e) {
        print('Error adding defaultScreen to account: $e');
      }
      try {
        await db.execute('ALTER TABLE account ADD COLUMN lastFlowFilter TEXT DEFAULT \'all\'');
      } catch (e) {
        print('Error adding lastFlowFilter to account: $e');
      }
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE account ADD COLUMN maxPastDays INTEGER DEFAULT 10');
      } catch (e) {
        print('Error adding maxPastDays to account: $e');
      }
    }
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE account ADD COLUMN apiEndpoint TEXT');
      } catch (e) {
        print('Error adding apiEndpoint to account: $e');
      }
      try {
        await db.execute('ALTER TABLE account ADD COLUMN username TEXT');
      } catch (e) {
        print('Error adding username to account: $e');
      }
      try {
        await db.execute('ALTER TABLE account ADD COLUMN password TEXT');
      } catch (e) {
        print('Error adding password to account: $e');
      }
      try {
        await db.execute('ALTER TABLE account ADD COLUMN authToken TEXT');
      } catch (e) {
        print('Error adding authToken to account: $e');
      }
    }
    if (oldVersion < 6) {
      // Add syncHash column to article table for duplicate detection
      try {
        await db.execute('ALTER TABLE article ADD COLUMN syncHash TEXT');
      } catch (e) {
        print('Error adding syncHash to article: $e');
      }
      // Create index on syncHash for performance
      try {
        await db.execute('CREATE INDEX idx_article_syncHash ON article(syncHash)');
      } catch (e) {
        print('Error creating syncHash index: $e');
      }
    }
    if (oldVersion < 7) {
      // Add read_history table to keep a durable record of read items
      try {
        await db.execute('''
          CREATE TABLE read_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            accountId INTEGER NOT NULL,
            feedId TEXT,
            link TEXT,
            normalizedLink TEXT,
            syncHash TEXT,
            title TEXT,
            readAt TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_read_history_accountId ON read_history(accountId)');
        await db.execute('CREATE INDEX idx_read_history_lookup ON read_history(accountId, syncHash, link, feedId)');
        await db.execute('CREATE UNIQUE INDEX idx_read_history_unique_link ON read_history(accountId, link)');
        await db.execute('CREATE UNIQUE INDEX idx_read_history_unique_syncHash ON read_history(accountId, syncHash)');

        // Seed history from existing read articles so previously read items don't resurface
        await db.execute('''
          INSERT OR IGNORE INTO read_history (accountId, feedId, link, syncHash, title, readAt)
          SELECT accountId, feedId, link, syncHash, title, COALESCE(updateAt, datetime('now')) 
          FROM article 
          WHERE isUnread = 0
        ''');
      } catch (e) {
        print('Error creating read_history table: $e');
      }
    }
    if (oldVersion < 8) {
      // Add normalizedLink column and backfill for better duplicate detection
      try {
        await db.execute('ALTER TABLE article ADD COLUMN normalizedLink TEXT');
      } catch (e) {
        print('Error adding normalizedLink to article: $e');
      }
      try {
        await db.execute('ALTER TABLE read_history ADD COLUMN normalizedLink TEXT');
      } catch (e) {
        print('Error adding normalizedLink to read_history: $e');
      }

      // Backfill normalizedLink values in Dart to apply consistent normalization rules
      try {
        final articles = await db.query('article', columns: ['id', 'link']);
        for (final row in articles) {
          final id = row['id'] as String?;
          final link = row['link'] as String? ?? '';
          if (id == null) continue;
          final normalized = LinkNormalizer.normalize(link);
          await db.update(
            'article',
            {'normalizedLink': normalized},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      } catch (e) {
        print('Error backfilling normalizedLink on article: $e');
      }

      try {
        final historyRows = await db.query('read_history', columns: ['id', 'link']);
        for (final row in historyRows) {
          final id = row['id'] as int?;
          final link = row['link'] as String? ?? '';
          if (id == null) continue;
          final normalized = LinkNormalizer.normalize(link);
          await db.update(
            'read_history',
            {'normalizedLink': normalized},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      } catch (e) {
        print('Error backfilling normalizedLink on read_history: $e');
      }

      try {
        await db.execute('CREATE INDEX idx_article_normalizedLink ON article(normalizedLink)');
      } catch (e) {
        print('Error creating idx_article_normalizedLink: $e');
      }
      try {
        await db.execute('CREATE UNIQUE INDEX idx_read_history_unique_normallink ON read_history(accountId, normalizedLink)');
      } catch (e) {
        print('Error creating idx_read_history_unique_normallink: $e');
      }
    }
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

  /// Clears all local articles and resets sync markers so a fresh sync can run.
  /// Keeps accounts, feeds, and groups intact.
  Future<void> clearArticlesAndSyncState() async {
    final db = await database;
    await db.delete('article');
    await db.update(
      'account',
      {
        'lastArticleId': null,
        'updateAt': null,
      },
    );
  }
}

