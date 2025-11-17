import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/article.dart';
import '../models/swipe_action.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import 'feeds_screen.dart';
import 'starred_screen.dart';
import 'settings_screen.dart';
import 'article_detail_screen.dart';
import '../widgets/platform_bottom_nav.dart';
import '../widgets/liquid_glass_toggle.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const _HomeTab(),
    const FeedsScreen(),
    const StarredScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: PlatformBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
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
  bool _showUnreadOnly = true; // Default to unread only
  bool _isSyncing = false;
  bool _hasSyncConfig = false;
  SwipeAction _leftSwipeAction = SwipeAction.toggleRead;
  SwipeAction _rightSwipeAction = SwipeAction.toggleStar;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadArticles();
    await _loadSwipePreferences();
    await _syncArticlesFromServer(initial: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh articles when returning to this tab
    _loadArticles();
    _loadSwipePreferences();
  }

  Future<void> _loadArticles() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // First, check total articles in DB
      final allArticles = await _db.getArticles(limit: 1000);
      print('Total articles in DB: ${allArticles.length}');
      final totalUnread = allArticles.where((a) => !a.isRead).length;
      final totalRead = allArticles.where((a) => a.isRead).length;
      print('Total unread: $totalUnread, Total read: $totalRead');
      
      // Now get filtered articles
      final articles = await _db.getArticles(
        limit: 100,
        isRead: _showUnreadOnly ? false : null,
      );
      final unreadCount = articles.where((a) => !a.isRead).length;
      print('Loaded ${articles.length} articles from database (filter: ${_showUnreadOnly ? "unread only" : "all"}, actually unread in result: $unreadCount)');
      
      // Debug: print first few article read statuses
      if (articles.isNotEmpty) {
        print('First 5 articles read status:');
        for (var i = 0; i < (articles.length > 5 ? 5 : articles.length); i++) {
          print('  ${articles[i].title}: isRead=${articles[i].isRead}');
        }
      } else if (allArticles.isNotEmpty) {
        print('WARNING: Filter returned 0 articles but DB has ${allArticles.length} total articles!');
        print('Sample article read statuses:');
        for (var i = 0; i < (allArticles.length > 5 ? 5 : allArticles.length); i++) {
          print('  ${allArticles[i].title}: isRead=${allArticles[i].isRead}');
        }
      }
      
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

  String _stripHtml(String? html) {
    if (html == null) return '';
    // Remove HTML tags and decode entities
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isRTLText(String text) {
    final rtlRegex = RegExp(r'[\u0590-\u08FF]');
    return rtlRegex.hasMatch(text);
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, yyyy • HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(_showUnreadOnly ? 'Unread Articles' : 'All Articles'),
        actions: [
          // Liquid glass toggle for iOS, regular for Android
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: LiquidGlassToggle(
              value: _showUnreadOnly,
              onChanged: (value) {
                setState(() {
                  _showUnreadOnly = value;
                });
                _loadArticles();
              },
              label: _showUnreadOnly ? 'Unread' : 'All',
            ),
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: _isSyncing ? null : () => _syncArticlesFromServer(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _syncArticlesFromServer(),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _articles.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No articles found\nPull down to refresh')),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _articles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      return _buildSwipeableCard(article);
                    },
                  ),
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
      confirmDismiss: (direction) async {
        await _handleSwipeAction(article, direction);
        return false;
      },
      child: _ArticleCard(
        article: article,
        summary: _stripHtml(article.summary ?? article.content ?? ''),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ArticleDetailScreen(article: article),
            ),
          ).then((_) => _loadArticles());
        },
        isRTLText: _isRTLText,
        formatDate: _formatDate,
      ),
    );
  }

  Future<void> _handleSwipeAction(Article article, DismissDirection direction) async {
    final hasConfig = await _ensureSyncConfigured();
    if (!hasConfig) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login again to sync article actions.')),
      );
      return;
    }

    final isStartToEnd = direction == DismissDirection.startToEnd;
    final action = isStartToEnd ? _leftSwipeAction : _rightSwipeAction;
    switch (action) {
      case SwipeAction.toggleRead:
        final newValue = !article.isRead;
        await _syncService.markArticleAsRead(article.id, newValue);
        if (!mounted) break;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newValue ? 'Marked as read' : 'Marked as unread')),
        );
        break;
      case SwipeAction.toggleStar:
        final newValue = !article.isStarred;
        await _syncService.markArticleAsStarred(article.id, newValue);
        if (!mounted) break;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newValue ? 'Starred article' : 'Unstarred article')),
        );
        break;
    }
    await _loadArticles();
  }
}

class _ArticleCard extends StatelessWidget {
  final Article article;
  final String summary;
  final VoidCallback onTap;
  final bool Function(String text) isRTLText;
  final String Function(DateTime date) formatDate;

  const _ArticleCard({
    required this.article,
    required this.summary,
    required this.onTap,
    required this.isRTLText,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final isTitleRTL = isRTLText(article.title);
    final isSummaryRTL = isRTLText(summary);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (article.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: article.imageUrl!,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            const SizedBox(width: 90, height: 90, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                        errorWidget: (context, url, error) =>
                            const SizedBox(width: 90, height: 90, child: Icon(Icons.image_not_supported)),
                      ),
                    )
                  else
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.rss_feed, size: 32),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                article.title,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                textAlign: isTitleRTL ? TextAlign.right : TextAlign.left,
                                textDirection: isTitleRTL ? ui.TextDirection.rtl : ui.TextDirection.ltr,
                              ),
                            ),
                            if (!article.isRead)
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          summary.isEmpty ? 'No summary available.' : summary,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                          textAlign: isSummaryRTL ? TextAlign.right : TextAlign.left,
                          textDirection: isSummaryRTL ? ui.TextDirection.rtl : ui.TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    formatDate(article.publishedDate),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
      case SwipeAction.toggleRead:
      default:
        return Colors.green.shade600;
    }
  }

  IconData get _icon {
    switch (action) {
      case SwipeAction.toggleStar:
        return Icons.star;
      case SwipeAction.toggleRead:
      default:
        return Icons.check_circle;
    }
  }

  String get _label {
    switch (action) {
      case SwipeAction.toggleStar:
        return article.isStarred ? 'Remove star' : 'Add star';
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
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

