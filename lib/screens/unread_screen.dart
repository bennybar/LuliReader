import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../models/article.dart';
import '../models/feed.dart';
import '../models/swipe_action.dart';
import '../notifiers/preview_lines_notifier.dart';
import '../notifiers/starred_refresh_notifier.dart';
import '../notifiers/unread_refresh_notifier.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../notifiers/swipe_prefs_notifier.dart';
import '../notifiers/last_sync_notifier.dart';
import '../utils/article_text_utils.dart';
import '../widgets/article_card.dart';
import '../widgets/platform_app_bar.dart';
import '../utils/platform_utils.dart';
import 'article_detail_screen.dart';

class UnreadScreen extends StatefulWidget {
  const UnreadScreen({super.key});

  @override
  State<UnreadScreen> createState() => _UnreadScreenState();
}

class _UnreadScreenState extends State<UnreadScreen> {
  final DatabaseService _db = DatabaseService();
  final SyncService _syncService = SyncService();
  final StorageService _storageService = StorageService();
  final UnreadRefreshNotifier _unreadNotifier = UnreadRefreshNotifier.instance;
  List<Article> _articles = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _hasSyncConfig = false;
  Map<String, String> _feedTitles = {};
  SwipeAction _leftSwipeAction = SwipeAction.toggleRead;
  SwipeAction _rightSwipeAction = SwipeAction.toggleStar;
  final PreviewLinesNotifier _previewLinesNotifier = PreviewLinesNotifier.instance;
  int _previewLines = 3;
  DateTime? _lastSync;
  bool _swipeAllowsDelete = false;
  final SwipePrefsNotifier _swipePrefsNotifier = SwipePrefsNotifier.instance;
  final LastSyncNotifier _lastSyncNotifier = LastSyncNotifier.instance;

  @override
  void initState() {
    super.initState();
    _previewLines = _previewLinesNotifier.lines;
    _previewLinesNotifier.addListener(_handlePreviewLinesChanged);
    _unreadNotifier.addListener(_handleUnreadRefresh);
    _swipePrefsNotifier.addListener(_handleSwipePrefsChanged);
    _lastSyncNotifier.addListener(_handleLastSyncChanged);
    _initialize();
  }

  @override
  void dispose() {
    _previewLinesNotifier.removeListener(_handlePreviewLinesChanged);
    _unreadNotifier.removeListener(_handleUnreadRefresh);
    _swipePrefsNotifier.removeListener(_handleSwipePrefsChanged);
    _lastSyncNotifier.removeListener(_handleLastSyncChanged);
    super.dispose();
  }

  void _handleUnreadRefresh() {
    _loadArticles();
  }

  Future<void> _initialize() async {
    await _loadFeedTitles();
    await _loadSwipePreferences();
    await _loadPreviewLines();
    await _loadLastSyncTime();
    await _loadSwipeDeleteSetting();
    await _loadArticles();
  }

  Future<void> _loadPreviewLines() async {
    final lines = await _storageService.getPreviewLines();
    if (!mounted) return;
    setState(() {
      _previewLines = lines;
    });
    _previewLinesNotifier.setLines(lines);
  }

  void _handlePreviewLinesChanged() {
    final lines = _previewLinesNotifier.lines;
    if (!mounted || _previewLines == lines) return;
    setState(() => _previewLines = lines);
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
    _loadArticles();
    _loadSwipePreferences();
  }

  Future<void> _loadArticles() async {
    if (!mounted) return;

    // Only show the big centered loader when there are no articles yet.
    final hadArticles = _articles.isNotEmpty;
    if (!hadArticles) {
    setState(() => _isLoading = true);
    }
    try {
      // Always show unread only
      final articles = await _db.getArticles(
        limit: 100,
        isRead: false,
      );
      if (mounted) {
        setState(() {
          _articles = articles;
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
          const SnackBar(content: Text('Unable to sync: missing account configuration')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }

    await _loadArticles();
  }

  Future<bool> _handleSwipeAction(Article article, DismissDirection direction) async {
    final hasConfig = await _ensureSyncConfigured();
    if (!hasConfig) {
      return false;
    }

    final action = direction == DismissDirection.startToEnd ? _leftSwipeAction : _rightSwipeAction;

    // Destructive delete via swipe when action is set to Delete
    if (action == SwipeAction.delete) {
      final deleted = await _syncService.deleteArticle(article.id);
      if (deleted) {
        await _loadArticles();
      }
      // Do not dismiss the card; list reload will reflect removal
      return false;
    }
    
    switch (action) {
      case SwipeAction.toggleRead:
        await _syncService.markArticleAsRead(article.id, !article.isRead);
        // _loadArticles() will be called automatically via UnreadRefreshNotifier
        break;
      case SwipeAction.toggleStar:
        await _syncService.markArticleAsStarred(article.id, !article.isStarred);
        // Starring doesn't affect unread status, but refresh anyway
        await _loadArticles();
        break;
      case SwipeAction.delete:
        // Handled in the delete branch above.
        break;
    }
    return false; // Don't dismiss
  }

  @override
  Widget build(BuildContext context) {
    final isIOSPlatform =
        Theme.of(context).platform == TargetPlatform.iOS;
    return Scaffold(
      appBar: PlatformAppBar(
        titleWidget: _buildTitleWidget(),
        actions: [
          _buildSyncAction(context),
        ],
      ),
      body: Column(
        children: [
          // Slim, non-blocking progress bar for sync
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _isSyncing ? 2 : 0,
            child: _isSyncing
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _syncArticlesFromServer(),
              child: _isLoading && _articles.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _articles.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                'No unread articles\nPull down to refresh',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: isIOSPlatform
                              ? const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                )
                              : const ClampingScrollPhysics(),
                          cacheExtent: 800,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                          itemCount: _articles.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
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
          ).then((_) => _loadArticles());
        },
      ),
    );
  }

  Widget _buildSyncAction(BuildContext context) {
    final icon = _isSyncing
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.sync, size: 18);

    if (!isIOS) {
      return IconButton(
        icon: icon,
        onPressed: _isSyncing ? null : () => _syncArticlesFromServer(),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: LiquidGlassLayer(
        settings: const LiquidGlassSettings(
          thickness: 16,
          blur: 18,
          glassColor: Color(0x33FFFFFF),
        ),
        child: LiquidGlass(
          shape: LiquidRoundedSuperellipse(borderRadius: 18),
          glassContainsChild: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _isSyncing ? null : () => _syncArticlesFromServer(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  if (!_isSyncing) ...[
                    const SizedBox(width: 6),
                    const Text(
                      'Refresh',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleWidget() {
    final theme = Theme.of(context);

    final children = <Widget>[
      Text(
        'Unread',
        style: theme.textTheme.titleLarge,
      ),
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

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label;

    switch (action) {
      case SwipeAction.toggleRead:
        color = article.isRead ? Colors.orange : Colors.blue;
        icon = article.isRead ? Icons.mark_email_unread : Icons.mark_email_read;
        label = article.isRead ? 'Unread' : 'Read';
        break;
      case SwipeAction.toggleStar:
        color = article.isStarred ? Colors.grey : Colors.amber;
        icon = article.isStarred ? Icons.star_border : Icons.star;
        label = article.isStarred ? 'Unstar' : 'Star';
        break;
      case SwipeAction.delete:
        color = Colors.red.shade600;
        icon = Icons.delete_outline;
        label = 'Delete';
        break;
    }

    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: color),
      child: Row(
        mainAxisAlignment: alignment == Alignment.centerLeft
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

