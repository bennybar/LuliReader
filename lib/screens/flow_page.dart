import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../database/article_dao.dart';
import '../providers/app_provider.dart';
import '../services/local_rss_service.dart';
import '../services/account_service.dart';
import '../utils/rtl_helper.dart';
import 'article_reader_screen.dart';
import 'settings_screen.dart';
import 'package:swipe_to_action/swipe_to_action.dart';

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
        await ref.read(accountServiceProvider).updateAccount(
              account.copyWith(updateAt: DateTime.now()),
            );
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
      if (_filter == 'unread') {
        setState(() {
          _articles = [];
        });
      } else {
        setState(() {
          _articles = _articles
              .map((a) => ArticleWithFeed(
                    article: a.article.copyWith(isUnread: false),
                    feed: a.feed,
                  ))
              .toList();
        });
      }
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
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark All as Read',
            onPressed: _markAllAsRead,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync All Feeds',
            onPressed: widget.onSync ?? _syncAll,
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
                  child: Column(
                    children: [
                      _buildSyncInfo(),
                      Expanded(
                        child: ListView.builder(
                          key: ValueKey(_refreshKey),
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: _articles.length,
                          itemBuilder: (context, index) {
                            final articleWithFeed = _articles[index];
                            return _buildArticleCard(articleWithFeed);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildArticleCard(ArticleWithFeed articleWithFeed) {
    final article = articleWithFeed.article;
    final feed = articleWithFeed.feed as Feed;
    final contentText =
        '${article.title} ${article.shortDescription} ${article.fullContent ?? ''}';
    final textDirection =
        RtlHelper.getTextDirectionFromContent(contentText, feedRtl: feed.isRtl);
    final isRtl = textDirection == TextDirection.rtl;

    return FutureBuilder(
      future: ref.read(accountServiceProvider).getCurrentAccount(),
      builder: (context, snapshot) {
        final account = snapshot.data;
        final swipeStartAction = account?.swipeStartAction ?? 2;
        final swipeEndAction = account?.swipeEndAction ?? 1;

        return Directionality(
          textDirection: textDirection,
          child: Swipeable(
            key: ValueKey(article.id),
            direction: SwipeDirection.horizontal,
            background: _buildSwipeBackground(
              context,
              textDirection,
              swipeStartAction,
              article,
              isStart: true,
            ),
            secondaryBackground: _buildSwipeBackground(
              context,
              textDirection,
              swipeEndAction,
              article,
              isStart: false,
            ),
            confirmSwipe: (dir) async {
              final action = dir == SwipeDirection.startToEnd ? swipeStartAction : swipeEndAction;
              if (action == 0) return false;
              return await _handleSwipeAction(action, article, fromSwipe: true);
            },
            onSwipe: (_) {},
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) => ArticleReaderScreen(article: article),
                        ),
                      )
                      .then((_) => _loadArticles());
                },
                onLongPress: () {
                  _showLongPressMenu(context, article);
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isRtl) ...[
                          _buildArticleImage(article),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment:
                                isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      article.title,
                                      style: TextStyle(
                                        fontWeight:
                                            article.isUnread ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 15,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: isRtl ? TextAlign.right : TextAlign.left,
                                    ),
                                  ),
                                  if (article.isStarred)
                                    Padding(
                                      padding: EdgeInsets.only(
                                          left: isRtl ? 0 : 8, right: isRtl ? 8 : 0),
                                      child: Icon(
                                        Icons.star,
                                        size: 16,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                article.shortDescription,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: 13,
                                      color:
                                          Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: isRtl ? TextAlign.right : TextAlign.left,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      feed.name,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.5),
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
                                    color:
                                        Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      _formatDate(article.date),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontSize: 11,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.5),
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
                        if (isRtl) ...[
                          const SizedBox(width: 12),
                          _buildArticleImage(article),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _handleSwipeAction(int action, Article article, {bool fromSwipe = false}) async {
    // Update UI immediately for instant feedback
    final index = _articles.indexWhere((a) => a.article.id == article.id);
    bool shouldRemove = false;
    if (index != -1) {
      setState(() {
        final currentArticle = _articles[index].article;
        Article updatedArticle;
        switch (action) {
          case 1: // Toggle Read
            updatedArticle = currentArticle.copyWith(isUnread: !currentArticle.isUnread);
            if (!updatedArticle.isUnread && _filter == 'unread') {
              shouldRemove = true;
            }
            break;
          case 2: // Toggle Starred
            updatedArticle = currentArticle.copyWith(isStarred: !currentArticle.isStarred);
            if (!updatedArticle.isStarred && _filter == 'starred') {
              shouldRemove = true;
            }
            break;
          default:
            return;
        }
        if (shouldRemove) {
          _articles.removeAt(index);
        } else {
          _articles[index] = ArticleWithFeed(
            article: updatedArticle,
            feed: _articles[index].feed,
          );
        }
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

    return shouldRemove;
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

  Widget _buildSwipeBackground(
    BuildContext context,
    TextDirection textDirection,
    int action,
    Article article, {
    required bool isStart,
  }) {
    if (action == 0) return const SizedBox.shrink();
    final color = _getActionColor(action);
    final icon = _getActionIcon(action);
    final label = _getActionLabel(action, article);
    return Directionality(
      textDirection: textDirection,
      child: Container(
        alignment: isStart ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: color.withOpacity(0.15),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isStart) ...[
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
            ],
            Icon(icon, color: color),
            if (isStart) ...[
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildArticleImage(Article article) {
    return ClipRRect(
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
    );
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

  void _showLongPressMenu(BuildContext context, Article article) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                _shareArticle(article);
              },
            ),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: const Text('Mark Below as Read'),
              onTap: () {
                Navigator.pop(context);
                _markBelowAsRead(article);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareArticle(Article article) async {
    await Clipboard.setData(ClipboardData(text: article.link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied to clipboard')),
      );
    }
  }

  Future<void> _markBelowAsRead(Article article) async {
    try {
      final articleDao = ref.read(articleDaoProvider);
      final currentIndex = _articles.indexWhere((a) => a.article.id == article.id);
      
      if (currentIndex != -1) {
        // Mark all articles below this one as read
        int markedCount = 0;
        final indicesToRemove = <int>[];
        for (int i = currentIndex + 1; i < _articles.length; i++) {
          if (_articles[i].article.isUnread) {
            await articleDao.markAsRead(_articles[i].article.id);
            markedCount++;
            if (_filter == 'unread') {
              indicesToRemove.add(i);
            }
          }
        }
        
        // Update UI
        setState(() {
          if (_filter == 'unread') {
            for (final idx in indicesToRemove.reversed) {
              _articles.removeAt(idx);
            }
          } else {
            for (int i = currentIndex + 1; i < _articles.length; i++) {
              _articles[i] = ArticleWithFeed(
                article: _articles[i].article.copyWith(isUnread: false),
                feed: _articles[i].feed,
              );
            }
          }
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Marked $markedCount articles as read')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
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

  Widget _buildSyncInfo() {
    return FutureBuilder(
      future: ref.read(accountServiceProvider).getCurrentAccount(),
      builder: (context, snapshot) {
        final account = snapshot.data;
        final lastSync = account?.updateAt;
        if (lastSync == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.history, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Last sync: ${_formatDate(lastSync)}',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


