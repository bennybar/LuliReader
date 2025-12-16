import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../database/group_dao.dart';
import '../models/group.dart';
import '../models/feed.dart';
import '../utils/rtl_helper.dart';
import 'article_list_screen.dart';
import 'add_feed_screen.dart';
import 'feed_options_screen.dart';
import 'settings_screen.dart';

class FeedsPage extends ConsumerStatefulWidget {
  final VoidCallback? onSync;
  
  const FeedsPage({super.key, this.onSync});

  @override
  ConsumerState<FeedsPage> createState() => FeedsPageState();
}

class FeedsPageState extends ConsumerState<FeedsPage> {
  int _refreshKey = 0;
  bool _accountListenerSet = false;

  void refresh() {
    setState(() {
      _refreshKey++;
    });
  }

  void _refresh() {
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_accountListenerSet) {
      _accountListenerSet = true;
      ref.listen(currentAccountProvider, (_, __) {
        _refresh();
      });
    }
    final accountAsync = ref.watch(currentAccountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feeds'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync All Feeds',
            onPressed: widget.onSync ?? () async {
              final account = await ref.read(accountServiceProvider).getCurrentAccount();
              if (account != null) {
                try {
                  final rssService = ref.read(localRssServiceProvider);
                  await rssService.sync(account.id!);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sync completed')),
                    );
                    _refresh();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sync error: $e')),
                    );
                  }
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'New Folder',
            onPressed: () => _createNewFolder(context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Feed',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddFeedScreen()),
              ).then((_) => _refresh());
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _refresh();
            },
          ),
        ],
      ),
      body: Directionality(
        textDirection: RtlHelper.getTextDirection(Localizations.localeOf(context)),
        child: accountAsync.when(
          data: (account) {
            if (account == null) {
              return const Center(child: Text('No account found'));
            }
            return _buildFeedsList(account.id!);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('Error: $error')),
        ),
      ),
    );
  }

  Widget _buildFeedsList(int accountId) {
    return FutureBuilder<List<GroupWithFeed>>(
      key: ValueKey(_refreshKey),
      future: _loadGroupsWithFeeds(accountId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final groups = snapshot.data ?? [];

        if (groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.rss_feed,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No feeds yet',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the + button to add a feed',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final groupWithFeed = groups[index];
            return _buildGroupCard(groupWithFeed);
          },
        );
      },
    );
  }

  Widget _buildGroupCard(GroupWithFeed groupWithFeed) {
    final group = groupWithFeed.group;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: Icon(
          Icons.folder,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Row(
          children: [
            Expanded(child: Text(group.name)),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete folder',
              onPressed: () => _confirmDeleteGroup(group),
            ),
          ],
        ),
        subtitle: Text('${groupWithFeed.feeds.length} feeds'),
        children: groupWithFeed.feeds.map((feed) {
          final feedObj = feed as Feed;
          return ListTile(
            leading: feedObj.icon != null && feedObj.icon!.isNotEmpty
                ? CircleAvatar(
                    backgroundImage: NetworkImage(feedObj.icon!),
                    radius: 16,
                    onBackgroundImageError: (_, __) {},
                    child: feedObj.icon == null || feedObj.icon!.isEmpty
                        ? Text(feedObj.name[0].toUpperCase())
                        : null,
                  )
                : CircleAvatar(
                    child: Text(feedObj.name[0].toUpperCase()),
                    radius: 16,
                  ),
            title: Text(
              feedObj.name,
              textAlign: Directionality.of(context) == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ArticleListScreen(feed: feedObj),
                ),
              );
            },
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FeedOptionsScreen(feed: feedObj),
                  ),
                );
                if (result == true && mounted) {
                  _refresh();
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<List<GroupWithFeed>> _loadGroupsWithFeeds(int accountId) async {
    final groupDao = ref.read(groupDaoProvider);
    return await groupDao.getAllWithFeeds(accountId);
  }

  Future<void> _createNewFolder(BuildContext context) async {
    final nameController = TextEditingController();
    String? folderName;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Folder Name',
            hintText: 'Enter folder name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) {
            folderName = value;
            Navigator.of(context).pop(true);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              folderName = nameController.text;
              Navigator.of(context).pop(true);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    // Dispose controller after dialog is fully closed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
    });

    if (confirmed != true) {
      return;
    }

    // Get the folder name before controller might be disposed
    final trimmedName = folderName?.trim() ?? '';
    if (trimmedName.isEmpty) {
      return;
    }

    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No account found')),
          );
        }
        return;
      }

      final groupDao = ref.read(groupDaoProvider);
      final groupId = '${account.id}\$${DateTime.now().millisecondsSinceEpoch}';
      final group = Group(
        id: groupId,
        name: trimmedName,
        accountId: account.id!,
      );
      
      await groupDao.insert(group);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created folder "${group.name}"')),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating folder: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteGroup(Group group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text(
          'This will remove the folder "${group.name}" and all feeds inside it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final groupDao = ref.read(groupDaoProvider);
        await groupDao.delete(group.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted folder "${group.name}"')),
          );
          _refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting folder: $e')),
          );
        }
      }
    }
  }
}

