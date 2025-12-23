import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/group.dart';
import '../providers/app_provider.dart';
import '../services/account_service.dart';

class GroupFilterDialog extends ConsumerStatefulWidget {
  const GroupFilterDialog({super.key});

  @override
  ConsumerState<GroupFilterDialog> createState() => _GroupFilterDialogState();
}

class _GroupFilterDialogState extends ConsumerState<GroupFilterDialog> {
  Set<String> _selectedGroups = {};
  List<Group> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account == null) {
      setState(() => _isLoading = false);
      return;
    }

    final groupDao = ref.read(groupDaoProvider);
    final groups = await groupDao.getAll(account.id!);
    
    // Load current filter
    final currentFilter = ref.read(groupFilterProvider(account.id!));
    
    setState(() {
      _groups = groups;
      // If no filter is set (empty set), select all groups by default
      _selectedGroups = currentFilter.isEmpty 
          ? groups.map((g) => g.id).toSet() // If no filter, select all
          : currentFilter;
      _isLoading = false;
    });
  }

  void _toggleGroup(String groupId) {
    setState(() {
      if (_selectedGroups.contains(groupId)) {
        _selectedGroups.remove(groupId);
      } else {
        _selectedGroups.add(groupId);
      }
    });
  }

  Future<void> _applyFilter() async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account == null) return;

    final filterNotifier = ref.read(groupFilterProvider(account.id!).notifier);
    
    // If all groups are selected, clear the filter (show all)
    final allGroupIds = _groups.map((g) => g.id).toSet();
    if (_selectedGroups.length == allGroupIds.length) {
      await filterNotifier.setFilter({});
    } else {
      await filterNotifier.setFilter(_selectedGroups);
    }
    
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filter by Folders'),
      content: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SizedBox(
              width: double.maxFinite,
              child: _groups.isEmpty
                  ? const Text('No folders available')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _groups.length,
                      itemBuilder: (context, index) {
                        final group = _groups[index];
                        final isSelected = _selectedGroups.contains(group.id);
                        return CheckboxListTile(
                          title: Text(group.name),
                          value: isSelected,
                          onChanged: (_) => _toggleGroup(group.id),
                        );
                      },
                    ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _selectedGroups = _groups.map((g) => g.id).toSet();
            });
          },
          child: const Text('Select All'),
        ),
        FilledButton(
          onPressed: _applyFilter,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

