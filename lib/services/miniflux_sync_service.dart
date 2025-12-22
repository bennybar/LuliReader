import '../database/account_dao.dart';
import '../database/article_dao.dart';
import '../database/feed_dao.dart';
import '../database/group_dao.dart';
import '../models/account.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/group.dart';
import 'miniflux_service.dart';
import 'rss_service.dart';

/// Syncs articles and subscriptions for Miniflux accounts.
class MinifluxSyncService {
  final MinifluxService _api;
  final ArticleDao _articleDao;
  final FeedDao _feedDao;
  final GroupDao _groupDao;
  final AccountDao _accountDao;
  final RssService _rssService;

  MinifluxSyncService(
    this._api,
    this._articleDao,
    this._feedDao,
    this._groupDao,
    this._accountDao,
    this._rssService,
  );

  Future<void> sync(
    int accountId, {
    void Function(String)? onProgress,
    void Function(double)? onProgressPercent,
  }) async {
    onProgress?.call('Loading account...');
    onProgressPercent?.call(0.0);
    final account = await _accountDao.getById(accountId);
    if (account == null || account.type != AccountType.miniflux) {
      throw Exception('Miniflux account not found');
    }

    final base = account.apiEndpoint ?? '';
    if (base.trim().isEmpty) {
      throw Exception('Miniflux endpoint is missing');
    }
    final apiEndpoint = MinifluxService.normalizeApiEndpoint(base);
    onProgress?.call('Authenticating Miniflux...');
    onProgressPercent?.call(0.05);
    var authToken = await _ensureAuthToken(account, apiEndpoint);

    onProgress?.call('Fetching subscriptions...');
    onProgressPercent?.call(0.10);
    Map<String, dynamic> subscriptions;
    try {
      subscriptions = await _api.getSubscriptions(apiEndpoint, authToken);
    } catch (e) {
      // If getSubscriptions fails, try re-authenticating
      print('[MINIFLUX_SYNC] getSubscriptions failed, re-authenticating: $e');
      authToken = await _api.authenticate(
        apiEndpoint,
        account.username ?? '',
        account.password ?? '',
      );
      await _accountDao.update(account.copyWith(authToken: authToken));
      subscriptions = await _api.getSubscriptions(apiEndpoint, authToken);
    }
    
    // Ensure subscriptions is a Map with 'subscriptions' key
    if (subscriptions is! Map<String, dynamic>) {
      throw Exception('Invalid subscriptions response format');
    }
    
    final parsed = await _api.parseSubscriptions(subscriptions, accountId);
    final groups = parsed['groups']!.cast<Group>();
    final feeds = parsed['feeds']!.cast<Feed>();

    onProgress?.call('Updating groups and feeds...');
    onProgressPercent?.call(0.20);
    await _upsertGroups(accountId, groups);
    await _upsertFeeds(accountId, feeds);

    onProgress?.call('Fetching latest articles...');
    onProgressPercent?.call(0.30);
    final articlesResult = await _fetchLatestArticles(
      apiEndpoint,
      authToken,
      accountId,
      account.maxPastDays,
      account,
    );
    final articles = articlesResult['articles'] as List<Article>;
    final timestampMap = articlesResult['timestampMap'] as Map<String, String>;

    final feedMap = <String, Feed>{
      for (final feed in feeds) feed.id: feed,
    };
    // For Miniflux, read status comes from the native API response directly
    // No need to fetch unread IDs separately - the articles already have correct status
    onProgress?.call('Processing articles...');
    onProgressPercent?.call(0.80);
    await _upsertArticles(
      articles, 
      feedMap, 
      account, 
      timestampMap, 
      <String>{}, // Empty set - read status comes from article.isUnread (from native API)
      onProgressPercent: onProgressPercent,
    );

    onProgress?.call('Completing sync...');
    onProgressPercent?.call(0.95);
    await _accountDao.update(
      account.copyWith(
        updateAt: DateTime.now(),
        authToken: authToken,
        apiEndpoint: apiEndpoint,
      ),
    );
    onProgressPercent?.call(1.0);
  }

