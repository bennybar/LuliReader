import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/blacklist_dao.dart';
import '../providers/app_provider.dart';
import '../services/account_service.dart';
import '../models/feed.dart';
import 'blocked_articles_screen.dart';

class BlacklistScreen extends ConsumerStatefulWidget {
  const BlacklistScreen({super.key});

  @override
  ConsumerState<BlacklistScreen> createState() => _BlacklistScreenState();
}

class _BlacklistScreenState extends ConsumerState<BlacklistScreen> {
  List<BlacklistEntry> _entries = [];
  List<Feed> _feeds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final accountService = ref.read(accountServiceProvider);
      final account = await accountService.getCurrentAccount();
      if (account == null) return;

      final blacklistDao = ref.read(blacklistDaoProvider);
      final feedDao = ref.read(feedDaoProvider);
      
      final entries = await blacklistDao.getAll(account.id!);
      final feeds = await feedDao.getAll(account.id!);
      
      if (mounted) {
        setState(() {
          _entries = entries;
          _feeds = feeds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading blacklist: $e')),
        );
      }
    }
  }

  Future<void> _addEntry() async {
    final accountService = ref.read(accountServiceProvider);
    final account = await accountService.getCurrentAccount();
    if (account == null) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddBlacklistDialog(feeds: _feeds),
    );

    if (result != null) {
      try {
        final blacklistDao = ref.read(blacklistDaoProvider);
        final entry = BlacklistEntry(
          pattern: result['pattern'] as String,
          feedId: result['feedId'] as String?,
          accountId: account.id!,
        );
        await blacklistDao.insert(entry);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Blacklist entry added')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding entry: $e')),
          );
        }
      }
    }
  }

  Future<void> _editEntry(BlacklistEntry entry) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddBlacklistDialog(
        feeds: _feeds,
        initialPattern: entry.pattern,
        initialFeedId: entry.feedId,
      ),
    );

    if (result != null) {
      try {
        final blacklistDao = ref.read(blacklistDaoProvider);
        final updated = entry.copyWith(
          pattern: result['pattern'] as String,
          feedId: result['feedId'] as String?,
        );
        await blacklistDao.update(updated);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Blacklist entry updated')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating entry: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteEntry(BlacklistEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Blacklist Entry?'),
        content: Text('Remove pattern "${entry.pattern}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final blacklistDao = ref.read(blacklistDaoProvider);
        await blacklistDao.delete(entry.id!);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Blacklist entry deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting entry: $e')),
          );
        }
      }
    }
  }

  String _getFeedName(String? feedId) {
    if (feedId == null) return 'All Feeds';
    final feed = _feeds.firstWhere((f) => f.id == feedId, orElse: () => Feed(
      id: feedId,
      name: 'Unknown',
      url: '',
      groupId: '',
      accountId: 0,
    ));
    return feed.name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blacklist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.block),
            tooltip: 'View Blocked Articles',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BlockedArticlesScreen(),
                ),
              );
              // Reload in case articles were released
              await _loadData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.block,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No blacklist entries',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add patterns to block articles by title',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          entry.feedId == null ? Icons.public : Icons.rss_feed,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(entry.pattern),
                        subtitle: Text(_getFeedName(entry.feedId)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _editEntry(entry),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              color: Theme.of(context).colorScheme.error,
                              onPressed: () => _deleteEntry(entry),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BlockedArticlesScreen(),
                ),
              );
              // Reload in case articles were released
              await _loadData();
            },
            icon: const Icon(Icons.block),
            label: const Text('View Blocked Articles'),
            heroTag: 'view_blocked',
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            onPressed: _addEntry,
            child: const Icon(Icons.add),
            heroTag: 'add_entry',
          ),
        ],
      ),
    );
  }
}

class _AddBlacklistDialog extends StatefulWidget {
  final List<Feed> feeds;
  final String? initialPattern;
  final String? initialFeedId;

  const _AddBlacklistDialog({
    required this.feeds,
    this.initialPattern,
    this.initialFeedId,
  });

  @override
  State<_AddBlacklistDialog> createState() => _AddBlacklistDialogState();
}

class _AddBlacklistDialogState extends State<_AddBlacklistDialog> {
  final _patternController = TextEditingController();
  String? _selectedFeedId;

  @override
  void initState() {
    super.initState();
    _patternController.text = widget.initialPattern ?? '';
    _selectedFeedId = widget.initialFeedId;
  }

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialPattern == null ? 'Add Blacklist Entry' : 'Edit Blacklist Entry'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _patternController,
              decoration: const InputDecoration(
                labelText: 'Pattern (title contains)',
                hintText: 'e.g., "spam", "advertisement"',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            const Text('Apply to:'),
            RadioListTile<String?>(
              title: const Text('All Feeds'),
              value: null,
              groupValue: _selectedFeedId,
              onChanged: (value) => setState(() => _selectedFeedId = value),
            ),
            ...widget.feeds.map((feed) => RadioListTile<String?>(
                  title: Text(feed.name),
                  value: feed.id,
                  groupValue: _selectedFeedId,
                  onChanged: (value) => setState(() => _selectedFeedId = value),
                )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_patternController.text.trim().isNotEmpty) {
              Navigator.of(context).pop({
                'pattern': _patternController.text.trim(),
                'feedId': _selectedFeedId,
              });
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

