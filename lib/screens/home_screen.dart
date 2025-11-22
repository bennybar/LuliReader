import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/article.dart';
import '../models/feed.dart';
import '../models/swipe_action.dart';
import '../notifiers/article_list_padding_notifier.dart';
import '../notifiers/preview_lines_notifier.dart';
import '../notifiers/unread_refresh_notifier.dart';
import '../notifiers/swipe_prefs_notifier.dart';
import '../notifiers/last_sync_notifier.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../utils/article_text_utils.dart';
import '../widgets/article_card.dart';
import 'starred_screen.dart';
import 'unread_screen.dart';
import 'settings_screen.dart';
import 'article_detail_screen.dart';
import '../widgets/platform_bottom_nav.dart';
import '../widgets/platform_app_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _TabConfig {
  final String id;
  final Widget widget;
  final IconData icon;
  final String label;

  const _TabConfig({
    required this.id,
    required this.widget,
    required this.icon,
    required this.label,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _showStarredTab = true;
  final StorageService _storageService = StorageService();
  final DatabaseService _db = DatabaseService();
  final UnreadRefreshNotifier _unreadNotifier = UnreadRefreshNotifier.instance;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadTabPreferences();
    _unreadNotifier.addListener(_handleUnreadChanged);
    _loadUnreadCount();
  }

  @override
  void dispose() {
    _unreadNotifier.removeListener(_handleUnreadChanged);
    super.dispose();
  }

  void _handleUnreadChanged() {
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    final count = await _db.getUnreadCount();
    if (!mounted) return;
    setState(() => _unreadCount = count);
  }

  Future<void> _loadTabPreferences() async {
    final showStarred = await _storageService.getShowStarredTab();
    final defaultTab = await _storageService.getDefaultTab();
    if (!mounted) return;

    // Find the index of the default tab
    final tabs = _getTabConfigs(showStarred);
    int defaultIndex = 0;
    for (int i = 0; i < tabs.length; i++) {
      if (tabs[i].id == defaultTab) {
        defaultIndex = i;
        break;
      }
    }

    setState(() {
      _showStarredTab = showStarred;
      _currentIndex = defaultIndex;
    });
  }

  List<_TabConfig> _getTabConfigs(bool showStarred) {
    final tabs = <_TabConfig>[
      const _TabConfig(
        id: 'home',
        widget: _HomeTab(),
        icon: Icons.home,
        label: 'Home',
      ),
      const _TabConfig(
        id: 'unread',
        widget: UnreadScreen(),
        icon: Icons.mark_email_unread,
        label: 'Unread',
      ),
    ];
    if (showStarred) {
      tabs.add(
        const _TabConfig(
          id: 'starred',
          widget: StarredScreen(),
          icon: Icons.star,
          label: 'Starred',
        ),
      );
    }
    tabs.add(
      _TabConfig(
        id: 'settings',
        widget: SettingsScreen(
          onShowStarredTabChanged: _handleShowStarredTabChanged,
        ),
        icon: Icons.settings,
        label: 'Settings',
      ),
    );
    return tabs;
  }

  void _handleShowStarredTabChanged(bool value) {
    setState(() {
      _showStarredTab = value;
      final tabs = _tabConfigs;
      if (_currentIndex >= tabs.length) {
        _currentIndex = tabs.length - 1;
      }
      final currentTabId = tabs[_currentIndex].id;
      if (!_showStarredTab && currentTabId == 'starred') {
        _currentIndex = 0;
      }
    });
  }

  List<_TabConfig> get _tabConfigs => _getTabConfigs(_showStarredTab);

  @override
  Widget build(BuildContext context) {
    final tabs = _tabConfigs;
    final clampedIndex = _currentIndex.clamp(0, tabs.length - 1);
    if (clampedIndex != _currentIndex) {
      _currentIndex = clampedIndex;
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _currentIndex,
              children: tabs.map((tab) => tab.widget).toList(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: PlatformBottomNav(
              currentIndex: _currentIndex,
              items:
                  tabs
                      .map(
                        (tab) => BottomNavItem(
                          icon: tab.icon,
                          label: tab.label,
                          hasNotification:
                              tab.id == 'unread' && _unreadCount > 0,
                        ),
                      )
                      .toList(),
              onTap: (index) => setState(() => _currentIndex = index),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  final DatabaseService _db = DatabaseService();
  final SyncService _syncService = SyncService();
  final StorageService _storageService = StorageService();
  List<Article> _articles = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreArticles = true;
  bool _isSyncing = false;
  bool _hasSyncConfig = false;
  Map<String, String> _feedTitles = {};
  SwipeAction _leftSwipeAction = SwipeAction.toggleRead;
  SwipeAction _rightSwipeAction = SwipeAction.toggleStar;
  final PreviewLinesNotifier _previewLinesNotifier =
      PreviewLinesNotifier.instance;
  final ArticleListPaddingNotifier _listPaddingNotifier =
      ArticleListPaddingNotifier.instance;
  int _previewLines = 3;
  double _listPadding = 16.0;
  DateTime? _lastSync;
  bool _swipeAllowsDelete = false;
  final SwipePrefsNotifier _swipePrefsNotifier = SwipePrefsNotifier.instance;
  final LastSyncNotifier _lastSyncNotifier = LastSyncNotifier.instance;
  final UnreadRefreshNotifier _unreadNotifier = UnreadRefreshNotifier.instance;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _previewLines = _previewLinesNotifier.lines;
    _listPadding = _listPaddingNotifier.padding;
    _previewLinesNotifier.addListener(_handlePreviewLinesChanged);
    _listPaddingNotifier.addListener(_handleListPaddingChanged);
    _unreadNotifier.addListener(_handleUnreadChanged);
    _swipePrefsNotifier.addListener(_handleSwipePrefsChanged);
    _lastSyncNotifier.addListener(_handleLastSyncChanged);
    _scrollController.addListener(_onScroll);
    _initialize();
  }

  @override
  void dispose() {
    _previewLinesNotifier.removeListener(_handlePreviewLinesChanged);
    _listPaddingNotifier.removeListener(_handleListPaddingChanged);
    _unreadNotifier.removeListener(_handleUnreadChanged);
    _swipePrefsNotifier.removeListener(_handleSwipePrefsChanged);
    _lastSyncNotifier.removeListener(_handleLastSyncChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadFeedTitles();
    await _loadSwipePreferences();
    await _loadPreviewLines();
    await _loadListPadding();
    await _loadLastSyncTime();
    await _loadSwipeDeleteSetting();
    await _loadArticles(reset: true);
  }

  Future<void> _loadPreviewLines() async {
    final lines = await _storageService.getPreviewLines();
    if (!mounted) return;
    setState(() {
      _previewLines = lines;
    });
    _previewLinesNotifier.setLines(lines);
  }

  Future<void> _loadListPadding() async {
    final padding = await _storageService.getArticleListPadding();
    if (!mounted) return;
    setState(() => _listPadding = padding);
    _listPaddingNotifier.setPadding(padding);
  }

  void _handlePreviewLinesChanged() {
    final lines = _previewLinesNotifier.lines;
    if (!mounted || _previewLines == lines) return;
    setState(() => _previewLines = lines);
  }

  void _handleListPaddingChanged() {
    final padding = _listPaddingNotifier.padding;
    if (!mounted || (_listPadding - padding).abs() < 0.5) return;
    setState(() => _listPadding = padding);
  }

  void _handleUnreadChanged() {
    // Whenever unread status changes (including from Unread tab or article
    // detail), refresh the Home tab list so read state is immediately reflected.
    _loadArticles(reset: true);
  }

  void _handleSwipePrefsChanged() {
    _loadSwipePreferences();
    _loadSwipeDeleteSetting();
  }

  void _handleLastSyncChanged() {
    _loadLastSyncTime();
  }

  Future<void> _loadLastSyncTime() async {
    final ts = await _storageService.getLastSyncTimestamp();
    if (!mounted) return;
    setState(() {
      _lastSync = ts;
    });
  }

  Future<void> _loadFeedTitles() async {
    final List<Feed> feeds = await _db.getAllFeeds();
    if (!mounted) return;
    setState(() {
      final map = <String, String>{};
      for (final feed in feeds) {
        map[feed.id] = feed.title;
        if (feed.id.startsWith('feed/')) {
          map[feed.id.substring(5)] = feed.title;
        }
      }
      _feedTitles = map;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh articles when returning to this tab
    _loadArticles(reset: true);
    _loadSwipePreferences();
  }

  Future<void> _loadArticles({bool reset = false}) async {
    if (!mounted) return;

    if (reset) {
      setState(() {
        _articles = [];
        _isLoading = true;
        _hasMoreArticles = true;
      });
    } else {
      // Only show the big centered loader when there are no articles yet.
      final hadArticles = _articles.isNotEmpty;
      if (!hadArticles) {
        setState(() => _isLoading = true);
      }
    }

    try {
      // Always show all articles in Home tab
      final articles = await _db.getArticles(
        limit: _pageSize,
        offset: reset ? 0 : _articles.length,
        isRead: null,
      );

      if (mounted) {
        setState(() {
          if (reset) {
            _articles = articles;
          } else {
            _articles.addAll(articles);
          }
          _hasMoreArticles = articles.length == _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading articles: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreArticles() async {
    if (_isLoadingMore || !_hasMoreArticles || !mounted) return;

    setState(() => _isLoadingMore = true);
    try {
      final articles = await _db.getArticles(
        limit: _pageSize,
        offset: _articles.length,
        isRead: null,
      );
      if (mounted) {
        setState(() {
          _articles.addAll(articles);
          _hasMoreArticles = articles.length == _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      print('Error loading more articles: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreArticles();
    }
  }

  Future<void> _loadSwipePreferences() async {
    final left = await _storageService.getSwipeLeftAction();
    final right = await _storageService.getSwipeRightAction();
    if (!mounted) return;
    setState(() {
      _leftSwipeAction = left;
      _rightSwipeAction = right;
    });
  }

  Future<void> _loadSwipeDeleteSetting() async {
    final allowDelete = await _storageService.getSwipeAllowsDelete();
    if (!mounted) return;
    setState(() => _swipeAllowsDelete = allowDelete);
  }

  Future<bool> _ensureSyncConfigured() async {
    if (_hasSyncConfig) return true;
    final config = await _storageService.getUserConfig();
    if (config == null) {
      print('No user config found for sync service');
      return false;
    }
    _syncService.setUserConfig(config);
    _hasSyncConfig = true;
    return true;
  }

  Future<void> _syncArticlesFromServer({bool initial = false}) async {
    if (_isSyncing) return;

    final hasConfig = await _ensureSyncConfigured();
    if (!hasConfig) {
      if (!initial && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to sync: missing account configuration'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isSyncing = true);
    try {
      await _syncService.syncAll(fetchFullContent: false);
      print('Manual sync completed');
      await _loadFeedTitles();
      await _storageService.saveLastSyncTimestamp(DateTime.now());
      await _loadLastSyncTime();
    } catch (e) {
      print('Error syncing articles from server: $e');
      if (!initial && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final isIOSPlatform = Theme.of(context).platform == TargetPlatform.iOS;
    return Scaffold(
      appBar: PlatformAppBar(
        titleWidget: _buildTitleWidget(),
        actions: const [
          // Sync button will be added here if needed
        ],
      ),
      body: Column(
        children: [
          // Slim, non-blocking progress bar for sync
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _isSyncing ? 2 : 0,
            child:
                _isSyncing
                    ? const LinearProgressIndicator(minHeight: 2)
                    : const SizedBox.shrink(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _syncArticlesFromServer();
                await _loadArticles(reset: true);
              },
              child:
                  _isLoading && _articles.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _articles.isEmpty
                      ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text(
                              'No articles found\nPull down to refresh',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                      : ListView.separated(
                        controller: _scrollController,
                        physics:
                            isIOSPlatform
                                ? const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                )
                                : const ClampingScrollPhysics(),
                        cacheExtent: 800,
                        padding: _listViewPadding(),
                        itemCount: _articles.length + (_hasMoreArticles ? 1 : 0),
                        separatorBuilder:
                            (_, __) => SizedBox(height: _cardSpacing),
                        itemBuilder: (context, index) {
                          if (index >= _articles.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final article = _articles[index];
                          return _buildSwipeableCard(article);
                        },
                      ),
            ),
          ),
        ],
      ),
    );
  }

  EdgeInsets _listViewPadding() {
    final horizontal = _listPadding;
    final top = _listPadding * 0.75;
    final bottom = 64 + _listPadding;
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  double get _cardSpacing {
    final spacing = (_listPadding / 16.0) * 12.0;
    return spacing.clamp(8.0, 28.0).toDouble();
  }

  Widget _buildTitleWidget() {
    final theme = Theme.of(context);

    final children = <Widget>[
      Text('All Articles', style: theme.textTheme.titleLarge),
    ];

    if (_lastSync != null) {
      children.add(
        Text(
          _formatSyncTimestamp(_lastSync!),
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: children,
    );
  }

  String _formatSyncTimestamp(DateTime ts) {
    final formatter = DateFormat('MMM d, y • h:mm a');
    return 'Synced ${formatter.format(ts)}';
  }

  Widget _buildSwipeableCard(Article article) {
    return Dismissible(
      key: ValueKey(article.id),
      direction: DismissDirection.horizontal,
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        action: _leftSwipeAction,
        article: article,
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        action: _rightSwipeAction,
        article: article,
      ),
      confirmDismiss: (direction) => _handleSwipeAction(article, direction),
      child: ArticleCard(
        article: article,
        summary: stripHtml(article.summary ?? article.content ?? ''),
        sourceName: _feedTitles[article.feedId] ?? 'Unknown source',
        summaryLines: _previewLines,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ArticleDetailScreen(article: article),
            ),
          ).then((_) => _loadArticles(reset: true));
        },
      ),
    );
  }

  Future<bool> _handleSwipeAction(
    Article article,
    DismissDirection direction,
  ) async {
    final hasConfig = await _ensureSyncConfigured();
    if (!hasConfig) {
      return false;
    }

    final action =
        direction == DismissDirection.startToEnd
            ? _leftSwipeAction
            : _rightSwipeAction;

    // Destructive delete via swipe when action is set to Delete
    if (action == SwipeAction.delete) {
      final deleted = await _syncService.deleteArticle(article.id);
      if (deleted) {
        await _loadArticles(reset: true);
      }
      // Do not dismiss the card; list reload will reflect removal
      return false;
    }

    switch (action) {
      case SwipeAction.toggleRead:
        await _syncService.markArticleAsRead(article.id, !article.isRead);
        await _loadArticles(reset: true);
        break;
      case SwipeAction.toggleStar:
        await _syncService.markArticleAsStarred(article.id, !article.isStarred);
        await _loadArticles(reset: true);
        break;
      case SwipeAction.delete:
        // Handled in the delete branch above.
        break;
    }
    return false; // Don't dismiss
  }
}

class _SwipeBackground extends StatelessWidget {
  final Alignment alignment;
  final SwipeAction action;
  final Article article;

  const _SwipeBackground({
    required this.alignment,
    required this.action,
    required this.article,
  });

  Color get _color {
    switch (action) {
      case SwipeAction.toggleStar:
        return Colors.amber.shade600;
      case SwipeAction.delete:
        return Colors.red.shade600;
      case SwipeAction.toggleRead:
      default:
        return Colors.green.shade600;
    }
  }

  IconData get _icon {
    switch (action) {
      case SwipeAction.toggleStar:
        return Icons.star;
      case SwipeAction.delete:
        return Icons.delete_outline;
      case SwipeAction.toggleRead:
      default:
        return Icons.check_circle;
    }
  }

  String get _label {
    switch (action) {
      case SwipeAction.toggleStar:
        return article.isStarred ? 'Remove star' : 'Add star';
      case SwipeAction.delete:
        return 'Delete';
      case SwipeAction.toggleRead:
      default:
        return article.isRead ? 'Mark as unread' : 'Mark as read';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(16),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            _label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