  Future<String> _ensureAuthToken(Account account, String apiEndpoint) async {
    if (account.authToken != null && account.authToken!.isNotEmpty) {
      return account.authToken!;
    }
    if (account.username == null ||
        account.username!.isEmpty ||
        account.password == null ||
        account.password!.isEmpty) {
      throw Exception('Miniflux credentials are missing');
    }
    final result = await _api.authenticateWithEndpoint(
      apiEndpoint,
      account.username!,
      account.password!,
    );
    final token = result['token']!;
    final correctedEndpoint = result['correctedEndpoint'];
    await _accountDao.update(
      account.copyWith(
        authToken: token,
        apiEndpoint: correctedEndpoint ?? apiEndpoint,
      ),
    );
    return token;
  }

  Future<void> _upsertGroups(int accountId, List<Group> groups) async {
    final existing = await _groupDao.getAll(accountId);
    final incomingIds = groups.map((g) => g.id).toSet();
    for (final group in groups) {
      // Check if group exists globally (not just for this account)
      final existingGroup = await _groupDao.getById(group.id);
      if (existingGroup == null) {
        // Group doesn't exist, insert it
        await _groupDao.insert(group);
      } else if (existingGroup.accountId != accountId) {
        // Group exists but for different account - update it to this account
        await _groupDao.update(group);
      } else if (existingGroup.name != group.name) {
        // Group exists for this account but name changed - update it
        await _groupDao.update(group);
      }
      // If group exists and name is same, no action needed
    }
    for (final g in existing) {
      if (!incomingIds.contains(g.id) && g.id != _groupDao.getDefaultGroupId(accountId)) {
        await _groupDao.delete(g.id);
      }
    }
  }

  Future<void> _upsertFeeds(int accountId, List<Feed> feeds) async {
    final existing = await _feedDao.getAll(accountId);
    final incomingIds = feeds.map((f) => f.id).toSet();
    for (final feed in feeds) {
      // Check if feed exists globally (not just for this account)
      final existingFeed = await _feedDao.getById(feed.id);
      if (existingFeed == null) {
        // Feed doesn't exist, insert it
        await _feedDao.insert(feed);
      } else if (existingFeed.accountId != accountId) {
        // Feed exists but for different account - update it to this account
        await _feedDao.update(feed);
      } else {
        // Feed exists for this account - update if needed
        final current = existing.firstWhere(
          (f) => f.id == feed.id,
          orElse: () => feed,
        );
        if (current.icon?.isNotEmpty == true) {
          await _feedDao.update(
            feed.copyWith(icon: current.icon),
          );
        } else {
          await _feedDao.update(feed);
        }
      }
    }
    for (final feed in existing) {
      if (!incomingIds.contains(feed.id)) {
        await _feedDao.delete(feed.id);
      }
    }
  }

