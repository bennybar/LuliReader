import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/group.dart';
import '../models/feed.dart';
import '../providers/app_provider.dart';
import '../services/account_service.dart';
import '../database/group_dao.dart';
import '../database/feed_dao.dart';

class FilterDrawer extends ConsumerStatefulWidget {
  final VoidCallback? onFiltersChanged;

  const FilterDrawer({super.key, this.onFiltersChanged});

  @override
  ConsumerState<FilterDrawer> createState() => _FilterDrawerState();
}

class _FilterDrawerState extends ConsumerState<FilterDrawer> {
  List<GroupWithFeed> _groupsWithFeeds = [];
  Set<String> _selectedGroups = {};
  Set<String> _selectedFeeds = {};
  bool _isLoading = true;
  bool _showAll = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account == null) {
      setState(() => _isLoading = false);
      return;
    }

    final groupDao = ref.read(groupDaoProvider);
    final feedDao = ref.read(feedDaoProvider);
    
    final groups = await groupDao.getAll(account.id!);
    final groupsWithFeeds = <GroupWithFeed>[];
    
    for (final group in groups) {
      final feeds = await feedDao.getByGroupId(account.id!, group.id);
      groupsWithFeeds.add(GroupWithFeed(
        group: group,
        feeds: feeds,
      ));
    }
    
    // Load current filters
    final currentGroupFilter = ref.read(groupFilterProvider(account.id!));
    final currentFeedFilter = ref.read(feedFilterProvider(account.id!));
    
    setState(() {
      _groupsWithFeeds = groupsWithFeeds;
      _showAll = currentGroupFilter.isEmpty && currentFeedFilter.isEmpty;
      if (_showAll) {
        // If show all, select all groups and feeds
        _selectedGroups = groups.map((g) => g.id).toSet();
        _selectedFeeds = {};
        for (final groupWithFeed in groupsWithFeeds) {
          for (final feed in groupWithFeed.feeds) {
            final feedObj = feed as Feed;
            _selectedFeeds.add(feedObj.id);
          }
        }
      } else {
        // Load selected groups and feeds from filters
        _selectedGroups = currentGroupFilter.isEmpty 
            ? groups.map((g) => g.id).toSet() 
            : currentGroupFilter;
        _selectedFeeds = currentFeedFilter.isEmpty
            ? {
                for (final groupWithFeed in groupsWithFeeds)
                  for (final feed in groupWithFeed.feeds)
                    (feed as Feed).id,
              }
            : currentFeedFilter;
      }
      _isLoading = false;
    });
  }

  void _toggleShowAll(bool? value) {
    if (value == null) return;
    setState(() {
      _showAll = value;
      if (_showAll) {
        // Select all groups and feeds
        _selectedGroups = _groupsWithFeeds.map((g) => g.group.id).toSet();
        _selectedFeeds = {};
        for (final groupWithFeed in _groupsWithFeeds) {
          for (final feed in groupWithFeed.feeds) {
            final feedObj = feed as Feed;
            _selectedFeeds.add(feedObj.id);
          }
        }
      }
    });
    _applyFilter();
  }

  void _toggleGroup(String groupId) {
    setState(() {
      if (_selectedGroups.contains(groupId)) {
        _selectedGroups.remove(groupId);
        // Also remove all feeds from this group
        final groupWithFeed = _groupsWithFeeds.firstWhere(
          (g) => g.group.id == groupId,
        );
        for (final feed in groupWithFeed.feeds) {
          final feedObj = feed as Feed;
          _selectedFeeds.remove(feedObj.id);
        }
      } else {
        _selectedGroups.add(groupId);
        // Also add all feeds from this group
        final groupWithFeed = _groupsWithFeeds.firstWhere(
          (g) => g.group.id == groupId,
        );
        for (final feed in groupWithFeed.feeds) {
          final feedObj = feed as Feed;
          _selectedFeeds.add(feedObj.id);
        }
      }
      _showAll = false;
    });
    _applyFilter();
  }

  void _toggleFeed(String feedId, String groupId) {
    setState(() {
      if (_selectedFeeds.contains(feedId)) {
        _selectedFeeds.remove(feedId);
        // Check if all feeds in group are deselected
        final groupWithFeed = _groupsWithFeeds.firstWhere(
          (g) => g.group.id == groupId,
        );
        final allFeedsSelected = groupWithFeed.feeds.every((feed) {
          final feedObj = feed as Feed;
          return feedObj.id == feedId || _selectedFeeds.contains(feedObj.id);
        });
        if (!allFeedsSelected) {
          _selectedGroups.remove(groupId);
        }
      } else {
        _selectedFeeds.add(feedId);
        // Ensure group is selected
        _selectedGroups.add(groupId);
      }
      _showAll = false;
    });
    _applyFilter();
  }

  Future<void> _applyFilter() async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account == null) return;

    final groupFilterNotifier = ref.read(groupFilterProvider(account.id!).notifier);
    final feedFilterNotifier = ref.read(feedFilterProvider(account.id!).notifier);
    
    if (_showAll) {
      // Clear filters to show all
      await groupFilterNotifier.setFilter({});
      await feedFilterNotifier.setFilter({});
    } else {
      // If nothing is selected, use a sentinel feed filter that matches nothing
      final groupsToSet = _selectedGroups;
      final feedsToSet = _selectedFeeds.isEmpty && _selectedGroups.isEmpty
          ? {'__none__'}
          : _selectedFeeds;
      // Set filters to selected groups and feeds
      await groupFilterNotifier.setFilter(groupsToSet);
      await feedFilterNotifier.setFilter(feedsToSet);
    }

    // Notify listeners (screens) to refresh immediately
    widget.onFiltersChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // MD3 styled header
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              color: colorScheme.onSurface,
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Filters',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 0,
                          color: colorScheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _toggleShowAll(!_showAll),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: _showAll,
                                    onChanged: _toggleShowAll,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Show all',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Folders and feeds list
                  Expanded(
                    child: _groupsWithFeeds.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.folder_outlined,
                                    size: 48,
                                    color: colorScheme.onSurface.withOpacity(0.38),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No folders available',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
                            itemCount: _groupsWithFeeds.length,
                            itemBuilder: (context, index) {
                              final groupWithFeed = _groupsWithFeeds[index];
                              return _buildGroupTile(groupWithFeed, theme, colorScheme);
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGroupTile(GroupWithFeed groupWithFeed, ThemeData theme, ColorScheme colorScheme) {
    final group = groupWithFeed.group;
    final allFeedsSelected = groupWithFeed.feeds.every((feed) {
      final feedObj = feed as Feed;
      return _selectedFeeds.contains(feedObj.id);
    });
    final someFeedsSelected = groupWithFeed.feeds.any((feed) {
      final feedObj = feed as Feed;
      return _selectedFeeds.contains(feedObj.id);
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            leading: Checkbox(
              value: allFeedsSelected ? true : (someFeedsSelected ? null : false),
              tristate: true,
              onChanged: (value) => _toggleGroup(group.id),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            title: Text(
              group.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              '${groupWithFeed.feeds.length} ${groupWithFeed.feeds.length == 1 ? 'feed' : 'feeds'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            iconColor: colorScheme.onSurfaceVariant,
            collapsedIconColor: colorScheme.onSurfaceVariant,
            children: groupWithFeed.feeds.map((feed) {
              final feedObj = feed as Feed;
              final isFeedSelected = _selectedFeeds.contains(feedObj.id);
              return _buildFeedTile(feedObj, isFeedSelected, theme, colorScheme);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedTile(Feed feed, bool isSelected, ThemeData theme, ColorScheme colorScheme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleFeed(feed.id, feed.groupId),
        child: Padding(
          padding: const EdgeInsets.only(left: 56, right: 16, top: 4, bottom: 4),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (value) => _toggleFeed(feed.id, feed.groupId),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  feed.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
