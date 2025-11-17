import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/background_sync_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storage = StorageService();
  int _syncInterval = 60;
  int _articleFetchLimit = 200;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final interval = await _storage.getBackgroundSyncInterval();
    final limit = await _storage.getArticleFetchLimit();
    setState(() {
      _syncInterval = interval;
      _articleFetchLimit = limit;
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

