import 'package:flutter/material.dart';

import '../models/swipe_action.dart';
import '../services/background_sync_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storage = StorageService();
  final SyncService _syncService = SyncService();
  int _syncInterval = 60;
  int _articleFetchLimit = 200;
  bool _isRefreshingOffline = false;
  bool _hasSyncConfig = false;
  bool _autoMarkRead = true;
  SwipeAction _leftSwipeAction = SwipeAction.toggleRead;
  SwipeAction _rightSwipeAction = SwipeAction.toggleStar;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final interval = await _storage.getBackgroundSyncInterval();
    final limit = await _storage.getArticleFetchLimit();
    final config = await _storage.getUserConfig();
    final autoMark = await _storage.getAutoMarkRead();
    final leftSwipe = await _storage.getSwipeLeftAction();
    final rightSwipe = await _storage.getSwipeRightAction();
    setState(() {
      _syncInterval = interval;
      _articleFetchLimit = limit;
      _autoMarkRead = autoMark;
      _leftSwipeAction = leftSwipe;
      _rightSwipeAction = rightSwipe;
      if (config != null) {
        _syncService.setUserConfig(config);
        _hasSyncConfig = true;
      }
    });
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<bool> _ensureSyncConfigured() async {
    if (_hasSyncConfig) return true;
    final config = await _storage.getUserConfig();
    if (config == null) return false;
    _syncService.setUserConfig(config);
    _hasSyncConfig = true;
    return true;
  }

  Future<void> _refreshOfflineContent() async {
    if (_isRefreshingOffline) return;
    final hasConfig = await _ensureSyncConfigured();
    if (!hasConfig) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login again to refresh offline content.')),
        );
      }
      return;
    }

    setState(() => _isRefreshingOffline = true);
    try {
      await _syncService.refreshOfflineContent(force: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline content refreshed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Offline refresh failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingOffline = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Background Sync Interval'),
            subtitle: Text('$_syncInterval minutes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final interval = await showDialog<int>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sync Interval'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<int>(
                        title: const Text('15 minutes'),
                        value: 15,
                        groupValue: _syncInterval,
                        onChanged: (value) => Navigator.pop(context, value),
                      ),
                      RadioListTile<int>(
                        title: const Text('30 minutes'),
                        value: 30,
                        groupValue: _syncInterval,
                        onChanged: (value) => Navigator.pop(context, value),
                      ),
                      RadioListTile<int>(
                        title: const Text('60 minutes'),
                        value: 60,
                        groupValue: _syncInterval,
                        onChanged: (value) => Navigator.pop(context, value),
                      ),
                      RadioListTile<int>(
                        title: const Text('120 minutes'),
                        value: 120,
                        groupValue: _syncInterval,
                        onChanged: (value) => Navigator.pop(context, value),
                      ),
                    ],
                  ),
                ),
              );
              if (interval != null) {
                await _storage.saveBackgroundSyncInterval(interval);
                await BackgroundSyncService.scheduleSync(interval);
                setState(() => _syncInterval = interval);
              }
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Article Fetch Limit'),
            subtitle: Text('$_articleFetchLimit articles'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final limit = await showDialog<int>(
                context: context,
                builder: (context) {
                  int selectedLimit = _articleFetchLimit;
                  return StatefulBuilder(
                    builder: (context, setDialogState) => AlertDialog(
                      title: const Text('Article Fetch Limit'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<int>(
                            title: const Text('100 articles'),
                            value: 100,
                            groupValue: selectedLimit,
                            onChanged: (value) {
                              setDialogState(() => selectedLimit = value!);
                              Navigator.pop(context, value);
                            },
                          ),
                          RadioListTile<int>(
                            title: const Text('200 articles'),
                            value: 200,
                            groupValue: selectedLimit,
                            onChanged: (value) {
                              setDialogState(() => selectedLimit = value!);
                              Navigator.pop(context, value);
                            },
                          ),
                          RadioListTile<int>(
                            title: const Text('500 articles'),
                            value: 500,
                            groupValue: selectedLimit,
                            onChanged: (value) {
                              setDialogState(() => selectedLimit = value!);
                              Navigator.pop(context, value);
                            },
                          ),
                          RadioListTile<int>(
                            title: const Text('1000 articles'),
                            value: 1000,
                            groupValue: selectedLimit,
                            onChanged: (value) {
                              setDialogState(() => selectedLimit = value!);
                              Navigator.pop(context, value);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
              if (limit != null) {
                await _storage.saveArticleFetchLimit(limit);
                setState(() => _articleFetchLimit = limit);
              }
            },
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Auto mark article as read'),
            value: _autoMarkRead,
            subtitle: const Text('When enabled, opening an article marks it as read automatically'),
            onChanged: (value) async {
              await _storage.saveAutoMarkRead(value);
              setState(() => _autoMarkRead = value);
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Left swipe action'),
            subtitle: const Text('Swipe right → left'),
            trailing: DropdownButton<SwipeAction>(
              value: _leftSwipeAction,
              items: SwipeAction.values
                  .map((action) => DropdownMenuItem(
                        value: action,
                        child: Text(action.label),
                      ))
                  .toList(),
              onChanged: (action) async {
                if (action == null) return;
                await _storage.saveSwipeLeftAction(action);
                setState(() => _leftSwipeAction = action);
              },
            ),
          ),
          ListTile(
            title: const Text('Right swipe action'),
            subtitle: const Text('Swipe left → right'),
            trailing: DropdownButton<SwipeAction>(
              value: _rightSwipeAction,
              items: SwipeAction.values
                  .map((action) => DropdownMenuItem(
                        value: action,
                        child: Text(action.label),
                      ))
                  .toList(),
              onChanged: (action) async {
                if (action == null) return;
                await _storage.saveSwipeRightAction(action);
                setState(() => _rightSwipeAction = action);
              },
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Refresh Offline Content'),
            subtitle: const Text('Download full articles & images for offline reading'),
            trailing: _isRefreshingOffline
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_for_offline_outlined),
            onTap: _isRefreshingOffline ? null : _refreshOfflineContent,
          ),
          const Divider(),
          ListTile(
            title: const Text('Logout'),
            leading: const Icon(Icons.logout, color: Colors.red),
            onTap: _handleLogout,
          ),
        ],
      ),
    );
  }
}

