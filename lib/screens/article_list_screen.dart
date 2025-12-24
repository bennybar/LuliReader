import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feed.dart';
import '../models/article.dart';
import '../models/article_sort.dart';
import '../database/article_dao.dart';
import '../providers/app_provider.dart';
import '../services/local_rss_service.dart';
import '../services/shared_preferences_service.dart';
import '../utils/reading_time.dart';
import 'article_reader_screen.dart';
import '../widgets/filter_drawer.dart';
import '../utils/rtl_helper.dart';

class ArticleListScreen extends ConsumerStatefulWidget {
  final Feed feed;

  const ArticleListScreen({super.key, required this.feed});

  @override
  ConsumerState<ArticleListScreen> createState() => _ArticleListScreenState();
}

class _ArticleListScreenState extends ConsumerState<ArticleListScreen> {
  List<Article> _articles = [];
  bool _isLoading = true;
  ArticleSortOption _sortOption = ArticleSortOption.dateDesc;
  bool _isBatchMode = false;
  Set<String> _selectedArticleIds = {};
  final SharedPreferencesService _prefs = SharedPreferencesService();
  final ScrollController _scrollController = ScrollController();
  bool _showPreviewText = true;
  bool _showHeroImage = true; // simple on/off

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
    _loadArticles();
    _loadArticleViewPrefs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload preferences when screen becomes visible (e.g., returning from settings)
    _loadArticleViewPrefs();
  }

  Future<void> _loadArticleViewPrefs() async {
    await _prefs.init();
    if (mounted) {
      final showPreviewTextValue = await _prefs.getBool('showPreviewText');
      // New: showHeroImage on/off. Backward compatibility: map old heroImagePosition.
      final legacyHeroPosition = await _prefs.getString('heroImagePosition');
      final showHeroImageValue =
          await _prefs.getBool('showHeroImage') ??
              (legacyHeroPosition == 'none' ? false : true);
      
      setState(() {
        _showPreviewText = showPreviewTextValue ?? true;
        _showHeroImage = showHeroImageValue;
      });
    }
  }

  Future<void> _loadSortPreference() async {
    await _prefs.init();
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account != null) {
      final sortIndex = await _prefs.getInt('sort_option_feed_${widget.feed.id}');
      if (sortIndex != null && sortIndex >= 0 && sortIndex < ArticleSortOption.values.length) {
        setState(() {
          _sortOption = ArticleSortOption.values[sortIndex];
        });
      }
    }
  }

  Future<void> _saveSortPreference() async {
    await _prefs.init();
    await _prefs.setInt('sort_option_feed_${widget.feed.id}', _sortOption.index);
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
      final articles = await articleDao.getArticlesWithSort(
        accountId: account.id!,
        sortOption: _sortOption,
        feedId: widget.feed.id,
        limit: 500,
      );
      setState(() {
        _articles = articles;
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

  Future<void> _syncFeed() async {
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account != null) {
        final rssService = ref.read(localRssServiceProvider);
        await rssService.sync(account.id!, feedId: widget.feed.id);
        _loadArticles();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error syncing feed: $e')),
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

  Future<void> _markAllAsRead() async {
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account != null) {
        final actions = ref.read(articleActionServiceProvider);
        final ids = _articles.where((a) => a.isUnread).map((a) => a.id).toList();
        if (ids.isNotEmpty) {
          await actions.batchMarkAsRead(ids, account.id!);
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
      drawer: FilterDrawer(onFiltersChanged: _loadArticles),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                widget.feed.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
            if (_selectedArticleIds.isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: 'Delete Selected',
                onPressed: _batchDelete,
              ),
              IconButton(
                icon: const Icon(Icons.star),
                tooltip: 'Star Selected',
                onPressed: _batchStar,
              ),
              IconButton(
                icon: const Icon(Icons.star_border),
                tooltip: 'Unstar Selected',
                onPressed: _batchUnstar,
              ),
              IconButton(
                icon: const Icon(Icons.done_all),
                tooltip: 'Mark Selected as Read',
                onPressed: _batchMarkAsRead,
              ),
              IconButton(
                icon: const Icon(Icons.mark_email_unread),
                tooltip: 'Mark Selected as Unread',
                onPressed: _batchMarkAsUnread,
              ),
            ],
          ] else ...[
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
                const PopupMenuItem(
                  value: 'sync',
                  child: Row(
                    children: [
                      Icon(Icons.sync, size: 20),
                      SizedBox(width: 8),
                      Text('Sync Feed'),
                    ],
                  ),
                ),
              ],
              onSelected: (value) async {
                if (value == 'mark_all_read') {
                  await _markAllAsRead();
                } else if (value == 'sync') {
                  await _syncFeed();
                }
              },
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _syncFeed();
              },
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
                                  'No articles yet',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Pull to refresh to sync',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _articles.length,
                      itemBuilder: (context, index) {
                        final article = _articles[index];
                        return _buildArticleCard(article, index);
                      },
                    ),
            ),
    );
  }

  Widget _buildArticleCard(Article article, int index) {
    final isSelected = _selectedArticleIds.contains(article.id);

    // Derive text direction from content and feed settings (consistent with FlowPage)
    final contentText = '${article.title} ${article.shortDescription} ${article.fullContent ?? ''}';
    final textDirection =
        RtlHelper.getTextDirectionFromContent(contentText, feedRtl: widget.feed.isRtl);
    final isRtl = textDirection == TextDirection.rtl;

    // Use state variables for article view preferences
    final showPreviewText = _showPreviewText;
    
    return Directionality(
      textDirection: textDirection,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isSelected
              ? BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: () {
            if (_isBatchMode) {
              _toggleArticleSelection(article.id);
            } else {
              final scrollPosition = _scrollController.hasClients
                  ? _scrollController.position.pixels
                  : 0.0;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ArticleReaderScreen(article: article),
                ),
              ).then((_) async {
                await _updateArticleAfterReading(article.id, scrollPosition, index);
              });
            }
          },
          onLongPress: () {
            if (!_isBatchMode) {
              setState(() {
                _isBatchMode = true;
                _selectedArticleIds.add(article.id);
              });
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              textDirection: TextDirection.ltr, // keep hero image visually on the right
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isBatchMode) ...[
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleArticleSelection(article.id),
                  ),
                  const SizedBox(width: 12),
                ],
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 80),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              article.title,
                              style: TextStyle(
                                fontWeight: article.isUnread ? FontWeight.bold : FontWeight.normal,
                              ),
                              textAlign: isRtl ? TextAlign.right : TextAlign.left,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
                      if (showPreviewText) ...[
                        const SizedBox(height: 6),
                        Text(
                          article.shortDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: isRtl ? TextAlign.right : TextAlign.left,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment:
                            isRtl ? AlignmentDirectional.centerEnd : Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                widget.feed.name,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.6),
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: isRtl ? TextAlign.right : TextAlign.left,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDate(article.date),
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            if (article.isStarred)
                              Padding(
                                padding: EdgeInsets.only(left: isRtl ? 4 : 8),
                                child: Icon(
                                  Icons.star,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
                if (!_isBatchMode &&
                    _showHeroImage &&
                    article.img != null &&
                    article.img!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: article.img!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.article),
                      placeholder: (_, __) => Container(
                        width: 80,
                        height: 80,
                        color: Colors.grey[300],
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Ensure both dates are in local timezone for accurate comparison
    final now = DateTime.now();
    final localDate = date.isUtc ? date.toLocal() : date;
    final difference = now.difference(localDate);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} minutes ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _updateArticleAfterReading(String articleId, double scrollPosition, int articleIndex) async {
    try {
      final articleDao = ref.read(articleDaoProvider);
      
      // Get updated article from database
      final updatedArticle = await articleDao.getById(articleId);
      if (updatedArticle == null) return;

      setState(() {
        // Update article in place
        final index = _articles.indexWhere((a) => a.id == articleId);
        if (index != -1) {
          _articles[index] = updatedArticle;
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

