import 'package:flutter/material.dart';

import '../models/swipe_action.dart';
import '../notifiers/preview_lines_notifier.dart';
import '../notifiers/swipe_prefs_notifier.dart';
import '../services/background_sync_service.dart';
import '../services/local_data_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../widgets/platform_app_bar.dart';
import 'feeds_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ValueChanged<bool>? onShowStarredTabChanged;

  const SettingsScreen({super.key, this.onShowStarredTabChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storage = StorageService();
  final SyncService _syncService = SyncService();
  final LocalDataService _localDataService = LocalDataService();
  final PreviewLinesNotifier _previewNotifier = PreviewLinesNotifier.instance;
  int _syncInterval = 60;
  int _articleFetchLimit = 200;
  bool _isRefreshingOffline = false;
  bool _hasSyncConfig = false;
  bool _autoMarkRead = true;
  SwipeAction _leftSwipeAction = SwipeAction.toggleRead;
  SwipeAction _rightSwipeAction = SwipeAction.toggleStar;
  bool _showStarredTab = true;
  int _previewLines = 3;
  bool _isClearingLocalData = false;
  String _defaultTab = 'home';
  double _articleFontSize = 16.0;
  bool _swipeAllowsDelete = false;

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
    final showStarred = await _storage.getShowStarredTab();
    final previewLines = await _storage.getPreviewLines();
    final defaultTab = await _storage.getDefaultTab();
    final articleFontSize = await _storage.getArticleFontSize();
    final swipeAllowsDelete = await _storage.getSwipeAllowsDelete();
    setState(() {
      _syncInterval = interval;
      _articleFetchLimit = limit;
      _autoMarkRead = autoMark;
      _leftSwipeAction = leftSwipe;
      _rightSwipeAction = rightSwipe;
      _showStarredTab = showStarred;
      _previewLines = previewLines;
      _defaultTab = defaultTab;
      _articleFontSize = articleFontSize;
      _swipeAllowsDelete = swipeAllowsDelete;
      if (config != null) {
        _syncService.setUserConfig(config);
        _hasSyncConfig = true;
      }
    });
    _previewNotifier.setLines(previewLines);
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
      await _clearLocalData(showFeedback: false);
      await _storage.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _confirmAndClearLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Local Data'),
        content: const Text(
          'This will delete all downloaded articles, offline files, and cached images. '
          'You will stay logged in, but the app will need to sync again. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearLocalData(showFeedback: true);
    }
  }

  Future<void> _clearLocalData({required bool showFeedback}) async {
    if (_isClearingLocalData) return;
    setState(() => _isClearingLocalData = true);
    try {
      await _localDataService.clearAllLocalData();
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Local data cleared. A fresh sync will be required.')),
        );
      }
    } catch (e) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear local data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClearingLocalData = false);
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
      appBar: const PlatformAppBar(
        title: 'Settings',
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 80),
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
          SwitchListTile(
            title: const Text('Allow swipe to delete articles'),
            subtitle: const Text('Swipe actions can permanently remove articles'),
            value: _swipeAllowsDelete,
            onChanged: (value) async {
              await _storage.saveSwipeAllowsDelete(value);
              setState(() => _swipeAllowsDelete = value);
              SwipePrefsNotifier.instance.ping();
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Article font size'),
            subtitle: Text('${_articleFontSize.toStringAsFixed(0)} pt'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final selected = await showDialog<double>(
                context: context,
                builder: (context) {
                  double tempSize = _articleFontSize;
                  return StatefulBuilder(
                    builder: (context, setDialogState) => AlertDialog(
                      title: const Text('Article font size'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Slider(
                            min: 14,
                            max: 24,
                            divisions: 10,
                            value: tempSize,
                            label: '${tempSize.toStringAsFixed(0)} pt',
                            onChanged: (value) {
                              setDialogState(() => tempSize = value);
                            },
                          ),
                          Text('${tempSize.toStringAsFixed(0)} pt'),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, tempSize),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              );
              if (selected != null) {
                await _storage.saveArticleFontSize(selected);
                setState(() => _articleFontSize = selected);
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
            title: const Text('Article preview lines'),
            subtitle: Text('$_previewLines line${_previewLines == 1 ? '' : 's'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final selected = await showDialog<int>(
                context: context,
                builder: (context) {
                  int tempSelection = _previewLines;
                  return StatefulBuilder(
                    builder: (context, setDialogState) => AlertDialog(
                      title: const Text('Preview lines'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(4, (index) {
                          final value = index + 1;
                          return RadioListTile<int>(
                            title: Text('$value line${value == 1 ? '' : 's'}'),
                            value: value,
                            groupValue: tempSelection,
                            onChanged: (val) {
                              if (val == null) return;
                              setDialogState(() => tempSelection = val);
                              Navigator.pop(context, val);
                            },
                          );
                        }),
                      ),
                    ),
                  );
                },
              );
              if (selected != null) {
                await _storage.savePreviewLines(selected);
                _previewNotifier.setLines(selected);
                setState(() => _previewLines = selected);
              }
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Default Tab'),
            subtitle: Text(_defaultTab == 'home' ? 'Home' : 'Unread'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final selected = await showDialog<String>(
                context: context,
                builder: (context) {
                  String tempSelection = _defaultTab;
                  return StatefulBuilder(
                    builder: (context, setDialogState) => AlertDialog(
                      title: const Text('Default Tab'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<String>(
                            title: const Text('Home'),
                            value: 'home',
                            groupValue: tempSelection,
                            onChanged: (val) {
                              if (val == null) return;
                              setDialogState(() => tempSelection = val);
                              Navigator.pop(context, val);
                            },
                          ),
                          RadioListTile<String>(
                            title: const Text('Unread'),
                            value: 'unread',
                            groupValue: tempSelection,
                            onChanged: (val) {
                              if (val == null) return;
                              setDialogState(() => tempSelection = val);
                              Navigator.pop(context, val);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
              if (selected != null) {
                await _storage.saveDefaultTab(selected);
                setState(() => _defaultTab = selected);
              }
            },
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Show Starred Tab'),
            value: _showStarredTab,
            subtitle: const Text('Toggle the Starred tab in the bottom navigation'),
            onChanged: (value) async {
              await _storage.saveShowStarredTab(value);
              setState(() => _showStarredTab = value);
              widget.onShowStarredTabChanged?.call(value);
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Feeds'),
            subtitle: const Text('View all your RSS feeds'),
            leading: const Icon(Icons.list),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FeedsScreen(),
                ),
              );
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
                SwipePrefsNotifier.instance.ping();
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
                SwipePrefsNotifier.instance.ping();
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
            title: const Text('Clear Local Data'),
            subtitle: const Text('Delete local database, offline articles, and cached images'),
            leading: const Icon(Icons.delete_forever_outlined),
            trailing: _isClearingLocalData
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cleaning_services_outlined),
            onTap: _isClearingLocalData ? null : _confirmAndClearLocalData,
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

