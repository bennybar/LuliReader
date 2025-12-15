import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../database/article_dao.dart';
import '../providers/app_provider.dart';
import '../services/local_rss_service.dart';
import '../services/account_service.dart';
import '../utils/rtl_helper.dart';
import 'article_reader_screen.dart';

class FlowPage extends ConsumerStatefulWidget {
  final VoidCallback? onSync;
  
  const FlowPage({super.key, this.onSync});

  @override
  ConsumerState<FlowPage> createState() => FlowPageState();
}

class FlowPageState extends ConsumerState<FlowPage> {
  List<ArticleWithFeed> _articles = [];
  bool _isLoading = true;
  String _filter = 'all'; // all, unread, starred
  int _refreshKey = 0;

  void refresh() {
    setState(() {
      _refreshKey++;
    });
    _loadArticles();
  }

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  Future<void> _loadArticles() async {
    setState(() => _isLoading = true);
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account == null) {
        setState(() => _isLoading = false);
        return;
      }

      final articleDao = ref.read(articleDaoProvider);
      final feedDao = ref.read(feedDaoProvider);

      List<Article> articles;
      if (_filter == 'unread') {
        articles = await articleDao.getUnread(account.id!, limit: 500);
      } else if (_filter == 'starred') {
        articles = await articleDao.getStarred(account.id!, limit: 500);
      } else {
        // Get all articles from all feeds (optimized query)
        articles = await articleDao.getAllArticles(account.id!, limit: 500);
      }

      // Get feeds for each article
      final articlesWithFeed = <ArticleWithFeed>[];
      for (final article in articles) {
        final feed = await feedDao.getById(article.feedId);
        if (feed != null) {
          articlesWithFeed.add(ArticleWithFeed(
            article: article,
            feed: feed as dynamic,
          ));
        }
      }

