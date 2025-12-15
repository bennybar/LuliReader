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
            icon: const Icon(Icons.add),
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: Icon(
          Icons.folder,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(groupWithFeed.group.name),
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
            title: Text(feedObj.name),
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
}

