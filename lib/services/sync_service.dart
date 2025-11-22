import '../models/user_config.dart';
import 'database_service.dart';
import 'freshrss_service.dart';
import 'offline_cache_service.dart';
import 'notification_service.dart';
import '../notifiers/unread_refresh_notifier.dart';
import '../notifiers/starred_refresh_notifier.dart';
import '../notifiers/last_sync_notifier.dart';
import 'storage_service.dart';

class SyncService {
  final DatabaseService _db = DatabaseService();
  final FreshRSSService _api = FreshRSSService();
  final OfflineCacheService _offlineCacheService = OfflineCacheService();
  final StorageService _storage = StorageService();
  int _articleFetchLimit = 200;
  int _maxArticleAgeDays = 30;

  void setUserConfig(UserConfig config) {
    _api.setConfig(config);
    _articleFetchLimit = config.articleFetchLimit;
    _maxArticleAgeDays = config.maxArticleAgeDays;
  }

  Future<void> syncAll({
    bool fetchFullContent = false,
    bool refreshOfflineCache = true,
  }) async {
    try {
      print('Starting sync...');

      // Sync feeds
      final feeds = await _api.getSubscriptions();
      print('Got ${feeds.length} feeds');
      for (var feed in feeds) {
        await _db.insertFeed(feed);
      }

      // Fetch latest articles from reading list (all articles, up to limit)
      print('Fetching latest articles from reading list (limit: $_articleFetchLimit)...');
      var allArticles = await _api.getStreamContents(
        streamId: 'user/-/state/com.google/reading-list',
        count: _articleFetchLimit,
        excludeRead: false,
      );
      print('Got ${allArticles.length} total articles from reading list');

      if (_maxArticleAgeDays > 0) {
        final cutoff = DateTime.now().subtract(Duration(days: _maxArticleAgeDays));
        final before = allArticles.length;
        allArticles =
            allArticles.where((a) => a.publishedDate.isAfter(cutoff)).toList();
        final dropped = before - allArticles.length;
        if (dropped > 0) {
          print(
            'Filtered out $dropped articles older than $_maxArticleAgeDays days',
          );
        }
      }

      // Filter out articles the user has deleted locally so they don't come back.
      final deletedIds = (await _storage.getDeletedArticleIds()).toSet();
      if (deletedIds.isNotEmpty) {
        allArticles =
            allArticles.where((a) => !deletedIds.contains(a.id)).toList();
        print('Filtered out ${deletedIds.length} deleted articles from sync');
      }

      if (allArticles.isNotEmpty) {
        print('Inserting ${allArticles.length} articles into database...');
        await _db.insertArticles(allArticles);
        print('Articles inserted successfully');

        // Verify insertion
        final count = await _db.getUnreadCount();
        print('Total unread articles in database: $count');
      } else {
        print('No articles to insert');
      }

      // Sync unread status
      await syncUnreadStatus();

      // Sync starred status
      await syncStarredStatus();

      // Refresh offline cache (unread) and cleanup expired caches when requested
      if (refreshOfflineCache) {
        await _offlineCacheService.refreshAndCleanup();
      }

      // Persist last sync and notify listeners so all tabs can refresh
      await _storage.saveLastSyncTimestamp(DateTime.now());
      LastSyncNotifier.instance.ping();
      UnreadRefreshNotifier.instance.ping();
      StarredRefreshNotifier.instance.ping();

      print('Sync completed');
    } catch (e) {
      print('Sync error: $e');
      rethrow;
    }
  }

  Future<void> syncFeedArticles(String feedId, {bool fetchFullContent = false}) async {
    try {
      print('Syncing articles for feed: $feedId');
      // Feed ID from FreshRSS already includes "feed/" prefix, so don't add it again
      final streamId = feedId.startsWith('feed/') ? feedId : 'feed/$feedId';
      final articles = await _api.getStreamContents(
        streamId: streamId,
        count: 100,
        excludeRead: false,
      );
      print('Got ${articles.length} articles for feed $feedId');

      if (articles.isNotEmpty) {
        await _db.insertArticles(articles);

        // Update feed's last article date
        final feed = await _db.getFeed(feedId);
        if (feed != null) {
          final latestArticle = articles.first;
          await _db.updateFeed(feed.copyWith(
            lastArticleDate: latestArticle.publishedDate,
            lastSyncDate: DateTime.now(),
          ));
        }
      }
    } catch (e) {
      print('Error syncing feed $feedId: $e');
    }
  }