      setState(() {
        _articles = articlesWithFeed;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading articles: $e')),
        );
      }
    }
  }

  Future<void> _syncAll() async {
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account != null) {
        final rssService = ref.read(localRssServiceProvider);
        await rssService.sync(account.id!);
        _loadArticles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sync completed')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error syncing: $e')),
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final articleDao = ref.read(articleDaoProvider);
      for (final articleWithFeed in _articles) {
        if (articleWithFeed.article.isUnread) {
          await articleDao.markAsRead(articleWithFeed.article.id);
        }
      }
      _loadArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All articles marked as read')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // Filter icons in app bar
            IconButton(
              icon: Icon(
                _filter == 'all' ? Icons.article : Icons.article_outlined,
                color: _filter == 'all' 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).colorScheme.onSurface,
              ),
              tooltip: 'All',
              onPressed: () {
                setState(() {
                  _filter = 'all';
                  _refreshKey++;
                });
                _loadArticles();
              },
            ),
            IconButton(
              icon: Icon(
                _filter == 'unread' ? Icons.visibility : Icons.visibility_outlined,
                color: _filter == 'unread' 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).colorScheme.onSurface,
              ),
              tooltip: 'Unread',
              onPressed: () {
                setState(() {
                  _filter = 'unread';
                  _refreshKey++;
                });
                _loadArticles();
              },
            ),
            IconButton(
              icon: Icon(
                _filter == 'starred' ? Icons.star : Icons.star_outline,
                color: _filter == 'starred' 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).colorScheme.onSurface,
              ),
              tooltip: 'Starred',
              onPressed: () {
                setState(() {
                  _filter = 'starred';
                  _refreshKey++;
                });
                _loadArticles();
              },
            ),
            const SizedBox(width: 8),
            const Text('Articles'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync All Feeds',
            onPressed: widget.onSync ?? _syncAll,
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'mark_all_read',
                child: Row(
                  children: [
                    Icon(Icons.done_all, size: 20),
                    SizedBox(width: 8),
                    Text('Mark All as Read'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'mark_all_read') {
                _markAllAsRead();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _articles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.article,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No articles',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sync feeds to load articles',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadArticles,
                  child: ListView.builder(
                    key: ValueKey(_refreshKey),
                    itemCount: _articles.length,
                    itemBuilder: (context, index) {
                      final articleWithFeed = _articles[index];
                      return _buildArticleCard(articleWithFeed);
                    },
                  ),
                ),
    );
  }

  Widget _buildArticleCard(ArticleWithFeed articleWithFeed) {
    final article = articleWithFeed.article;
    final feed = articleWithFeed.feed as Feed;
    final locale = Localizations.localeOf(context);
    final textDirection = RtlHelper.getTextDirection(locale, feedRtl: feed.isRtl);
    final isRtl = textDirection == TextDirection.rtl;

    return FutureBuilder(
      future: ref.read(accountServiceProvider).getCurrentAccount(),
      builder: (context, snapshot) {
        final account = snapshot.data;
        final swipeStartAction = account?.swipeStartAction ?? 2;
        final swipeEndAction = account?.swipeEndAction ?? 1;

        return Slidable(
          key: ValueKey(article.id),
          startActionPane: _buildStartActionPane(swipeStartAction, article, isRtl),
          endActionPane: _buildEndActionPane(swipeEndAction, article, isRtl),
          child: Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArticleReaderScreen(article: article),
            ),
          ).then((_) => _loadArticles());
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              textDirection: textDirection,
              children: [
                // Article image - position based on RTL
                if (!isRtl) ...[
                  // LTR: image on left
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: article.img != null && article.img!.isNotEmpty
                        ? Image.network(
                            article.img!,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            alignment: Alignment.topLeft,
                            errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: 100,
                                height: 100,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            },
                          )
                        : _buildPlaceholderImage(),
                  ),
                  const SizedBox(width: 12),
                ],
                // Article content
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      // Title with star
                      Row(
                        textDirection: textDirection,
                        children: [
                          Expanded(
                            child: Text(
                              article.title,
                              style: TextStyle(
                                fontWeight: article.isUnread ? FontWeight.bold : FontWeight.normal,
                                fontSize: 15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: isRtl ? TextAlign.right : TextAlign.left,
                            ),
                          ),
                          if (article.isStarred)
                            Padding(
                              padding: EdgeInsets.only(left: isRtl ? 0 : 8, right: isRtl ? 8 : 0),
                              child: Icon(
                                Icons.star,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Description
                      Text(
                        article.shortDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: isRtl ? TextAlign.right : TextAlign.left,
                      ),
                      const SizedBox(height: 8),
                      // Feed name and time at bottom
                      Row(
                        textDirection: textDirection,
                        children: [
                          Expanded(
                            child: Text(
                              feed.name,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    fontSize: 11,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.access_time,
                            size: 11,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _formatDate(article.date),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                  ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Article image - position based on RTL
                if (isRtl) ...[
                  // RTL: image on right
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: article.img != null && article.img!.isNotEmpty
                        ? Image.network(
                            article.img!,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            alignment: Alignment.topLeft,
                            errorBuilder: (context, error, stackTrace) => _buildPlaceholderImage(),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: 100,
                                height: 100,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            },
                          )
                        : _buildPlaceholderImage(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
      },
    );
  }

  ActionPane? _buildStartActionPane(int action, Article article, bool isRtl) {
    if (action == 0) return null; // None

    return ActionPane(
      motion: const DrawerMotion(),
      extentRatio: 0.25,
      children: [
        SlidableAction(
          onPressed: (_) => _handleSwipeAction(action, article),
          backgroundColor: _getActionColor(action),
          foregroundColor: Colors.white,
          icon: _getActionIcon(action),
          label: _getActionLabel(action, article),
          autoClose: true,
        ),
      ],
    );
  }

  ActionPane? _buildEndActionPane(int action, Article article, bool isRtl) {
    if (action == 0) return null; // None

    return ActionPane(
      motion: const DrawerMotion(),
      extentRatio: 0.25,
      children: [
        SlidableAction(
          onPressed: (_) => _handleSwipeAction(action, article),
          backgroundColor: _getActionColor(action),
          foregroundColor: Colors.white,
          icon: _getActionIcon(action),
          label: _getActionLabel(action, article),
          autoClose: true,
        ),
      ],
    );
  }

  Future<void> _handleSwipeAction(int action, Article article) async {
    // Update UI immediately for instant feedback
    final index = _articles.indexWhere((a) => a.article.id == article.id);
    if (index != -1) {
      setState(() {
        final currentArticle = _articles[index].article;
        Article updatedArticle;
        switch (action) {
          case 1: // Toggle Read
            updatedArticle = currentArticle.copyWith(isUnread: !currentArticle.isUnread);
            break;
          case 2: // Toggle Starred
            updatedArticle = currentArticle.copyWith(isStarred: !currentArticle.isStarred);
            break;
          default:
            return;
        }
        _articles[index] = ArticleWithFeed(
          article: updatedArticle,
          feed: _articles[index].feed,
        );
      });
    }

    // Update database in background
    Future.microtask(() async {
      try {
        final articleDao = ref.read(articleDaoProvider);
        switch (action) {
          case 1: // Toggle Read
            if (article.isUnread) {
              await articleDao.markAsRead(article.id);
            } else {
              await articleDao.markAsUnread(article.id);
            }
            break;
          case 2: // Toggle Starred
            await articleDao.toggleStarred(article.id);
            break;
        }
      } catch (e) {
        // If database update fails, reload from database
        if (mounted && index != -1) {
          final articleDao = ref.read(articleDaoProvider);
          final updatedArticle = await articleDao.getById(article.id);
          if (updatedArticle != null) {
            setState(() {
              _articles[index] = ArticleWithFeed(
                article: updatedArticle,
                feed: _articles[index].feed,
              );
            });
          }
        }
      }
    });
  }

  Color _getActionColor(int action) {
    switch (action) {
      case 1: // Toggle Read
        return Colors.blue;
      case 2: // Toggle Starred
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getActionIcon(int action) {
    switch (action) {
      case 1: // Toggle Read
        return Icons.visibility;
      case 2: // Toggle Starred
        return Icons.star;
      default:
        return Icons.help;
    }
  }

  String _getActionLabel(int action, Article article) {
    switch (action) {
      case 1: // Toggle Read
        return article.isUnread ? 'Read' : 'Unread';
      case 2: // Toggle Starred
        return article.isStarred ? 'Unstar' : 'Star';
      default:
        return '';
    }
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.article,
        size: 40,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

