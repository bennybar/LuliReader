import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/blacklist_dao.dart';
import '../providers/app_provider.dart';
import '../services/account_service.dart';

class BlockedArticlesScreen extends ConsumerStatefulWidget {
  const BlockedArticlesScreen({super.key});

  @override
  ConsumerState<BlockedArticlesScreen> createState() => _BlockedArticlesScreenState();
}

class _BlockedArticlesScreenState extends ConsumerState<BlockedArticlesScreen> {
  List<Map<String, dynamic>> _blockedArticles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedArticles();
  }

  Future<void> _loadBlockedArticles() async {
    setState(() => _isLoading = true);
    try {
      final accountService = ref.read(accountServiceProvider);
      final account = await accountService.getCurrentAccount();
      if (account == null) return;

      final blacklistDao = ref.read(blacklistDaoProvider);
      final blocked = await blacklistDao.getBlockedArticles(account.id!);
      
      if (mounted) {
        setState(() {
          _blockedArticles = blocked;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading blocked articles: $e')),
        );
      }
    }
  }

  Future<void> _releaseArticle(Map<String, dynamic> article) async {
    try {
      final accountService = ref.read(accountServiceProvider);
      final account = await accountService.getCurrentAccount();
      if (account == null) return;

      final blacklistDao = ref.read(blacklistDaoProvider);
      await blacklistDao.addException(article['id'] as String, account.id!);
      
      await _loadBlockedArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Article "${article['title']}" released')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error releasing article: $e')),
        );
      }
    }
  }

  Future<void> _releaseAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Release All Articles?'),
        content: Text('Release all ${_blockedArticles.length} blocked articles?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Release All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final accountService = ref.read(accountServiceProvider);
        final account = await accountService.getCurrentAccount();
        if (account == null) return;

        final blacklistDao = ref.read(blacklistDaoProvider);
        for (final article in _blockedArticles) {
          await blacklistDao.addException(article['id'] as String, account.id!);
        }
        
        await _loadBlockedArticles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All articles released')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error releasing articles: $e')),
          );
        }
      }
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Articles'),
        actions: [
          if (_blockedArticles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.lock_open),
              tooltip: 'Release All',
              onPressed: _releaseAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blockedArticles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No blocked articles',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Articles matching blacklist patterns will appear here',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadBlockedArticles,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _blockedArticles.length,
                    itemBuilder: (context, index) {
                      final article = _blockedArticles[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Text(
                            article['title'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Feed: ${article['feedName'] as String}'),
                              Text('Pattern: ${article['blacklistPattern'] as String}'),
                              Text(_formatDate(article['date'] as String)),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.lock_open),
                            color: Theme.of(context).colorScheme.primary,
                            tooltip: 'Release',
                            onPressed: () => _releaseArticle(article),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

