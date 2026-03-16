import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feed.dart';
import '../models/article.dart';
import '../models/article_sort.dart';
import '../providers/app_provider.dart';
import '../services/shared_preferences_service.dart';
import 'article_reader_screen.dart';
import '../widgets/filter_drawer.dart';
import '../utils/rtl_helper.dart';
import '../theme/app_symbols.dart';

class ArticleListScreen extends ConsumerStatefulWidget {
  final Feed feed;

  const ArticleListScreen({super.key, required this.feed});

  @override
  ConsumerState<ArticleListScreen> createState() => _ArticleListScreenState();
}

class _ArticleListScreenState extends ConsumerState<ArticleListScreen> {
  static const Color _starredColor = Color(0xFFFFC107);
  List<Article> _articles = [];
  bool _isLoading = true;
  ArticleSortOption _sortOption = ArticleSortOption.dateDesc;
  bool _isBatchMode = false;
  Set<String> _selectedArticleIds = {};
  final SharedPreferencesService _prefs = SharedPreferencesService();
  final ScrollController _scrollController = ScrollController();
  bool _showPreviewText = true;
  bool _showHeroImage = true; // simple on/off
  double _listFontScale = 1.0;

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
        title: Row(
          children: [
            IconButton(
              icon: const Icon(AppSymbols.arrow_back),
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
              icon: const Icon(AppSymbols.close),
              tooltip: 'Cancel Selection',
              onPressed: () {
                setState(() {
                  _isBatchMode = false;
                  _selectedArticleIds.clear();
                });
              },
            ),
            PopupMenuButton<String>(
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.delete_outline),
                    title: Text('Delete Selected'),
                  ),
                ),
                PopupMenuItem(
                  value: 'star',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.star_outline),
                    title: Text('Star Selected'),
                  ),
                ),
                PopupMenuItem(
                  value: 'unstar',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.star_border),
                    title: Text('Unstar Selected'),
                  ),
                ),
                PopupMenuItem(
                  value: 'read',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.done_all),
                    title: Text('Mark Selected Read'),
                  ),
                ),
                PopupMenuItem(
                  value: 'unread',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.mark_email_unread),
                    title: Text('Mark Selected Unread'),
                  ),
                ),
              ],
              onSelected: (value) async {
                switch (value) {
                  case 'delete':
                    await _batchDelete();
                    break;
                  case 'star':
                    await _batchStar();
                    break;
                  case 'unstar':
                    await _batchUnstar();
                    break;
                  case 'read':
                    await _batchMarkAsRead();
                    break;
                  case 'unread':
                    await _batchMarkAsUnread();
                    break;
                }
              },
            ),
          ] else ...[
            IconButton(
              icon: const Icon(AppSymbols.sort),
              tooltip: 'Sort',
              onPressed: _showSortBottomSheet,
            ),
            PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'font_size',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.text_fields),
                    title: Text('List Font Size'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'select',
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
                const PopupMenuItem(
                  value: 'sync',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppSymbols.sync),
                    title: Text('Sync Feed'),
                  ),
                ),
              ],
              onSelected: (value) async {
                if (value == 'font_size') {
                  await _showListFontSizeDialog(context);
                } else if (value == 'select') {
                  setState(() {
                    _isBatchMode = true;
                  });
                } else if (value == 'mark_all_read') {
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
                                  AppSymbols.article,
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
                      cacheExtent: 1200,
                      itemCount: _articles.length,
                      itemBuilder: (context, index) {
                        final article = _articles[index];
                        return _buildArticleCard(article, index);
                      },
                    ),
            ),
      ),
    );
  }

  Widget _buildArticleCard(Article article, int index) {
    final isSelected = _selectedArticleIds.contains(article.id);
    final double heroSize = (76 * _listFontScale).clamp(68.0, 88.0).toDouble();
    final double placeholderIconSize =
        (40 * _listFontScale).clamp(28.0, 80.0).toDouble();

    // Derive text direction from content and feed settings (consistent with FlowPage)
    final contentText = '${article.title} ${article.shortDescription}';
    final textDirection =
        RtlHelper.getTextDirectionFromContent(contentText, feedRtl: widget.feed.isRtl);
    final isRtl = textDirection == TextDirection.rtl;

    // Use state variables for article view preferences
    final showPreviewText = _showPreviewText;
    final hasThumbnail = !_isBatchMode &&
        _showHeroImage &&
        article.img != null &&
        article.img!.isNotEmpty;
    
    return Directionality(
      textDirection: textDirection,
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
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: hasThumbnail ? 72 : 0),
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
                                  fontWeight:
                                      article.isUnread ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                  height: 1.22,
                                ),
                                textAlign: isRtl ? TextAlign.right : TextAlign.left,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (article.isStarred)
                              Padding(
                                padding:
                                    EdgeInsets.only(left: isRtl ? 0 : 8, right: isRtl ? 8 : 0),
                                child: Icon(
                                  AppSymbols.star,
                                  size: 16,
                                  color: _starredColor,
                                ),
                              ),
                          ],
                        ),
                        if (showPreviewText) ...[
                          const SizedBox(height: 3),
                          Text(
                            article.shortDescription,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.7),
                                ),
                            textAlign: isRtl ? TextAlign.right : TextAlign.left,
                          ),
                        ],
                        const SizedBox(height: 6),
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
                                            .withValues(alpha: 0.56),
                                        fontSize: 10.5,
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
                                    AppSymbols.access_time,
                                    size: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.56),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    _formatDate(article.date),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontSize: 10.5,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.56),
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: article.img!,
                      width: heroSize,
                      height: heroSize,
                      fit: BoxFit.cover,
                      memCacheWidth: _targetImageCacheWidth(heroSize),
                      maxWidthDiskCache: _targetImageCacheWidth(heroSize),
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      errorWidget: (_, __, ___) => _buildImagePlaceholder(
                        heroSize,
                        placeholderIconSize,
                      ),
                      placeholder: (_, __) => _buildImagePlaceholder(
                        heroSize,
                        placeholderIconSize,
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
    // Use local time consistently to avoid double-offset issues
    final now = DateTime.now();
    final articleLocal = date.isUtc ? date.toLocal() : date;
    final difference = now.difference(articleLocal);

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

  Widget _buildImagePlaceholder(double heroSize, double placeholderIconSize) {
    return SizedBox(
      width: heroSize,
      height: heroSize,
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

