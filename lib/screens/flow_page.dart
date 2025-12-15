import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../database/article_dao.dart';
import '../providers/app_provider.dart';
import '../services/local_rss_service.dart';
import '../services/account_service.dart';
import '../utils/rtl_helper.dart';
import 'article_reader_screen.dart';
import 'settings_screen.dart';

// Custom Slidable widget that auto-triggers on full swipe
class _SlidableWithAutoTrigger extends StatefulWidget {
  final Article article;
  final int swipeStartAction;
  final int swipeEndAction;
  final bool isRtl;
  final Function(int, Article) onSwipeAction;
  final Function(int, Article) onDismissibleAction;
  final ActionPane? Function(int, Article, bool) buildStartActionPane;
  final ActionPane? Function(int, Article, bool) buildEndActionPane;
  final Widget Function() buildCard;

  const _SlidableWithAutoTrigger({
    super.key,
    required this.article,
    required this.swipeStartAction,
    required this.swipeEndAction,
    required this.isRtl,
    required this.onSwipeAction,
    required this.onDismissibleAction,
    required this.buildStartActionPane,
    required this.buildEndActionPane,
    required this.buildCard,
  });

  @override
  State<_SlidableWithAutoTrigger> createState() => _SlidableWithAutoTriggerState();
}

class _SlidableWithAutoTriggerState extends State<_SlidableWithAutoTrigger> {
  @override
  Widget build(BuildContext context) {
    return Slidable(
      key: widget.key,
      startActionPane: widget.buildStartActionPane(
        widget.swipeStartAction,
        widget.article,
        widget.isRtl,
      ),
      endActionPane: widget.buildEndActionPane(
        widget.swipeEndAction,
        widget.article,
        widget.isRtl,
      ),
      closeOnScroll: true,
      child: widget.buildCard(),
    );
  }
}


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
    _loadLastFilter();
  }

  Future<void> _loadLastFilter() async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account != null && account.lastFlowFilter.isNotEmpty) {
      setState(() {
        _filter = account.lastFlowFilter;
      });
    }
    _loadArticles();
  }

  Future<void> _loadArticles() async {
    print('[FLOW_PAGE] _loadArticles() called, filter: $_filter');
    setState(() => _isLoading = true);
    try {
      print('[FLOW_PAGE] Getting current account...');
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account == null) {
        print('[FLOW_PAGE] ERROR: No account found!');
        setState(() => _isLoading = false);
        return;
      }
      print('[FLOW_PAGE] Account found: id=${account.id}, name=${account.name}');

      final articleDao = ref.read(articleDaoProvider);
      final feedDao = ref.read(feedDaoProvider);

      List<Article> articles;
      print('[FLOW_PAGE] Loading articles with filter: $_filter');
      if (_filter == 'unread') {
        print('[FLOW_PAGE] Calling getUnread(accountId=${account.id})');
        articles = await articleDao.getUnread(account.id!, limit: 500);
        print('[FLOW_PAGE] getUnread returned ${articles.length} articles');
      } else if (_filter == 'starred') {
        print('[FLOW_PAGE] Calling getStarred(accountId=${account.id})');
        articles = await articleDao.getStarred(account.id!, limit: 500);
        print('[FLOW_PAGE] getStarred returned ${articles.length} articles');
      } else {
        print('[FLOW_PAGE] Calling getAllArticles(accountId=${account.id})');
        articles = await articleDao.getAllArticles(account.id!, limit: 500);
        print('[FLOW_PAGE] getAllArticles returned ${articles.length} articles');
      }

      if (articles.isEmpty) {
        print('[FLOW_PAGE] WARNING: No articles returned from database query!');
        print('[FLOW_PAGE] Filter: $_filter, Account ID: ${account.id}');
      } else {
        print('[FLOW_PAGE] Processing ${articles.length} articles...');
        // Log first few article IDs for debugging
        for (int i = 0; i < articles.length && i < 3; i++) {
          print('[FLOW_PAGE] Article[$i]: id=${articles[i].id}, title=${articles[i].title.substring(0, articles[i].title.length > 30 ? 30 : articles[i].title.length)}, feedId=${articles[i].feedId}');
        }
      }

      // Get feeds for each article
      print('[FLOW_PAGE] Loading feeds for articles...');
      final articlesWithFeed = <ArticleWithFeed>[];
      int feedNotFoundCount = 0;
      for (final article in articles) {
        final feed = await feedDao.getById(article.feedId);
        if (feed != null) {
          articlesWithFeed.add(ArticleWithFeed(
            article: article,
            feed: feed as dynamic,
          ));
        } else {
          feedNotFoundCount++;
          print('[FLOW_PAGE] WARNING: Feed not found for article ${article.id}, feedId=${article.feedId}');
        }
      }

      if (feedNotFoundCount > 0) {
        print('[FLOW_PAGE] WARNING: $feedNotFoundCount articles had missing feeds!');
      }

      print('[FLOW_PAGE] Final article count: ${articlesWithFeed.length} (from ${articles.length} articles)');
      setState(() {
        _articles = articlesWithFeed;
        _isLoading = false;
      });
      print('[FLOW_PAGE] State updated, _articles.length = ${_articles.length}');
    } catch (e, stackTrace) {
      print('[FLOW_PAGE] ERROR in _loadArticles: $e');
      print('[FLOW_PAGE] Stack trace: $stackTrace');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading articles: $e')),
        );
      }
    }
  }

  Future<void> _saveFilter(String filter) async {
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account != null) {
        final updatedAccount = account.copyWith(lastFlowFilter: filter);
        await ref.read(accountServiceProvider).updateAccount(updatedAccount);
      }
    } catch (e) {
      print('Error saving filter: $e');
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
                _saveFilter('unread');
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
                _saveFilter('starred');
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
      body: Builder(
        builder: (context) {
          print('[FLOW_PAGE] build() called: _isLoading=$_isLoading, _articles.length=${_articles.length}, filter=$_filter');
          return _isLoading
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
                          const SizedBox(height: 16),
                          // Debug info
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'Debug: Filter=$_filter\nArticles in state: ${_articles.length}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                              textAlign: TextAlign.center,
                            ),
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
                          if (index == 0) {
                            print('[FLOW_PAGE] Building first article card, total items: ${_articles.length}');
                          }
                          final articleWithFeed = _articles[index];
                          return _buildArticleCard(articleWithFeed);
                        },
                      ),
                    );
        },
      ),
    );
  }

  Widget _buildCardWidget(Article article, Feed feed, bool isRtl, TextDirection textDirection, BuildContext context) {
    return Card(
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
        onLongPress: () {
          _showLongPressMenu(context, article);
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
                        ? CachedNetworkImage(
                            imageUrl: article.img!,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            alignment: Alignment.topLeft,
                            errorWidget: (context, url, error) => _buildPlaceholderImage(),
                            placeholder: (context, url) => Container(
                              width: 100,
                              height: 100,
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
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
                        ? CachedNetworkImage(
                            imageUrl: article.img!,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            alignment: Alignment.topLeft,
                            errorWidget: (context, url, error) => _buildPlaceholderImage(),
                            placeholder: (context, url) => Container(
                              width: 100,
                              height: 100,
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          )
                        : _buildPlaceholderImage(),
                  ),
                ],
              ],
            ),
          ),
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

        return _SlidableWithAutoTrigger(
          key: ValueKey(article.id),
          article: article,
          swipeStartAction: swipeStartAction,
          swipeEndAction: swipeEndAction,
          isRtl: isRtl,
          onSwipeAction: _handleSwipeAction,
          onDismissibleAction: _handleDismissibleAction,
          buildStartActionPane: _buildStartActionPane,
          buildEndActionPane: _buildEndActionPane,
          buildCard: () => _buildCardWidget(article, feed, isRtl, textDirection, context),
        );
      },
    );
  }

  ActionPane? _buildStartActionPane(int action, Article article, bool isRtl) {
    if (action == 0) return null; // None

    return ActionPane(
      motion: const DrawerMotion(),
      extentRatio: 0.35,
      dismissible: DismissiblePane(
        onDismissed: () => _handleDismissibleAction(action, article),
      ),
      children: [
        SlidableAction(
          onPressed: (_) => _handleSwipeAction(action, article),
          backgroundColor: _getActionColor(action),
          foregroundColor: Colors.white,
          icon: _getActionIcon(action),
          label: _getActionLabel(action, article),
          autoClose: true,
          flex: 1,
        ),
      ],
    );
  }

  ActionPane? _buildEndActionPane(int action, Article article, bool isRtl) {
    if (action == 0) return null; // None

    return ActionPane(
      motion: const DrawerMotion(),
      extentRatio: 0.35,
      dismissible: DismissiblePane(
        onDismissed: () => _handleDismissibleAction(action, article),
      ),
      children: [
        SlidableAction(
          onPressed: (_) => _handleSwipeAction(action, article),
          backgroundColor: _getActionColor(action),
          foregroundColor: Colors.white,
          icon: _getActionIcon(action),
          label: _getActionLabel(action, article),
          autoClose: true,
          flex: 1,
        ),
      ],
    );
  }

  Future<void> _handleDismissibleAction(int action, Article article) async {
    // Required by DismissiblePane: remove from list immediately
    final index = _articles.indexWhere((a) => a.article.id == article.id);
    if (index == -1) return;

    final current = _articles[index];
    setState(() {
      _articles.removeAt(index);
    });

    // Compute updated state and whether it should remain in list
    Article updatedArticle = current.article;
    bool shouldRemain = true;
    switch (action) {
      case 1: // Toggle Read
        updatedArticle = current.article.copyWith(isUnread: !current.article.isUnread);
        if (!updatedArticle.isUnread && _filter == 'unread') {
          shouldRemain = false;
        }
        break;
      case 2: // Toggle Starred
        updatedArticle = current.article.copyWith(isStarred: !current.article.isStarred);
        if (!updatedArticle.isStarred && _filter == 'starred') {
          shouldRemain = false;
        }
        break;
      default:
        shouldRemain = false;
    }

    // Persist in background
    Future.microtask(() async {
      try {
        final articleDao = ref.read(articleDaoProvider);
        switch (action) {
          case 1:
            if (article.isUnread) {
              await articleDao.markAsRead(article.id);
            } else {
              await articleDao.markAsUnread(article.id);
            }
            break;
          case 2:
            await articleDao.toggleStarred(article.id);
            break;
        }
      } catch (e) {
        // If failed, fallback to reload
        if (mounted) _loadArticles();
      }
    });

    // Reinsert on next frame if it should stay visible (e.g., in "all" filter)
    if (shouldRemain && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _articles.insert(
            index.clamp(0, _articles.length),
            ArticleWithFeed(article: updatedArticle, feed: current.feed),
          );
        });
      });
    }
  }

  Future<void> _handleSwipeAction(int action, Article article) async {
    // Update UI immediately for instant feedback
    final index = _articles.indexWhere((a) => a.article.id == article.id);
    if (index != -1) {
      setState(() {
        final currentArticle = _articles[index].article;
        Article updatedArticle;
        bool shouldRemove = false;
        
        switch (action) {
          case 1: // Toggle Read
            updatedArticle = currentArticle.copyWith(isUnread: !currentArticle.isUnread);
            // If marking as read and filter is "unread", remove from list
            if (!updatedArticle.isUnread && _filter == 'unread') {
              shouldRemove = true;
            }
            break;
          case 2: // Toggle Starred
            updatedArticle = currentArticle.copyWith(isStarred: !currentArticle.isStarred);
            // If unstarring and filter is "starred", remove from list
            if (!updatedArticle.isStarred && _filter == 'starred') {
              shouldRemove = true;
            }
            break;
          default:
            return;
        }
        
        if (shouldRemove) {
          // Remove article from list (dismissible behavior)
          _articles.removeAt(index);
        } else {
          // Update article in place
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
        final indicesToUpdate = <int>[];
        for (int i = currentIndex + 1; i < _articles.length; i++) {
          if (_articles[i].article.isUnread) {
            await articleDao.markAsRead(_articles[i].article.id);
            indicesToUpdate.add(i);
            markedCount++;
          }
        }

        // Update UI: remove in unread filter, otherwise mark as read in place
        setState(() {
          if (_filter == 'unread') {
            // Remove from bottom to top to keep indices valid
            for (final idx in indicesToUpdate.reversed) {
              _articles.removeAt(idx);
            }
          } else {
            for (final idx in indicesToUpdate) {
              _articles[idx] = ArticleWithFeed(
                article: _articles[idx].article.copyWith(isUnread: false),
                feed: _articles[idx].feed,
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
}


