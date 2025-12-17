import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../database/feed_dao.dart';
import '../database/group_dao.dart';
import '../models/account.dart';
import '../models/feed.dart';
import '../models/group.dart';
import '../services/rss_helper.dart';
import '../services/freshrss_service.dart';
import '../services/sync_coordinator.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

class AddFeedScreen extends ConsumerStatefulWidget {
  const AddFeedScreen({super.key});

  @override
  ConsumerState<AddFeedScreen> createState() => _AddFeedScreenState();
}

class _AddFeedScreenState extends ConsumerState<AddFeedScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  bool _isLoading = false;
  String? _selectedGroupId;

  Future<void> _addFeed() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account == null) {
        throw Exception('No account found');
      }

      final rssHelper = ref.read(rssHelperProvider);
      final feedDao = ref.read(feedDaoProvider);
      final groupDao = ref.read(groupDaoProvider);
      final freshRssService = ref.read(freshRssServiceProvider);
      final syncCoordinator = ref.read(syncCoordinatorProvider);

      // Check if feed already exists
      if (await feedDao.isFeedExist(_urlController.text.trim(), accountId: account.id)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feed already exists')),
        );
        return;
      }

      // Fetch feed to get name
      final syndFeed = await rssHelper.searchFeed(_urlController.text.trim());
      
      // Get selected group or default group
      String targetGroupId;
      if (_selectedGroupId != null) {
        final selectedGroup = await groupDao.getById(_selectedGroupId!);
        if (selectedGroup != null) {
          targetGroupId = selectedGroup.id;
        } else {
          final defaultGroupId = groupDao.getDefaultGroupId(account.id!);
          final defaultGroup = await groupDao.getById(defaultGroupId);
          if (defaultGroup == null) {
            throw Exception('Default group not found');
          }
          targetGroupId = defaultGroup.id;
        }
      } else {
        final defaultGroupId = groupDao.getDefaultGroupId(account.id!);
        final defaultGroup = await groupDao.getById(defaultGroupId);
        if (defaultGroup == null) {
          throw Exception('Default group not found');
        }
        targetGroupId = defaultGroup.id;
      }

      if (account.type == AccountType.freshrss) {
        final endpoint = FreshRssService.normalizeApiEndpoint(
          account.apiEndpoint ?? _urlController.text.trim(),
        );
        final token = await _ensureFreshRssAuthToken(account, endpoint);
        final groupName = (await groupDao.getById(targetGroupId))?.name;
        await freshRssService.subscribeToFeed(
          endpoint,
          token,
          _urlController.text.trim(),
          title: syndFeed.title,
          categoryLabel: groupName,
        );
        await syncCoordinator.syncAccount(account.id!);
      } else {
        // Create local feed
        final feedId = '${account.id}\$${const Uuid().v4()}';
        final feed = Feed(
          id: feedId,
          name: syndFeed.title ?? 'Untitled Feed',
          url: _urlController.text.trim(),
          groupId: targetGroupId,
          accountId: account.id!,
        );

        await feedDao.insert(feed);

        // Try to get icon
        final iconLink = await rssHelper.queryRssIconLink(feed.url);
        if (iconLink != null) {
          await feedDao.update(feed.copyWith(icon: iconLink));
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feed added successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding feed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String> _ensureFreshRssAuthToken(Account account, String endpoint) async {
    if (account.authToken != null && account.authToken!.isNotEmpty) {
      return account.authToken!;
    }
    if (account.username == null ||
        account.username!.isEmpty ||
        account.password == null ||
        account.password!.isEmpty) {
      throw Exception('FreshRSS credentials missing');
    }
    final token = await ref.read(freshRssServiceProvider).authenticate(
          endpoint,
          account.username!,
          account.password!,
        );
    final updatedAccount = account.copyWith(
      authToken: token,
      apiEndpoint: endpoint,
    );
    await ref.read(accountServiceProvider).updateAccount(updatedAccount);
    return token;
  }

  Future<List<Group>> _loadGroupsForDropdown() async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account == null) return [];
    final groupDao = ref.read(groupDaoProvider);
    final groups = await groupDao.getAll(account.id!);
    // Set default selected group if not set
    if (_selectedGroupId == null && groups.isNotEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedGroupId = groups.first.id;
          });
        }
      });
    }
    return groups;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Feed'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'RSS Feed URL',
                  hintText: 'https://example.com/feed.xml',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a feed URL';
                  }
                  if (!Uri.tryParse(value.trim())!.hasScheme) {
                    return 'Please enter a valid URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              FutureBuilder<List<Group>>(
                future: _loadGroupsForDropdown(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }
                  final groups = snapshot.data ?? [];
                  if (groups.isEmpty) {
                    return const Text('No folders available');
                  }
                  return DropdownButtonFormField<String>(
                    value: _selectedGroupId,
                    decoration: const InputDecoration(
                      labelText: 'Folder',
                      border: OutlineInputBorder(),
                    ),
                    items: groups.map((group) {
                      return DropdownMenuItem<String>(
                        value: group.id,
                        child: Text(group.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedGroupId = value;
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _addFeed,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add Feed'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

