import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/article_sort.dart';
import '../database/article_dao.dart';
import '../providers/app_provider.dart';
import '../services/account_service.dart';
import '../services/sync_coordinator.dart';
import '../utils/rtl_helper.dart';
import '../utils/reading_time.dart';
import '../services/shared_preferences_service.dart';
import 'article_reader_screen.dart';
import 'settings_screen.dart';
import 'search_screen.dart';
import 'package:swipe_to_action/swipe_to_action.dart';

class FlowPage extends ConsumerStatefulWidget {
  final Future<void> Function()? onSync;
  
  const FlowPage({super.key, this.onSync});

  @override
  ConsumerState<FlowPage> createState() => FlowPageState();
}

class FlowPageState extends ConsumerState<FlowPage> with WidgetsBindingObserver {
  List<ArticleWithFeed> _articles = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  double _syncProgress = 0.0;
  String _filter = 'all'; // all, unread, starred
  int _refreshKey = 0;
  Timer? _accountRefreshTimer;
  bool _accountListenerSet = false;
  ArticleSortOption _sortOption = ArticleSortOption.dateDesc;
  bool _isBatchMode = false;
  Set<String> _selectedArticleIds = {};
  final SharedPreferencesService _prefs = SharedPreferencesService();

  void refresh() {
    setState(() {
      _refreshKey++;
    });
    _loadArticles();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLastFilter();
    _loadSortPreference();
    _startAccountRefreshTimer();
  }

