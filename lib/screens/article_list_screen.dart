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

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
    _loadArticles();
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Feed synced successfully')),
          );
        }
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
      appBar: AppBar(
        title: Text(widget.feed.name),
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
                )
              : RefreshIndicator(
                  onRefresh: _loadArticles,
                  child: ListView.builder(
                    itemCount: _articles.length,
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      return _buildArticleCard(article);
                    },
                  ),
                ),
    );
  }

  Widget _buildArticleCard(Article article) {
    final isSelected = _selectedArticleIds.contains(article.id);
    final readingTime = ReadingTime.calculateAndFormat(
      article.fullContent ?? article.rawDescription,
    );
    
    return Card(
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
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: _isBatchMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleArticleSelection(article.id),
              )
            : (article.img != null
                ? ClipRRect(
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
                  )
                : const Icon(Icons.article, size: 40)),
        title: Text(
          article.title,
          style: TextStyle(
            fontWeight: article.isUnread ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              article.shortDescription,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (readingTime.isNotEmpty) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        readingTime,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
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
                    ),
                  ],
                ),
                if (article.isStarred)
                  Icon(
                    Icons.star,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ],
        ),
        onTap: () {
          if (_isBatchMode) {
            _toggleArticleSelection(article.id);
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ArticleReaderScreen(article: article),
              ),
            ).then((_) => _loadArticles());
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
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

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
}

