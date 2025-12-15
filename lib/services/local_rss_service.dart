import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/account.dart';
import '../database/article_dao.dart';
import '../database/feed_dao.dart';
import '../database/group_dao.dart';
import '../database/account_dao.dart';
import 'rss_helper.dart';
import 'rss_service.dart';

class LocalRssService {
  final ArticleDao _articleDao;
  final FeedDao _feedDao;
  final GroupDao _groupDao;
  final AccountDao _accountDao;
  final RssHelper _rssHelper;
  final RssService _rssService;
  final http.Client _httpClient;

  LocalRssService(
    this._articleDao,
    this._feedDao,
    this._groupDao,
    this._accountDao,
    this._rssHelper,
    this._rssService,
    this._httpClient,
  );

  /// Sync all feeds for an account
  Future<void> sync(int accountId, {String? feedId, String? groupId}) async {
    final account = await _accountDao.getById(accountId);
    if (account == null || account.type != AccountType.local) {
      throw Exception('Invalid account');
    }
    
    // Store account-level full content setting for use in sync
    final accountFullContent = account.isFullContent;

    final preDate = DateTime.now();
    final List<Feed> feedsToSync;

    if (feedId != null) {
      final feed = await _feedDao.getById(feedId);
      feedsToSync = feed != null ? [feed] : [];
    } else if (groupId != null) {
      feedsToSync = await _feedDao.getByGroupId(accountId, groupId);
    } else {
      feedsToSync = await _feedDao.getAll(accountId);
    }

    if (feedsToSync.isEmpty) {
      return; // No feeds to sync
    }

    // Sync feeds with limited concurrency
    final futures = <Future>[];
    int activeCount = 0;
    const maxConcurrent = 8;

    for (final feed in feedsToSync) {
      // Wait if we have too many active syncs
      while (activeCount >= maxConcurrent) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      activeCount++;
      futures.add(_syncFeed(feed, accountId, preDate, accountFullContent).then((_) {
        activeCount--;
      }).catchError((e) {
        activeCount--;
        print('Error syncing feed ${feed.name}: $e');
      }));
    }

    // Wait for all syncs to complete
    await Future.wait(futures, eagerError: false);

    // Update account sync time
    await _accountDao.update(account.copyWith(updateAt: preDate));
  }

  Future<void> _syncFeed(Feed feed, int accountId, DateTime preDate, bool accountFullContent) async {
    try {
      // Get archived articles to skip
      final archivedArticles = await _feedDao.getArchivedArticles(feed.id);
      final archivedLinks = archivedArticles.map((a) => a.link).toSet();

      // Fetch articles from RSS
      final articles = await _rssHelper.queryRssXml(feed, accountId, null, preDate);
      
      if (articles.isEmpty) {
        print('No articles found for feed: ${feed.name}');
        return;
      }
      
      // Filter out archived articles
      final newArticles = articles.where((a) => !archivedLinks.contains(a.link)).toList();

      // Insert new articles
      final insertedArticles = await _articleDao.insertListIfNotExist(
        articles: newArticles,
        feed: feed,
      );

      // If account or feed has isFullContent enabled, download full content in background
      // Feed-level setting overrides account-level setting
      final shouldParseFullContent = feed.isFullContent || accountFullContent;
      if (shouldParseFullContent) {
        // Download full content asynchronously (don't wait)
        Future.microtask(() async {
          // First, download for new articles
          if (insertedArticles.isNotEmpty) {
            for (final article in insertedArticles) {
              try {
                await downloadFullContent(article);
              } catch (e) {
                print('Error downloading full content for article ${article.id}: $e');
                // Continue with other articles even if one fails
              }
            }
          }

          // Also check for existing articles without full content (limit to avoid too many downloads)
          try {
            final existingArticles = await _articleDao.getByFeedId(feed.id, limit: 50);
            final articlesNeedingContent = existingArticles.where((a) => 
              a.fullContent == null || a.fullContent!.isEmpty
            ).take(10).toList(); // Limit to 10 per sync to avoid overwhelming

            for (final article in articlesNeedingContent) {
              try {
                await downloadFullContent(article);
                // Small delay to avoid rate limiting
                await Future.delayed(const Duration(milliseconds: 500));
              } catch (e) {
                print('Error downloading full content for existing article ${article.id}: $e');
                // Continue with other articles even if one fails
              }
            }
          } catch (e) {
            print('Error checking for articles needing full content: $e');
          }
        });
      }

      // Update feed icon if needed
      if (feed.icon == null || feed.icon!.isEmpty) {
        try {
          final iconLink = await _rssHelper.queryRssIconLink(feed.url);
          if (iconLink != null && iconLink.isNotEmpty) {
            await _feedDao.update(feed.copyWith(icon: iconLink));
          }
        } catch (e) {
          // Icon fetch is optional, don't fail the sync
          print('Error fetching icon for ${feed.name}: $e');
        }
      }

      // TODO: Send notifications for new articles if enabled
      // if (feed.isNotification && inserted.isNotEmpty) {
      //   _notificationHelper.notify(feed, inserted);
      // }
    } catch (e) {
      print('Error syncing feed ${feed.name}: $e');
      // Don't rethrow - continue with other feeds
    }
  }

  /// Download full content for an article
  Future<String?> downloadFullContent(Article article) async {
    try {
      final content = await _rssService.parseFullContent(article.link, article.title);
      if (content != null) {
        // Update article with full content
        await _articleDao.update(article.copyWith(fullContent: content));
        return content;
      }
    } catch (e) {
      print('Error downloading full content: $e');
    }
    return null;
  }
}