  Future<Map<String, dynamic>> _fetchLatestArticles(
    String apiEndpoint,
    String authToken,
    int accountId,
    int maxPastDays,
    Account account,
  ) async {
    final List<Article> all = [];
    final Map<String, String> timestampMap = {};
    String? continuation;
    int batches = 0;
    final minDate = DateTime.now().subtract(Duration(days: maxPastDays));

    // Miniflux: Get item IDs first, then fetch contents by ID
    // Get all feeds first
    final feeds = await _feedDao.getAll(accountId);
    print('[MINIFLUX_SYNC] Fetching articles from ${feeds.length} feeds...');
    
    // Collect all item IDs from all feeds
    final Map<String, List<String>> feedItemIds = {}; // feedId -> list of item IDs
    
    for (int i = 0; i < feeds.length; i++) {
      final feed = feeds[i];
      print('[MINIFLUX_SYNC] Getting item IDs from feed ${i + 1}/${feeds.length}: ${feed.name} (${feed.id})...');
      
      try {
        String? continuation;
        final feedIds = <String>[];
        int batchCount = 0;
        
        do {
          final idsResult = await _api.getStreamItemIds(
            apiEndpoint,
            authToken,
            streamId: feed.id,
            xt: null, // get all items (read and unread)
            n: 1000,
            continuation: continuation,
          );
          final ids = idsResult['ids'] as Set<String>? ?? {};
          feedIds.addAll(ids);
          continuation = idsResult['continuation'] as String?;
          batchCount++;
          print('[MINIFLUX_SYNC] Feed ${feed.name}: Got ${ids.length} item IDs (total: ${feedIds.length})');
        } while (continuation != null && batchCount < 5);
        
        if (feedIds.isNotEmpty) {
          feedItemIds[feed.id] = feedIds;
          print('[MINIFLUX_SYNC] Feed ${feed.name}: Total ${feedIds.length} item IDs collected');
        }
      } catch (e) {
        print('[MINIFLUX_SYNC] Error getting item IDs from feed ${feed.name}: $e');
      }
    }
    
    print('[MINIFLUX_SYNC] Total feeds with items: ${feedItemIds.length}');
    
    // Miniflux's Google Reader API stream/contents returns empty, so use native REST API
    print('[MINIFLUX_SYNC] Google Reader API returns empty, trying Miniflux native REST API...');
    try {
      final response = await _api.getEntriesViaNativeApi(
        apiEndpoint,
        account.username ?? '',
        account.password ?? '',
        accountId,
        maxPastDays,
      );
      final parsed = _api.parseArticlesWithMetadata(response, accountId);
      final articles = parsed['articles'] as List<Article>;
      final timestamps = parsed['timestampMap'] as Map<String, String>;
      timestampMap.addAll(timestamps);
      final filtered = articles.where((a) => !a.date.isBefore(minDate)).toList();
      all.addAll(filtered);
      print('[MINIFLUX_SYNC] Native API: Got ${filtered.length} articles');
    } catch (e) {
      print('[MINIFLUX_SYNC] Error fetching via native API: $e');
      // Fallback: Try fetching by item IDs (even though it usually returns empty)
      final allItemIds = <String>[];
      for (final ids in feedItemIds.values) {
        allItemIds.addAll(ids);
      }
      
      if (allItemIds.isNotEmpty) {
        print('[MINIFLUX_SYNC] Fallback: Trying to fetch ${allItemIds.length} items by ID...');
        const batchSize = 20;
        for (int i = 0; i < allItemIds.length; i += batchSize) {
          final batch = allItemIds.skip(i).take(batchSize).toList();
          try {
            final response = await _api.getStreamContents(
              apiEndpoint,
              authToken,
              itemIds: batch,
            );
            final items = response['items'] as List<dynamic>?;
            if (items != null && items.isNotEmpty) {
              final parsed = _api.parseArticlesWithMetadata(response, accountId);
              final articles = parsed['articles'] as List<Article>;
              final timestamps = parsed['timestampMap'] as Map<String, String>;
              timestampMap.addAll(timestamps);
              final filtered = articles.where((a) => !a.date.isBefore(minDate)).toList();
              all.addAll(filtered);
            }
          } catch (_) {
            // Ignore errors in fallback
          }
        }
      }
    }

    print('[MINIFLUX_SYNC] Total articles fetched: ${all.length}');
    return {'articles': all, 'timestampMap': timestampMap};
  }

  Future<Set<String>> _fetchUnreadTimestampIds(
    String apiEndpoint,
    String authToken,
    int maxPastDays,
  ) async {
    final unreadIds = <String>{};
    String? continuation;
    int batches = 0;

    do {
      final result = await _api.getStreamItemIds(
        apiEndpoint,
        authToken,
        streamId: 'user/-/state/com.google/reading-list',
        xt: 'user/-/state/com.google/read', // exclude read items, so we get only unread
        n: 1000,
        continuation: continuation,
      );
      
      final ids = result['ids'] as Set<String>;
      unreadIds.addAll(ids);
      
      continuation = result['continuation'] as String?;
      batches++;
    } while (continuation != null && batches < 4);

    return unreadIds;
  }


