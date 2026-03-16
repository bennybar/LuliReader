import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/article_sort.dart';
import '../providers/app_provider.dart';
import '../utils/rtl_helper.dart';
import '../services/shared_preferences_service.dart';
import 'article_reader_screen.dart';
import 'settings_screen.dart';
import 'search_screen.dart';
import '../widgets/filter_drawer.dart';
import 'package:swipe_to_action/swipe_to_action.dart';
import '../theme/app_symbols.dart';

class FlowPage extends ConsumerStatefulWidget {
  final Future<void> Function()? onSync;
  
  const FlowPage({super.key, this.onSync});

  @override
  ConsumerState<FlowPage> createState() => FlowPageState();
}

class FlowPageState extends ConsumerState<FlowPage> with WidgetsBindingObserver {
  static const _swipeTriggerThreshold = 0.24;
  static const _swipeMaxOffset = 0.32;
  static const _swipeMovementDuration = Duration(milliseconds: 140);

  List<ArticleWithFeed> _articles = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  double _syncProgress = 0.0;
  String _filter = 'all'; // all, unread, starred
  int _refreshKey = 0;
  Timer? _accountRefreshTimer;
  bool _filterListenerSet = false;
  ArticleSortOption _sortOption = ArticleSortOption.dateDesc;
  bool _isBatchMode = false;
  Set<String> _selectedArticleIds = {};
  final SharedPreferencesService _prefs = SharedPreferencesService();
  final ScrollController _scrollController = ScrollController();
  ProviderSubscription<Set<String>>? _groupFilterSub;
  ProviderSubscription<Set<String>>? _feedFilterSub;
  ProviderSubscription<AsyncValue<dynamic>>? _accountSub;
  bool _showPreviewText = true;
  bool _showHeroImage = true; // simple on/off
  double _listFontScale = 1.0;
  int _swipeStartAction = 2;
  int _swipeEndAction = 1;

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
    _loadArticleViewPrefs();
    _loadSwipeActions();
    _startAccountRefreshTimer();
    // Set up listeners after first frame to ensure ref is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupFilterListeners();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload preferences when screen becomes visible (e.g., returning from settings)
    _loadArticleViewPrefs();
  }

  Future<void> _loadArticleViewPrefs() async {
    await _prefs.init();
    final showPreviewTextValue = await _prefs.getBool('showPreviewText');
    // New: showHeroImage on/off. Backward compatibility: map old heroImagePosition.
    final legacyHeroPosition = await _prefs.getString('heroImagePosition');
    final showHeroImageValue =
        await _prefs.getBool('showHeroImage') ??
            (legacyHeroPosition == 'none' ? false : true);
    final listFontScaleValue = await _prefs.getDouble('articleListFontScale') ?? 1.0;

    if (mounted) {
      setState(() {
        _showPreviewText = showPreviewTextValue ?? true;
        _showHeroImage = showHeroImageValue;
        _listFontScale = listFontScaleValue;
      });
    }
  }

  Future<void> _loadSwipeActions() async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (!mounted || account == null) return;
    setState(() {
      _swipeStartAction = account.swipeStartAction;
      _swipeEndAction = account.swipeEndAction;
    });
  }

  void _setFilter(String value) {
    setState(() {
      _filter = value;
      _refreshKey++;
    });
    _saveFilter();
    _loadArticles();
  }

  Future<void> _openFlowSettings() async {
    await Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => const SettingsScreen(),
          ),
        )
        .then((_) async {
      await _loadArticleViewPrefs();
      if (mounted) {
        setState(() => _refreshKey++);
        _loadArticles();
      }
    });
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SearchScreen(),
      ),
    );
  }

  Future<void> _showListFontSizeDialog(BuildContext context) async {
    await _prefs.init();
    final baseSize = Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16.0;
    double tempFontSize = baseSize * _listFontScale;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> updateSize(double newSize) async {
            setDialogState(() {
              tempFontSize = newSize.clamp(10.0, 32.0);
            });
            final newScale = tempFontSize / baseSize;
            await _prefs.setDouble('articleListFontScale', newScale);
            if (mounted) {
              setState(() => _listFontScale = newScale);
            }
          }

          Future<void> resetSize() async {
            await updateSize(baseSize);
          }

          return AlertDialog(
            title: const Text('List Font Size'),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(AppSymbols.remove),
                  onPressed: () => updateSize(tempFontSize - 1),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    '${tempFontSize.toStringAsFixed(0)} px',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(AppSymbols.add),
                  onPressed: () => updateSize(tempFontSize + 1),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: resetSize,
                child: const Text('Reset'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSortBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: ArticleSortOption.values.map((option) {
              return ListTile(
                leading: Icon(
                  _sortOption == option ? AppSymbols.radio_button_checked : AppSymbols.radio_button_off,
                ),
                title: Text(option.displayName),
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _sortOption = option;
                  });
                  _saveSortPreference();
                  _loadArticles();
                },
              );
            }).toList(),
          ),
        );
      },
    );
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
    _scrollController.dispose();
    _groupFilterSub?.close();
    _feedFilterSub?.close();
    _accountSub?.close();
    super.dispose();
  }

  Future<void> _setupFilterListeners() async {
    // Listen for account changes to reattach filter listeners
    _accountSub ??= ref.listenManual(currentAccountProvider, (previous, next) async {
      _filterListenerSet = false;
      await _setupFilterListeners();
      _loadArticles();
    });

    if (_filterListenerSet) return;

    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account == null) return;

    // Close existing listeners if any
    _groupFilterSub?.close();
    _feedFilterSub?.close();

    _groupFilterSub = ref.listenManual(groupFilterProvider(account.id!), (previous, next) {
      if (previous != next && mounted) {
        _loadArticles();
      }
    });

    _feedFilterSub = ref.listenManual(feedFilterProvider(account.id!), (previous, next) {
      if (previous != next && mounted) {
        _loadArticles();
      }
    });

    _filterListenerSet = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(currentAccountProvider);
      _loadSwipeActions();
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

      // Filter by selected groups and feeds
      final visibleGroupIds = ref.read(groupFilterProvider(account.id!));
      final visibleFeedIds = ref.read(feedFilterProvider(account.id!));
      
      if (visibleGroupIds.isNotEmpty || visibleFeedIds.isNotEmpty) {
        // Get all feeds
        final allFeeds = await feedDao.getAll(account.id!);
        Set<String> allowedFeedIds;
        
        if (visibleFeedIds.isNotEmpty) {
          // If feed filter is set, use it (more specific)
          allowedFeedIds = visibleFeedIds;
        } else if (visibleGroupIds.isNotEmpty) {
          // Otherwise, filter by group
          allowedFeedIds = allFeeds
              .where((feed) => visibleGroupIds.contains(feed.groupId))
              .map((feed) => feed.id)
              .toSet();
        } else {
          allowedFeedIds = allFeeds.map((feed) => feed.id).toSet();
        }
        
        articles = articles.where((article) => allowedFeedIds.contains(article.feedId)).toList();
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

  Future<void> _updateArticleAfterReading(String articleId, double scrollPosition, int articleIndex) async {
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account == null) return;

      final articleDao = ref.read(articleDaoProvider);
      final feedDao = ref.read(feedDaoProvider);
      
      // Get updated article from database
      final updatedArticle = await articleDao.getById(articleId);
      if (updatedArticle == null) return;

      // Check if article should be removed based on current filter
      final shouldRemove = (_filter == 'unread' && !updatedArticle.isUnread) ||
                          (_filter == 'starred' && !updatedArticle.isStarred);

      setState(() {
        if (shouldRemove && articleIndex < _articles.length && _articles[articleIndex].article.id == articleId) {
          // Remove article from list
          _articles.removeAt(articleIndex);
        } else {
          // Update article in place
          final index = _articles.indexWhere((a) => a.article.id == articleId);
          if (index != -1) {
            final feed = _articles[index].feed;
            _articles[index] = ArticleWithFeed(
              article: updatedArticle,
              feed: feed,
            );
          }
        }
      });

      // Restore scroll position
      if (_scrollController.hasClients && scrollPosition > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(scrollPosition);
          }
        });
      }
    } catch (e) {
      // If incremental update fails, fall back to full reload
      _loadArticles();
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
    final media = MediaQuery.of(context);
    final scaledMedia = media.copyWith(
      textScaler: TextScaler.linear(_listFontScale),
    );
    return MediaQuery(
      data: scaledMedia,
      child: Scaffold(
      drawer: FilterDrawer(onFiltersChanged: _loadArticles),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_isBatchMode ? '${_selectedArticleIds.length} selected' : 'Articles'),
        bottom: _isBatchMode
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<String>(
                      multiSelectionEnabled: false,
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('All')),
                        ButtonSegment(value: 'unread', label: Text('Unread')),
                        ButtonSegment(value: 'starred', label: Text('Starred')),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (selection) => _setFilter(selection.first),
                    ),
                  ),
                ),
              ),
        actions: [
          if (_isBatchMode) ...[
            IconButton(
              icon: const Icon(AppSymbols.close),
              tooltip: 'Cancel Selection',
              onPressed: () {
                setState(() {
                  _isBatchMode = false;
                  _selectedArticleIds.clear();
                });
              },
            ),
          ] else ...[
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(AppSymbols.tune),
                tooltip: 'Filters',
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            IconButton(
              icon: const Icon(AppSymbols.search),
              tooltip: 'Search',
              onPressed: _openSearch,
            ),
            PopupMenuButton<String>(
              icon: const Icon(AppSymbols.more_vert),
              tooltip: 'More',
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'sort',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.sort),
                    title: Text('Change Sort'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'font_size',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.text_fields),
                    title: Text('List Font Size'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'select_all',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.select_all),
                    title: Text('Select Articles'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'mark_all_read',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.done_all),
                    title: Text('Mark All as Read'),
                  ),
                ),
                PopupMenuItem(
                  value: 'sync',
                  enabled: !_isSyncing,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(AppSymbols.sync),
                    title: const Text('Sync'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.settings_outlined),
                    title: Text('Settings'),
                  ),
                ),
              ],
              onSelected: (value) async {
                switch (value) {
                  case 'sort':
                    _showSortBottomSheet();
                    break;
                  case 'font_size':
                    _showListFontSizeDialog(context);
                    break;
                  case 'select_all':
                    setState(() {
                      _isBatchMode = true;
                    });
                    break;
                  case 'mark_all_read':
                    await _markAllAsRead();
                    break;
                  case 'sync':
                    await _syncAll();
                    break;
                  case 'settings':
                    await _openFlowSettings();
                    break;
                }
              },
            ),
          ],
          if (_isBatchMode)
            PopupMenuButton<String>(
              icon: const Icon(AppSymbols.more_vert),
              tooltip: 'More',
              itemBuilder: (context) => [
                if (_selectedArticleIds.isNotEmpty && _isBatchMode) ...const [
                  PopupMenuItem(
                    value: 'mark_selected_read',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(AppSymbols.done_all),
                      title: Text('Mark Selected Read'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'mark_selected_unread',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(AppSymbols.mark_email_unread),
                      title: Text('Mark Selected Unread'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'star_selected',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(AppSymbols.star_outline),
                      title: Text('Star Selected'),
                    ),
                  ),
                ] else ...[
                  const PopupMenuItem(
                    value: 'sort',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(AppSymbols.sort),
                      title: Text('Change Sort'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'font_size',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(AppSymbols.text_fields),
                      title: Text('List Font Size'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'select_all',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(AppSymbols.select_all),
                      title: Text('Select Articles'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'mark_all_read',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(AppSymbols.done_all),
                      title: Text('Mark All as Read'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sync',
                    enabled: !_isSyncing,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(AppSymbols.sync),
                      title: const Text('Sync'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(AppSymbols.settings_outlined),
                      title: Text('Settings'),
                    ),
                  ),
                ],
              ],
              onSelected: (value) async {
                switch (value) {
                  case 'mark_selected_read':
                    await _batchMarkAsRead();
                    break;
                  case 'mark_selected_unread':
                    await _batchMarkAsUnread();
                    break;
                  case 'star_selected':
                    await _batchStar();
                    break;
                  case 'sort':
                    _showSortBottomSheet();
                    break;
                  case 'font_size':
                    _showListFontSizeDialog(context);
                    break;
                  case 'select_all':
                    setState(() {
                      _isBatchMode = true;
                    });
                    break;
                  case 'mark_all_read':
                    await _markAllAsRead();
                    break;
                  case 'sync':
                    await _syncAll();
                    break;
                  case 'settings':
                    await _openFlowSettings();
                    break;
                }
              },
            ),
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
                                            AppSymbols.article,
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
                                controller: _scrollController,
                                cacheExtent: 1200,
                                padding: EdgeInsets.only(
                                  bottom: _isBatchMode && _selectedArticleIds.isNotEmpty ? 120 : 96,
                                ),
                                itemCount: _articles.length,
                                itemBuilder: (context, index) {
                                  final articleWithFeed = _articles[index];
                                  return _buildArticleCard(articleWithFeed, index);
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
    ),
  );
  }

  Widget _buildArticleCard(ArticleWithFeed articleWithFeed, int index) {
    final article = articleWithFeed.article;
    final feed = articleWithFeed.feed as Feed;
    final contentText = '${article.title} ${article.shortDescription}';
    final textDirection =
        RtlHelper.getTextDirectionFromContent(contentText, feedRtl: feed.isRtl);
    final isRtl = textDirection == TextDirection.rtl;
    final alignRight = isRtl || Directionality.of(context) == TextDirection.rtl || (feed.isRtl ?? false);
    final isSelected = _selectedArticleIds.contains(article.id);
    final hasThumbnail = _showHeroImage && article.img != null && article.img!.isNotEmpty;
    return Directionality(
      textDirection: textDirection,
      child: Swipeable(
        key: ValueKey('${article.id}_${_refreshKey}'),
        direction: SwipeDirection.horizontal,
        dismissThresholds: const {
          SwipeDirection.startToEnd: _swipeTriggerThreshold,
          SwipeDirection.endToStart: _swipeTriggerThreshold,
        },
        maxOffset: _swipeMaxOffset,
        movementDuration: _swipeMovementDuration,
        dragStartBehavior: DragStartBehavior.down,
        background: _buildSwipeBackground(
          context,
          textDirection,
          _swipeStartAction,
          article,
          isStart: true,
        ),
        secondaryBackground: _buildSwipeBackground(
          context,
          textDirection,
          _swipeEndAction,
          article,
          isStart: false,
        ),
        confirmSwipe: (dir) async {
          if (!mounted) return false;
          final action = dir == SwipeDirection.startToEnd ? _swipeStartAction : _swipeEndAction;
          if (action == 0) return false;
          return await _handleSwipeAction(action, article, fromSwipe: true);
        },
        onSwipe: (_) {
          if (!mounted) return;
        },
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: isSelected
                ? BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  )
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              if (_isBatchMode) {
                _toggleArticleSelection(article.id);
              } else {
                if (!mounted) return;
                final scrollPosition =
                    _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
                final articleIndex = index;

                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => ArticleReaderScreen(article: article),
                      ),
                    )
                    .then((_) async {
                      if (mounted) {
                        await _updateArticleAfterReading(article.id, scrollPosition, articleIndex);
                      }
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                textDirection: TextDirection.ltr, // keep hero image visually on the right
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isBatchMode) ...[
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleArticleSelection(article.id),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: hasThumbnail ? 72 : 0),
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
                                    fontSize: 14,
                                    height: 1.22,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: alignRight ? TextAlign.right : TextAlign.left,
                                ),
                              ),
                              if (article.isStarred)
                                Padding(
                                  padding:
                                      EdgeInsets.only(left: isRtl ? 0 : 8, right: isRtl ? 8 : 0),
                                  child: Icon(
                                    AppSymbols.star,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                            ],
                          ),
                          if (_showPreviewText) ...[
                            const SizedBox(height: 3),
                            Text(
                              article.shortDescription,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color:
                                        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: alignRight ? TextAlign.right : TextAlign.left,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Align(
                            alignment: alignRight
                                ? AlignmentDirectional.centerEnd
                                : Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    feed.name,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.52),
                                          fontSize: 10.5,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: alignRight ? TextAlign.right : TextAlign.left,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      AppSymbols.access_time,
                                      size: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.52),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      _formatDate(article.date),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontSize: 10.5,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.52),
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (hasThumbnail) ...[
                    const SizedBox(width: 10),
                    _buildArticleImage(article),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _handleSwipeAction(int action, Article article, {bool fromSwipe = false}) async {
    if (!mounted) return false;
    // Update UI immediately for instant feedback
    final index = _articles.indexWhere((a) => a.article.id == article.id);
    bool shouldRemove = false;
    if (index != -1 && mounted) {
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
      if (!mounted) return;
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
          if (updatedArticle != null && mounted) {
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
    final double heroSize = (76 * _listFontScale).clamp(68.0, 88.0).toDouble();
    final double placeholderIconSize =
        (40 * _listFontScale).clamp(28.0, 80.0).toDouble();
    final targetCacheWidth = _targetImageCacheWidth(heroSize);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: article.img != null && article.img!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: article.img!,
              width: heroSize,
              height: heroSize,
              fit: BoxFit.cover,
              alignment: Alignment.topLeft,
              memCacheWidth: targetCacheWidth,
              maxWidthDiskCache: targetCacheWidth,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              errorWidget: (context, url, error) => _buildPlaceholderImage(
                size: heroSize,
                iconSize: placeholderIconSize,
              ),
              placeholder: (context, url) => _buildPlaceholderImage(
                size: heroSize,
                iconSize: placeholderIconSize,
              ),
            )
          : _buildPlaceholderImage(
              size: heroSize,
              iconSize: placeholderIconSize,
            ),
    );
  }

  IconData _getActionIcon(int action) {
    switch (action) {
      case 1: // Toggle Read
        return AppSymbols.visibility;
      case 2: // Toggle Starred
        return AppSymbols.star;
      default:
        return AppSymbols.help;
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

  Widget _buildPlaceholderImage({double? size, double? iconSize}) {
    final heroSize = size ?? (100 * _listFontScale).clamp(72.0, 160.0);
    final placeholderIconSize = iconSize ?? (40 * _listFontScale).clamp(28.0, 80.0);

    return Container(
      width: heroSize,
      height: heroSize,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        AppSymbols.photo_outlined,
        size: placeholderIconSize,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
      ),
    );
  }

  int _targetImageCacheWidth(double logicalWidth) {
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    return (logicalWidth * devicePixelRatio).round();
  }

  void _showLongPressMenu(BuildContext context, Article article) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppSymbols.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                _shareArticle(article);
              },
            ),
            ListTile(
              leading: const Icon(AppSymbols.done_all),
              title: const Text('Mark Below as Read'),
              onTap: () {
                Navigator.pop(context);
                _markBelowAsRead(article);
              },
            ),
            ListTile(
              leading: const Icon(AppSymbols.select_all),
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
    // Use local time consistently to avoid double-offset issues
    final now = DateTime.now();
    final articleLocal = date.isUtc ? date.toLocal() : date;
    final difference = now.difference(articleLocal);

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
              const Icon(AppSymbols.history, size: 16),
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
                  icon: AppSymbols.star,
                  label: 'Star',
                  onPressed: _batchStar,
                  color: Colors.orange,
                ),
                _buildBatchActionButton(
                  icon: AppSymbols.star_border,
                  label: 'Unstar',
                  onPressed: _batchUnstar,
                  color: Colors.orange,
                ),
                _buildBatchActionButton(
                  icon: AppSymbols.done_all,
                  label: 'Read',
                  onPressed: _batchMarkAsRead,
                  color: Colors.blue,
                ),
                _buildBatchActionButton(
                  icon: AppSymbols.mark_email_unread,
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