  Future<void> _loadSortPreference() async {
    await _prefs.init();
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account != null) {
      final sortIndex = await _prefs.getInt('sort_option_${account.id}');
      if (sortIndex != null && sortIndex >= 0 && sortIndex < ArticleSortOption.values.length) {
        setState(() {
          _sortOption = ArticleSortOption.values[sortIndex];
        });
      }
    }
    _loadArticles();
  }

  Future<void> _saveSortPreference() async {
    await _prefs.init();
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account != null) {
      await _prefs.setInt('sort_option_${account.id}', _sortOption.index);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accountRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(currentAccountProvider);
      _loadArticles();
      _startAccountRefreshTimer(); // Restart timer when resumed
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _accountRefreshTimer?.cancel(); // Stop timer when paused/inactive
    }
    super.didChangeAppLifecycleState(state);
  }

  void _startAccountRefreshTimer() {
    _accountRefreshTimer?.cancel();
    // Only refresh when app is in foreground - increased to 10 minutes to reduce battery usage
    // The account provider will still update on user actions (sync, account changes, etc.)
    _accountRefreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (mounted) {
        ref.invalidate(currentAccountProvider);
      }
    });
  }

  Future<void> _loadLastFilter() async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account != null && account.lastFlowFilter.isNotEmpty) {
      _filter = account.lastFlowFilter;
    }
    _loadArticles();
  }

  Future<void> _saveFilter() async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account != null) {
      await ref.read(accountServiceProvider).updateAccount(
        account.copyWith(lastFlowFilter: _filter),
      );
    }
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
      
      // Use new sorting method
      articles = await articleDao.getArticlesWithSort(
        accountId: account.id!,
        sortOption: _sortOption,
        unread: _filter == 'unread' ? true : (_filter == 'starred' ? null : null),
        starred: _filter == 'starred' ? true : null,
        limit: 500,
      );

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

      // If sorting by feed, we need to sort the combined list
      if (_sortOption == ArticleSortOption.feedAsc || _sortOption == ArticleSortOption.feedDesc) {
        articlesWithFeed.sort((a, b) {
          final feedA = a.feed as Feed;
          final feedB = b.feed as Feed;
          final comparison = feedA.name.compareTo(feedB.name);
          return _sortOption == ArticleSortOption.feedAsc ? comparison : -comparison;
        });
      }

      setState(() {
        _articles = articlesWithFeed;
        _isLoading = false;
        if (_isBatchMode) {
          _selectedArticleIds.clear();
        }
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
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _syncProgress = 0.0;
    });
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account != null) {
        final syncCoordinator = ref.read(syncCoordinatorProvider);
        await syncCoordinator.syncAccount(
          account.id!,
          onProgressPercent: (progress) {
            if (mounted) {
              setState(() {
                _syncProgress = progress;
              });
            }
          },
        );
        await ref.read(accountServiceProvider).updateAccount(
              account.copyWith(updateAt: DateTime.now()),
            );
        ref.invalidate(currentAccountProvider);
        _loadArticles();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error syncing: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgress = 0.0;
        });
      }
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      final ids = _articles
          .where((a) => a.article.isUnread)
          .map((a) => a.article.id)
          .toList();
      if (account != null && ids.isNotEmpty) {
        final actions = ref.read(articleActionServiceProvider);
        await actions.batchMarkAsRead(ids, account.id!);
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
    if (!_accountListenerSet) {
      _accountListenerSet = true;
      ref.listen(currentAccountProvider, (_, __) {
        _loadArticles();
      });
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
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
                _saveFilter();
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
                _saveFilter();
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
                _saveFilter();
                _loadArticles();
              },
            ),
            if (!isSmallScreen) ...[
              const SizedBox(width: 8),
              const Text('Articles'),
            ],
          ],
        ),
        actions: [
          if (_isBatchMode) ...[
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel Selection',
              onPressed: () {
                setState(() {
                  _isBatchMode = false;
                  _selectedArticleIds.clear();
                });
              },
            ),
          ] else if (isSmallScreen) ...[
            // On small screens, put most actions in a menu
            PopupMenuButton<ArticleSortOption>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort',
              onSelected: (option) {
                setState(() {
                  _sortOption = option;
                });
                _saveSortPreference();
                _loadArticles();
              },
              itemBuilder: (context) => ArticleSortOption.values.map((option) {
                return PopupMenuItem(
                  value: option,
                  child: Row(
                    children: [
                      if (_sortOption == option)
                        const Icon(Icons.check, size: 20)
                      else
                        const SizedBox(width: 20),
                      const SizedBox(width: 8),
                      Text(option.displayName),
                    ],
                  ),
                );
              }).toList(),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More',
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'search',
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 20),
                      SizedBox(width: 8),
                      Text('Search'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'select_all',
                  child: Row(
                    children: [
                      Icon(Icons.select_all, size: 20),
                      SizedBox(width: 8),
                      Text('Select Articles'),
                    ],
                  ),
                ),
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
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings, size: 20),
                      SizedBox(width: 8),
                      Text('Settings'),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'search':
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SearchScreen(),
                      ),
                    );
                    break;
                  case 'select_all':
                    setState(() {
                      _isBatchMode = true;
                    });
                    break;
                  case 'mark_all_read':
                    _markAllAsRead();
                    break;
                  case 'settings':
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                    break;
                }
              },
            ),
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              tooltip: 'Sync All Feeds',
              onPressed: _isSyncing
                  ? null
                  : () async {
                      // Use _syncAll which has progress tracking
                      await _syncAll();
                    },
            ),
          ] else ...[
            // On larger screens, show all actions as icon buttons
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SearchScreen(),
                  ),
                );
              },
            ),
            PopupMenuButton<ArticleSortOption>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort',
              onSelected: (option) {
                setState(() {
                  _sortOption = option;
                });
                _saveSortPreference();
                _loadArticles();
              },
              itemBuilder: (context) => ArticleSortOption.values.map((option) {
                return PopupMenuItem(
                  value: option,
                  child: Row(
                    children: [
                      if (_sortOption == option)
                        const Icon(Icons.check, size: 20)
                      else
                        const SizedBox(width: 20),
                      const SizedBox(width: 8),
                      Text(option.displayName),
                    ],
                  ),
                );
              }).toList(),
            ),
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select Articles',
              onPressed: () {
                setState(() {
                  _isBatchMode = true;
                });
              },
            ),
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
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              tooltip: 'Sync All Feeds',
              onPressed: _isSyncing
                  ? null
                  : () async {
                      // Use _syncAll which has progress tracking
                      await _syncAll();
                    },
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildSyncInfo(),
                    if (_isSyncing && _syncProgress > 0.0) _buildSyncProgress(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _syncAll,
                        child: _articles.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.6,
                                    child: Center(
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
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: ValueKey(_refreshKey),
                                padding: EdgeInsets.only(
                                  bottom: _isBatchMode && _selectedArticleIds.isNotEmpty ? 120 : 96,
                                ),
                                itemCount: _articles.length,
                                itemBuilder: (context, index) {
                                  final articleWithFeed = _articles[index];
                                  return _buildArticleCard(articleWithFeed);
                                },
                              ),
                      ),
                    ),
                  ],
                ),
          if (_isBatchMode && _selectedArticleIds.isNotEmpty)
            _buildBatchActionBar(),
        ],
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
    final alignRight = isRtl || Directionality.of(context) == TextDirection.rtl || (feed.isRtl ?? false);
    final isSelected = _selectedArticleIds.contains(article.id);
    final readingTime = ReadingTime.calculateAndFormat(
      article.fullContent ?? article.rawDescription,
    );

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
                side: isSelected
                    ? BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : BorderSide.none,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  if (_isBatchMode) {
                    _toggleArticleSelection(article.id);
                  } else {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => ArticleReaderScreen(article: article),
                          ),
                        )
                        .then((_) async {
                          // Reload articles immediately - database updates should be committed
                          // For remote accounts (Miniflux/FreshRSS), the markAsRead operation
                          // updates the local DB first, then syncs to server
                          _loadArticles();
                        });
                  }
                },
                onLongPress: () {
                  if (!_isBatchMode) {
                    _showLongPressMenu(context, article);
                  } else {
                    _toggleArticleSelection(article.id);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isBatchMode) ...[
                          Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleArticleSelection(article.id),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (!isRtl) ...[
                          _buildArticleImage(article),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment:
                                alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                                      textAlign: alignRight ? TextAlign.right : TextAlign.left,
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
                                textAlign: alignRight ? TextAlign.right : TextAlign.left,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                alignment: alignRight ? WrapAlignment.end : WrapAlignment.start,
                                children: [
                                  Text(
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
                                  if (readingTime.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.timer_outlined,
                                          size: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.5),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          readingTime,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                fontSize: 11,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.5),
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.5),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        _formatDate(article.date),
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              fontSize: 11,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.5),
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
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
        final actions = ref.read(articleActionServiceProvider);
        switch (action) {
          case 1: // Toggle Read
            if (article.isUnread) {
              await actions.markAsRead(article);
            } else {
              await actions.markAsUnread(article);
            }
            break;
          case 2: // Toggle Starred
            await actions.toggleStar(article);
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
            ListTile(
              leading: const Icon(Icons.select_all),
              title: const Text('Select Articles'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _isBatchMode = true;
                  _selectedArticleIds.add(article.id);
                });
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

  Future<void> _batchMarkAsRead() async {
    if (_selectedArticleIds.isEmpty) return;
    final count = _selectedArticleIds.length;
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account != null) {
        final actions = ref.read(articleActionServiceProvider);
        await actions.batchMarkAsRead(_selectedArticleIds.toList(), account.id!);
      }
      setState(() {
        _selectedArticleIds.clear();
        _isBatchMode = false;
      });
      _loadArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked $count articles as read')),
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

  Future<void> _batchMarkAsUnread() async {
    if (_selectedArticleIds.isEmpty) return;
    final count = _selectedArticleIds.length;
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account != null) {
        final actions = ref.read(articleActionServiceProvider);
        await actions.batchMarkAsUnread(_selectedArticleIds.toList(), account.id!);
      }
      setState(() {
        _selectedArticleIds.clear();
        _isBatchMode = false;
      });
      _loadArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked $count articles as unread')),
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

  Future<void> _batchStar() async {
    if (_selectedArticleIds.isEmpty) return;
    final count = _selectedArticleIds.length;
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account != null) {
        final actions = ref.read(articleActionServiceProvider);
        await actions.batchStar(_selectedArticleIds.toList(), account.id!);
      }
      setState(() {
        _selectedArticleIds.clear();
        _isBatchMode = false;
      });
      _loadArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Starred $count articles')),
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

  Future<void> _batchUnstar() async {
    if (_selectedArticleIds.isEmpty) return;
    final count = _selectedArticleIds.length;
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account != null) {
        final actions = ref.read(articleActionServiceProvider);
        await actions.batchUnstar(_selectedArticleIds.toList(), account.id!);
      }
      setState(() {
        _selectedArticleIds.clear();
        _isBatchMode = false;
      });
      _loadArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unstarred $count articles')),
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

  Future<void> _batchDelete() async {
    if (_selectedArticleIds.isEmpty) return;
    final count = _selectedArticleIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Articles'),
        content: Text('Are you sure you want to delete $count articles?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    
    try {
      final articleDao = ref.read(articleDaoProvider);
      await articleDao.batchDelete(_selectedArticleIds.toList());
      setState(() {
        _selectedArticleIds.clear();
        _isBatchMode = false;
      });
      _loadArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $count articles')),
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

  void _toggleArticleSelection(String articleId) {
    setState(() {
      if (_selectedArticleIds.contains(articleId)) {
        _selectedArticleIds.remove(articleId);
      } else {
        _selectedArticleIds.add(articleId);
      }
    });
  }

  Future<void> _markBelowAsRead(Article article) async {
    try {
      final actions = ref.read(articleActionServiceProvider);
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      final currentIndex = _articles.indexWhere((a) => a.article.id == article.id);
      
      if (currentIndex != -1) {
        // Mark all articles below this one as read
        int markedCount = 0;
        final indicesToRemove = <int>[];
        final idsToMark = <String>[];
        for (int i = currentIndex + 1; i < _articles.length; i++) {
          if (_articles[i].article.isUnread) {
            idsToMark.add(_articles[i].article.id);
            markedCount++;
            if (_filter == 'unread') {
              indicesToRemove.add(i);
            }
          }
        }
        if (account != null && idsToMark.isNotEmpty) {
          await actions.batchMarkAsRead(idsToMark, account.id!);
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
    // Ensure both dates are in local timezone for accurate comparison
    final now = DateTime.now();
    final localDate = date.isUtc ? date.toLocal() : date;
    final difference = now.difference(localDate);

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
    final accountAsync = ref.watch(currentAccountProvider);
    return accountAsync.when(
      data: (account) {
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
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildSyncProgress() {
    final percentage = (_syncProgress * 100).toStringAsFixed(0);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: _syncProgress,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$percentage%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchActionBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 90, // Position above bottom nav bar (12 + 62 + 16 padding)
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBatchActionButton(
                  icon: Icons.star,
                  label: 'Star',
                  onPressed: _batchStar,
                  color: Colors.orange,
                ),
                _buildBatchActionButton(
                  icon: Icons.star_border,
                  label: 'Unstar',
                  onPressed: _batchUnstar,
                  color: Colors.orange,
                ),
                _buildBatchActionButton(
                  icon: Icons.done_all,
                  label: 'Read',
                  onPressed: _batchMarkAsRead,
                  color: Colors.blue,
                ),
                _buildBatchActionButton(
                  icon: Icons.mark_email_unread,
                  label: 'Unread',
                  onPressed: _batchMarkAsUnread,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBatchActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: color,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