  Future<void> _upsertArticles(
    List<Article> articles,
    Map<String, Feed> feedMap,
    Account account,
    Map<String, String> timestampMap,
    Set<String> unreadTimestampIds, {
    void Function(double)? onProgressPercent,
  }) async {
    final totalArticles = articles.length;
    final newArticles = <Article>[];
    int processedCount = 0;
    for (final article in articles) {
      if (!feedMap.containsKey(article.feedId)) {
        continue;
      }
      final normalizedId = _normalizeItemId(article.id);
      
      // Check for duplicate by title + feedId first (not by URL)
      final existingByTitle = await _articleDao.getByTitleAndFeedId(
        article.title,
        article.feedId,
        article.accountId,
      );
      
      // For Miniflux: read status comes directly from the article (parsed from native API)
      // The article.isUnread is already set correctly from the server response
      final isUnreadFromServer = article.isUnread;
      final isStarredFromServer = article.isStarred;

      if (existingByTitle == null) {
        // Also check by ID as fallback
        final existingById = await _articleDao.getById(article.id);
        if (existingById == null) {
          // Check if article was previously read and deleted (in read_history)
          // If found, skip insertion to prevent deleted articles from returning
          final wasPreviouslyRead = await _articleDao.isInReadHistory(article);
          if (wasPreviouslyRead) {
            // Skip article that was previously read (and likely deleted)
            continue;
          }
          
          final toInsert = article.copyWith(
            id: normalizedId,
            isUnread: isUnreadFromServer, // Use server's read status (from native API)
            isStarred: isStarredFromServer, // Use server's starred status
          );
          await _articleDao.insert(toInsert);
          newArticles.add(toInsert);
        } else {
          // For existing articles, update metadata but preserve read status if user explicitly set it
          // Only update read status if it differs from server AND user hasn't explicitly changed it
          // For Miniflux, always sync read status from server to keep in sync
          final updated = existingById.copyWith(
            id: normalizedId,
            title: article.title,
            rawDescription: article.rawDescription,
            shortDescription: article.shortDescription,
            link: article.link,
            isUnread: isUnreadFromServer, // Sync read status from server
            isStarred: isStarredFromServer, // Sync starred status from server
            date: article.date,
            feedId: article.feedId,
          );
          await _articleDao.update(updated);
        }
      } else {
        // Article with same title + feed already exists, skip to avoid duplicates
        // Optionally update read status if needed
        if (existingByTitle.isUnread != isUnreadFromServer || existingByTitle.isStarred != isStarredFromServer) {
          final updated = existingByTitle.copyWith(
            isUnread: isUnreadFromServer,
            isStarred: isStarredFromServer,
          );
          await _articleDao.update(updated);
        }
      }
      
      processedCount++;
      // Update progress: 80% to 95% for article processing
      if (onProgressPercent != null && totalArticles > 0) {
        final progress = 0.80 + (processedCount / totalArticles) * 0.15;
        onProgressPercent(progress);
      }
    }

    final shouldFetchFull =
        account.isFullContent || newArticles.any((a) => (feedMap[a.feedId]?.isFullContent ?? false));
    if (shouldFetchFull && newArticles.isNotEmpty) {
      for (final article in newArticles) {
        try {
          final content = await _rssService.parseFullContent(article.link, article.title);
          if (content != null) {
            await _articleDao.update(article.copyWith(fullContent: content));
            // Prefetch images for caching
            RssService.prefetchImages(content);
          }
        } catch (_) {}
      }
    }
  }

  /// Normalize Miniflux item IDs to the short form used by unread/read streams.
  String _normalizeItemId(String id) {
    // For Miniflux articles, preserve the miniflux_ prefix
    if (id.startsWith('miniflux_')) {
      return id;
    }
    // For Google Reader API format, extract the item ID
    final idx = id.lastIndexOf('item/');
    if (idx != -1) {
      return id.substring(idx + 5);
    }
    return id;
  }
}

