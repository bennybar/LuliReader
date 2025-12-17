import '../database/account_dao.dart';
import '../database/article_dao.dart';
import '../database/feed_dao.dart';
import '../database/group_dao.dart';
import '../models/account.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/group.dart';
import 'freshrss_service.dart';
import 'rss_service.dart';

/// Syncs articles and subscriptions for FreshRSS accounts.
class FreshRssSyncService {
  final FreshRssService _api;
  final ArticleDao _articleDao;
  final FeedDao _feedDao;
  final GroupDao _groupDao;
  final AccountDao _accountDao;
  final RssService _rssService;

  FreshRssSyncService(
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
  }) async {
    onProgress?.call('Loading account...');
    final account = await _accountDao.getById(accountId);
    if (account == null || account.type != AccountType.freshrss) {
      throw Exception('FreshRSS account not found');
    }

    final base = account.apiEndpoint ?? '';
    if (base.trim().isEmpty) {
      throw Exception('FreshRSS endpoint is missing');
    }
    final apiEndpoint = FreshRssService.normalizeApiEndpoint(base);
    onProgress?.call('Authenticating FreshRSS...');
    var authToken = await _ensureAuthToken(account, apiEndpoint);

    onProgress?.call('Fetching subscriptions...');
    Map<String, dynamic> subscriptions;
    try {
      subscriptions = await _api.getSubscriptions(apiEndpoint, authToken);
    } catch (_) {
      authToken = await _api.authenticate(
        apiEndpoint,
        account.username ?? '',
        account.password ?? '',
      );
      await _accountDao.update(account.copyWith(authToken: authToken));
      subscriptions = await _api.getSubscriptions(apiEndpoint, authToken);
    }
    final parsed = await _api.parseSubscriptions(subscriptions, accountId);
    final groups = parsed['groups']!.cast<Group>();
    final feeds = parsed['feeds']!.cast<Feed>();

    await _upsertGroups(accountId, groups);
    await _upsertFeeds(accountId, feeds);

    onProgress?.call('Fetching latest articles...');
    final articlesResult = await _fetchLatestArticles(
      apiEndpoint,
      authToken,
      accountId,
      account.maxPastDays,
    );
    final articles = articlesResult['articles'] as List<Article>;
    final timestampMap = articlesResult['timestampMap'] as Map<String, String>;

    onProgress?.call('Fetching unread item IDs from server...');
    // Get unread item IDs from server using items/ids endpoint
    final unreadTimestampIds = await _fetchUnreadTimestampIds(
      apiEndpoint,
      authToken,
      account.maxPastDays,
    );

    final feedMap = <String, Feed>{
      for (final feed in feeds) feed.id: feed,
    };
    // Use unread IDs from server to determine read status
    await _upsertArticles(articles, feedMap, account, timestampMap, unreadTimestampIds);

    await _accountDao.update(
      account.copyWith(
        updateAt: DateTime.now(),
        authToken: authToken,
        apiEndpoint: apiEndpoint,
      ),
    );
  }

  Future<String> _ensureAuthToken(Account account, String apiEndpoint) async {
    if (account.authToken != null && account.authToken!.isNotEmpty) {
      return account.authToken!;
    }
    if (account.username == null ||
        account.username!.isEmpty ||
        account.password == null ||
        account.password!.isEmpty) {
      throw Exception('FreshRSS credentials are missing');
    }
    final token = await _api.authenticate(
      apiEndpoint,
      account.username!,
      account.password!,
    );
    await _accountDao.update(
      account.copyWith(
        authToken: token,
        apiEndpoint: apiEndpoint,
      ),
    );
    return token;
  }

  Future<void> _upsertGroups(int accountId, List<Group> groups) async {
    final existing = await _groupDao.getAll(accountId);
    final incomingIds = groups.map((g) => g.id).toSet();
    for (final group in groups) {
      final current = existing.firstWhere(
        (g) => g.id == group.id,
        orElse: () => Group(id: '', name: '', accountId: accountId),
      );
      if (current.id.isEmpty) {
        await _groupDao.insert(group);
      } else if (current.name != group.name) {
        await _groupDao.update(group);
      }
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
      final current = existing.firstWhere(
        (f) => f.id == feed.id,
        orElse: () => Feed(
          id: '',
          name: '',
          url: '',
          groupId: '',
          accountId: accountId,
        ),
      );
      if (current.id.isEmpty) {
        await _feedDao.insert(feed);
      } else {
        await _feedDao.update(
          feed.copyWith(
            icon: current.icon?.isNotEmpty == true ? current.icon : feed.icon,
          ),
        );
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
  ) async {
    final List<Article> all = [];
    final Map<String, String> timestampMap = {};
    String? continuation;
    int batches = 0;
    final minDate = DateTime.now().subtract(Duration(days: maxPastDays));

    do {
      final response = await _api.getStreamContents(
        apiEndpoint,
        authToken,
        streamId: 'user/-/state/com.google/reading-list',
        n: 200,
        continuation: continuation,
        xt: null, // fetch all items (both read and unread) to get their categories
      );
      final parsed = _api.parseArticlesWithMetadata(response, accountId);
      final articles = parsed['articles'] as List<Article>;
      final timestamps = parsed['timestampMap'] as Map<String, String>;
      timestampMap.addAll(timestamps);
      final filtered = articles.where((a) => !a.date.isBefore(minDate)).toList();
      all.addAll(filtered);
      continuation = response['continuation'] as String?;
      batches++;
    } while (continuation != null && batches < 4); // cap to avoid huge syncs

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
    Set<String> unreadTimestampIds,
  ) async {
    final newArticles = <Article>[];
    for (final article in articles) {
      if (!feedMap.containsKey(article.feedId)) {
        continue;
      }
      final normalizedId = _normalizeItemId(article.id);
      final existing = await _articleDao.getById(article.id);
      
      // Determine read status from server's unread IDs list
      // Match article by timestampUsec to see if it's in the unread set
      final timestampUsec = timestampMap[article.id];
      final isUnreadFromServer = timestampUsec != null && unreadTimestampIds.contains(timestampUsec);
      
      // Use starred status from categories (already parsed in parseArticles)
      final isStarredFromServer = article.isStarred;

      if (existing == null) {
        final toInsert = article.copyWith(
          id: normalizedId,
          isUnread: isUnreadFromServer, // Use server's unread IDs list
          isStarred: isStarredFromServer, // Use server's categories
        );
        await _articleDao.insert(toInsert);
        newArticles.add(toInsert);
      } else {
        // For existing articles, update with server state
        final updated = existing.copyWith(
          id: normalizedId,
          title: article.title,
          rawDescription: article.rawDescription,
          shortDescription: article.shortDescription,
          link: article.link,
          isUnread: isUnreadFromServer, // Use server's unread IDs list
          isStarred: isStarredFromServer, // Use server's categories
          date: article.date,
          feedId: article.feedId,
        );
        await _articleDao.update(updated);
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
          }
        } catch (_) {}
      }
    }
  }

  /// Normalize FreshRSS item IDs to the short form used by unread/read streams.
  String _normalizeItemId(String id) {
    final idx = id.lastIndexOf('item/');
    if (idx != -1) {
      return id.substring(idx + 5);
    }
    return id;
  }
}