  Future<void> syncUnreadStatus() async {
    try {
      print('Syncing unread status from server...');
      // Get unread article IDs from server
      final serverUnreadIds = await _api.getUnreadArticleIds();
      print('Server has ${serverUnreadIds.length} unread articles');

      if (serverUnreadIds.isEmpty) {
        // If there are truly no unread articles, mark all local as read
        final localIds = await _db.getAllArticleIds();
        if (localIds.isNotEmpty) {
          await _db.markMultipleArticlesAsRead(localIds, true);
        }
        print('Unread status sync completed. Local unread count: 0');
        return;
      }

      final localIds = await _db.getAllArticleIds();
      final localSet = localIds.toSet();
      final unreadSet = serverUnreadIds.toSet();

      final idsToMarkUnread = localSet.where(unreadSet.contains).toList();
      final idsToMarkRead = localSet.where((id) => !unreadSet.contains(id)).toList();

      if (idsToMarkRead.isNotEmpty) {
        await _db.markMultipleArticlesAsRead(idsToMarkRead, true);
      }
      if (idsToMarkUnread.isNotEmpty) {
        await _db.markMultipleArticlesAsRead(idsToMarkUnread, false);
      }

      final newUnreadCount = await _db.getUnreadCount();
      print('Unread status sync completed. Local unread count: $newUnreadCount');
    } catch (e) {
      print('Error syncing unread status: $e');
    }
  }

  Future<void> syncStarredStatus() async {
    try {
      // Get starred article IDs from server
      final serverStarredIds = await _api.getStarredArticleIds();

      // Get all articles from local DB
      final localArticles = await _db.getArticles();

      // Create sets for comparison
      final serverStarredSet = serverStarredIds.toSet();
      final localStarredSet = localArticles
          .where((a) => a.isStarred)
          .map((a) => a.id)
          .toSet();

      // Find articles that need to be unstarred locally
      final toUnstar = localStarredSet.difference(serverStarredSet);
      for (var id in toUnstar) {
        await _db.markArticleAsStarred(id, false);
      }

      // Find articles that need to be starred locally
      final toStar = serverStarredSet.difference(localStarredSet);
      for (var id in toStar) {
        await _db.markArticleAsStarred(id, true);
      }
    } catch (e) {
      // Handle error
    }
  }

  /// Attempts to delete an article locally and from FreshRSS.
  /// Returns true if local deletion succeeds; remote deletion is best-effort.
  Future<bool> deleteArticle(String articleId) async {
    try {
      // Delete locally first
      await _db.deleteArticle(articleId);
      await _storage.addDeletedArticleId(articleId);

      // Best-effort remote delete: FreshRSS doesn't expose a true delete in
      // Reader API, so we try to mark as read & unstar; failures are ignored.
      _api
          .markAsRead([articleId], read: true)
          .catchError((e) => print('Remote delete(mark read) failed: $e'));
      // No-op for star; if it was starred, we unstar to hide it from starred.
      _api
          .markAsStarred([articleId], starred: false)
          .catchError((e) => print('Remote delete(unstar) failed: $e'));

      // Update badge count & notify lists to refresh
      await NotificationService.updateBadgeCount();
      UnreadRefreshNotifier.instance.ping();
      StarredRefreshNotifier.instance.ping();
      return true;
    } catch (e) {
      print('deleteArticle error: $e');
      return false;
    }
  }

  Future<void> markArticleAsRead(String articleId, bool isRead) async {
    try {
      // Update local DB
      await _db.markArticleAsRead(articleId, isRead);

      // Sync to server (non-blocking - don't wait for it)
      _api.markAsRead([articleId], read: isRead).catchError((e) {
        print('Error syncing read status to server: $e');
      });
      
      // Update badge count
      await NotificationService.updateBadgeCount();
      
      // Notify unread screen to refresh immediately
      UnreadRefreshNotifier.instance.ping();
    } catch (e) {
      // Handle error
    }
  }

  Future<void> markArticleAsStarred(String articleId, bool isStarred) async {
    try {
      // Update local DB
      await _db.markArticleAsStarred(articleId, isStarred);

      // Sync to server
      await _api.markAsStarred([articleId], starred: isStarred);
      
      // Update badge count (starring doesn't affect unread, but sync might)
      await NotificationService.updateBadgeCount();
    } catch (e) {
      // Handle error
    }
  }

  Future<void> refreshOfflineContent({bool force = false}) async {
    await _offlineCacheService.refreshAndCleanup(force: force);
  }
}

