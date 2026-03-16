import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../models/group.dart';
import '../models/feed.dart';
import '../utils/rtl_helper.dart';
import 'add_freshrss_account_screen.dart';
import 'add_miniflux_account_screen.dart';
import 'article_list_screen.dart';
import 'add_feed_screen.dart';
import 'feed_options_screen.dart';
import 'settings_screen.dart';
import '../widgets/filter_drawer.dart';
import '../widgets/app_count_badge.dart';
import '../theme/app_symbols.dart';

class FeedsPage extends ConsumerStatefulWidget {
  final Future<void> Function()? onSync;
  
  const FeedsPage({super.key, this.onSync});

  @override
  ConsumerState<FeedsPage> createState() => FeedsPageState();
}

class FeedsPageState extends ConsumerState<FeedsPage> {
  int _refreshKey = 0;
  bool _accountListenerSet = false;
  bool _isSyncing = false;

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
      drawer: FilterDrawer(onFiltersChanged: _refresh),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppSymbols.rss_feed, size: 20),
            const SizedBox(width: 8),
            Text(
              'Feeds',
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
          ],
        ),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(AppSymbols.tune),
              tooltip: 'Filters',
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppSymbols.sync),
            tooltip: 'Sync All Feeds',
            onPressed: _isSyncing
                ? null
                : () async {
                    if (_isSyncing) return;
                    setState(() => _isSyncing = true);
                    try {
                      if (widget.onSync != null) {
                        await widget.onSync!();
                        if (mounted) {
                          _refresh();
                          ref.invalidate(currentAccountProvider);
                        }
                      } else {
                        final account = await ref.read(accountServiceProvider).getCurrentAccount();
                        if (account != null) {
                          final syncCoordinator = ref.read(syncCoordinatorProvider);
                          await syncCoordinator.syncAccount(account.id!);
                          if (mounted) {
                            _refresh();
                            ref.invalidate(currentAccountProvider); // Notify listeners to reload articles
                          }
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Sync error: $e')),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _isSyncing = false);
                      }
                    }
                  },
          ),
          IconButton(
            icon: const Icon(AppSymbols.add),
            tooltip: 'Add Feed',
            onPressed: _openAddFeed,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) async {
              switch (value) {
                case 'new_folder':
                  await _createNewFolder(context);
                  break;
                case 'cloud_account':
                  await _showCloudAccountPicker();
                  break;
                case 'settings':
                  await _openSettings();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'new_folder',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(AppSymbols.create_new_folder),
                  title: Text('New Folder'),
                ),
              ),
              PopupMenuItem(
                value: 'cloud_account',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(AppSymbols.cloud_outlined),
                  title: Text('Add Cloud Account'),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(AppSymbols.settings_outlined),
                  title: Text('Settings'),
                ),
              ),
            ],
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

  Future<void> _showCloudAccountPicker() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppSymbols.cloud),
              title: const Text('FreshRSS'),
              subtitle: const Text('Google Reader compatible'),
              onTap: () => Navigator.pop(context, 'freshrss'),
            ),
            ListTile(
              leading: const Icon(AppSymbols.cloud),
              title: const Text('Miniflux'),
              subtitle: const Text('Google Reader compatible'),
              onTap: () => Navigator.pop(context, 'miniflux'),
            ),
          ],
        ),
      ),
    );

    if (selection == 'freshrss') {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const AddFreshRssAccountScreen(),
        ),
      );
      if (result == true) {
        _refresh();
      }
    } else if (selection == 'miniflux') {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const AddMinifluxAccountScreen(),
        ),
      );
      if (result == true) {
        _refresh();
      }
    }
  }

  Widget _buildFeedsList(int accountId) {
    return FutureBuilder<_FeedsPageData>(
      key: ValueKey(_refreshKey),
      future: _loadFeedsPageData(accountId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final feedTree = snapshot.data ??
            const _FeedsPageData(groups: [], unreadCountsByFeed: {});
        final groups = feedTree.groups;

        // Filter groups based on filter
        final visibleGroupIds = ref.watch(groupFilterProvider(accountId));
        final filteredGroups = groups.where((g) {
          return visibleGroupIds.isEmpty || visibleGroupIds.contains(g.group.id);
        }).toList();

        if (filteredGroups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  visibleGroupIds.isEmpty ? AppSymbols.rss_feed : AppSymbols.filter_alt_off,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  visibleGroupIds.isEmpty ? 'No feeds yet' : 'No folders match filter',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  visibleGroupIds.isEmpty 
                      ? 'Tap the + button to add a feed'
                      : 'Adjust your folder filter to see feeds',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
          itemCount: filteredGroups.length,
          itemBuilder: (context, index) {
            final groupWithFeed = filteredGroups[index];
            return _buildGroupCard(
              groupWithFeed,
              feedTree.unreadCountsByFeed,
            );
          },
        );
      },
    );
  }

  Widget _buildGroupCard(
    GroupWithFeed groupWithFeed,
    Map<String, int> unreadCountsByFeed,
  ) {
    final group = groupWithFeed.group;
    final groupUnreadCount = _groupUnreadCount(groupWithFeed, unreadCountsByFeed);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              AppSymbols.folder_rounded,
              size: 20,
              color: scheme.onPrimaryContainer,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              AppCountBadge(
                count: groupUnreadCount,
                compact: true,
                highlight: groupUnreadCount > 0,
              ),
              PopupMenuButton<String>(
                icon: const Icon(AppSymbols.more_horiz),
                tooltip: 'Folder actions',
                onSelected: (value) {
                  if (value == 'delete') {
                    _confirmDeleteGroup(group);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(AppSymbols.delete_outline),
                      title: Text('Delete Folder'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        children: groupWithFeed.feeds.map((feed) {
          final feedObj = feed as Feed;
          final hasError = feedObj.lastSyncErrorAt != null;
          final unreadCount = unreadCountsByFeed[feedObj.id] ?? 0;
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            leading: Stack(
              children: [
                feedObj.icon != null && feedObj.icon!.isNotEmpty
                    ? CircleAvatar(
                        backgroundImage: NetworkImage(feedObj.icon!),
                        radius: 15,
                        onBackgroundImageError: (_, __) {},
                        child: feedObj.icon == null || feedObj.icon!.isEmpty
                            ? Text(feedObj.name[0].toUpperCase())
                            : null,
                      )
                    : CircleAvatar(
                        child: Text(feedObj.name[0].toUpperCase()),
                        radius: 15,
                      ),
                if (hasError)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        AppSymbols.error_outline,
                        size: 12,
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              feedObj.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w600,
                  ),
              textAlign: Directionality.of(context) == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left,
            ),
            subtitle: hasError
                ? Text(
                    'Last sync failed',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  )
                : null,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ArticleListScreen(feed: feedObj),
                ),
              );
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppCountBadge(
                  count: unreadCount,
                  compact: true,
                  highlight: unreadCount > 0,
                ),
                IconButton(
                  icon: const Icon(AppSymbols.more_horiz),
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
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
              ],
            ),
          );
        }).toList(),
        ),
      ),
    );
  }

  Future<_FeedsPageData> _loadFeedsPageData(int accountId) async {
    final groupDao = ref.read(groupDaoProvider);
    final articleDao = ref.read(articleDaoProvider);
    final groups = await groupDao.getAllWithFeeds(accountId);
    final unreadCountsByFeed = await articleDao.getUnreadCountsByFeed(accountId);
    return _FeedsPageData(
      groups: groups,
      unreadCountsByFeed: unreadCountsByFeed,
    );
  }

  int _groupUnreadCount(
    GroupWithFeed groupWithFeed,
    Map<String, int> unreadCountsByFeed,
  ) {
    var count = 0;
    for (final feed in groupWithFeed.feeds) {
      count += unreadCountsByFeed[(feed as Feed).id] ?? 0;
    }
    return count;
  }

  void _openAddFeed() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddFeedScreen()),
    ).then((_) => _refresh());
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _refresh();
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

class _FeedsPageData {
  const _FeedsPageData({
    required this.groups,
    required this.unreadCountsByFeed,
  });

  final List<GroupWithFeed> groups;
  final Map<String, int> unreadCountsByFeed;
}

