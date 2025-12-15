import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feed.dart';
import '../providers/app_provider.dart';
import '../database/feed_dao.dart';
import '../database/article_dao.dart';

class FeedOptionsScreen extends ConsumerStatefulWidget {
  final Feed feed;

  const FeedOptionsScreen({super.key, required this.feed});

  @override
  ConsumerState<FeedOptionsScreen> createState() => _FeedOptionsScreenState();
}

class _FeedOptionsScreenState extends ConsumerState<FeedOptionsScreen> {
  bool _isLoading = false;
  late bool _isFullContent;
  late bool _isBrowser;
  late bool _isNotification;
  late bool? _isRtl;
  int? _articleCount;
  DateTime? _latestArticleDate;

  @override
  void initState() {
    super.initState();
    _isFullContent = widget.feed.isFullContent;
    _isBrowser = widget.feed.isBrowser;
    _isNotification = widget.feed.isNotification;
    _isRtl = widget.feed.isRtl;
    _loadFeedStats();
  }

  Future<void> _loadFeedStats() async {
    try {
      final articleDao = ref.read(articleDaoProvider);
      final count = await articleDao.countByFeedId(widget.feed.id);
      final latest = await articleDao.latestByFeedId(widget.feed.id);
      if (mounted) {
        setState(() {
          _articleCount = count;
          _latestArticleDate = latest?.date;
        });
      }
    } catch (e) {
      // Error loading feed stats
    }
  }

  Future<void> _deleteFeed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Feed'),
        content: Text('Are you sure you want to delete "${widget.feed.name}"? This will also delete all articles from this feed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final feedDao = ref.read(feedDaoProvider);
      await feedDao.delete(widget.feed.id);

      if (!mounted) return;
      Navigator.of(context).pop(true); // Return true to indicate deletion
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting feed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearFeed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Feed'),
        content: Text('Are you sure you want to clear all articles from "${widget.feed.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final articleDao = ref.read(articleDaoProvider);
      final articles = await articleDao.getByFeedId(widget.feed.id, limit: 10000);
      
      for (final article in articles) {
        await articleDao.delete(article.id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feed cleared successfully')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error clearing feed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _renameFeed() async {
    final controller = TextEditingController(text: widget.feed.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Feed'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Feed Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == widget.feed.name) return;

    setState(() => _isLoading = true);
    try {
      final feedDao = ref.read(feedDaoProvider);
      await feedDao.update(widget.feed.copyWith(name: newName));

      if (!mounted) return;
      Navigator.of(context).pop(true); // Return true to indicate update
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error renaming feed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateFeedSettings() async {
    setState(() => _isLoading = true);
    try {
      final feedDao = ref.read(feedDaoProvider);
      final wasFullContentEnabled = widget.feed.isFullContent;
      final isNowEnabled = _isFullContent;
      
      await feedDao.update(widget.feed.copyWith(
        isFullContent: _isFullContent,
        isBrowser: _isBrowser,
        isNotification: _isNotification,
        isRtl: _isRtl,
      ));

      // If full content was just enabled, start downloading for existing articles in background
      if (!wasFullContentEnabled && isNowEnabled) {
        _startBackgroundFullContentDownload();
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating feed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startBackgroundFullContentDownload() {
    // Start downloading full content for existing articles in background
    // This runs asynchronously and doesn't block the UI
    Future.microtask(() async {
      try {
        final articleDao = ref.read(articleDaoProvider);
        final localRssService = ref.read(localRssServiceProvider);
        
        // Get articles without full content (limit to avoid too many at once)
        final articles = await articleDao.getByFeedId(widget.feed.id, limit: 100);
        final articlesNeedingContent = articles.where((a) => 
          a.fullContent == null || a.fullContent!.isEmpty
        ).toList();

        // Download in batches to avoid overwhelming the system
        const batchSize = 5;
        for (int i = 0; i < articlesNeedingContent.length; i += batchSize) {
          final batch = articlesNeedingContent.skip(i).take(batchSize).toList();
          
          // Download all in batch concurrently
          await Future.wait(
            batch.map((article) => localRssService.downloadFullContent(article).catchError((e) {
              // Error downloading full content for article
              return null;
            })),
            eagerError: false,
          );
          
          // Small delay between batches
          if (i + batchSize < articlesNeedingContent.length) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      } catch (e) {
        // Error in background full content download
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.feed.name),
        actions: [
          if (_isFullContent != widget.feed.isFullContent ||
              _isBrowser != widget.feed.isBrowser ||
              _isNotification != widget.feed.isNotification ||
              _isRtl != widget.feed.isRtl)
            TextButton(
              onPressed: _updateFeedSettings,
              child: const Text('Save'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_articleCount != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.health_and_safety),
                      title: const Text('Feed health'),
                      subtitle: Text(
                        'Articles cached: $_articleCount\nLatest: ${_latestArticleDate != null ? _latestArticleDate!.toLocal() : 'N/A'}',
                      ),
                    ),
                  ),
                if (_articleCount != null) const SizedBox(height: 12),
                // Reading Page Settings
                Text(
                  'Reading Page',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                // Parse Full Content Toggle
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.article_outlined),
                    title: const Text('Parse Full Content'),
                    subtitle: const Text(
                      'Automatically download and parse full article content in the background',
                    ),
                    value: _isFullContent,
                    onChanged: (value) {
                      setState(() {
                        _isFullContent = value;
                        if (value) {
                          _isBrowser = false; // Can't have both enabled
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 8),
                // Open in Browser Toggle
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.open_in_browser),
                    title: const Text('Open in Browser'),
                    subtitle: const Text('Open articles in external browser instead of reader'),
                    value: _isBrowser,
                    onChanged: (value) {
                      setState(() {
                        _isBrowser = value;
                        if (value) {
                          _isFullContent = false; // Can't have both enabled
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 8),
                // Force RTL Toggle
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.format_textdirection_r_to_l),
                    title: const Text('Force Right-to-Left'),
                    subtitle: const Text('Force RTL layout and right alignment for this feed'),
                    value: _isRtl == true,
                    onChanged: (value) {
                      setState(() {
                        _isRtl = value ? true : null; // true = force RTL, null = auto-detect
                      });
                    },
                  ),
                ),
                const SizedBox(height: 24),
                // Preset Settings
                Text(
                  'Preset',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.notifications_outlined),
                    title: const Text('Allow Notifications'),
                    subtitle: const Text('Receive notifications for new articles'),
                    value: _isNotification,
                    onChanged: (value) {
                      setState(() {
                        _isNotification = value;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 24),
                // Feed Management
                Text(
                  'Feed Management',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Rename'),
                    onTap: _renameFeed,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.clear_all, color: Colors.orange),
                    title: const Text('Clear Articles'),
                    subtitle: const Text('Remove all articles from this feed'),
                    onTap: _clearFeed,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text('Delete Feed'),
                    subtitle: const Text('Permanently delete this feed and all articles'),
                    onTap: _deleteFeed,
                  ),
                ),
              ],
            ),
    );
  }
}

