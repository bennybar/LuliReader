import 'package:flutter/material.dart';

import '../models/swipe_action.dart';
import '../notifiers/article_list_padding_notifier.dart';
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
  final ArticleListPaddingNotifier _listPaddingNotifier =
      ArticleListPaddingNotifier.instance;
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
  double _articleListPadding = 16.0;
  bool _swipeAllowsDelete = false;
  bool _isLoadingSyncLog = false;
  List<String> _syncLogEntries = const [];
  int _maxArticleAgeDays = 30;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final interval = await _storage.getBackgroundSyncInterval();
    final limit = await _storage.getArticleFetchLimit();
    final maxAgeDays = await _storage.getMaxArticleAgeDays();
    final config = await _storage.getUserConfig();
    final autoMark = await _storage.getAutoMarkRead();
    final leftSwipe = await _storage.getSwipeLeftAction();
    final rightSwipe = await _storage.getSwipeRightAction();
    final showStarred = await _storage.getShowStarredTab();
    final previewLines = await _storage.getPreviewLines();
    final defaultTab = await _storage.getDefaultTab();
    final articleFontSize = await _storage.getArticleFontSize();
    final swipeAllowsDelete = await _storage.getSwipeAllowsDelete();
    final articleListPadding = await _storage.getArticleListPadding();
    setState(() {
      _syncInterval = interval;
      _articleFetchLimit = limit;
      _maxArticleAgeDays = maxAgeDays;
      _autoMarkRead = autoMark;
      _leftSwipeAction = leftSwipe;
      _rightSwipeAction = rightSwipe;
      _showStarredTab = showStarred;
      _previewLines = previewLines;
      _defaultTab = defaultTab;
      _articleFontSize = articleFontSize;
      _swipeAllowsDelete = swipeAllowsDelete;
      _articleListPadding = articleListPadding;
      if (config != null) {
        _syncService.setUserConfig(config);
        _hasSyncConfig = true;
      }
    });
    _previewNotifier.setLines(previewLines);
    _listPaddingNotifier.setPadding(articleListPadding);
  }

  Future<void> _openSyncLog() async {
    setState(() {
      _isLoadingSyncLog = true;
    });
    try {
      final entries = await _storage.getSyncLogEntries();
      if (!mounted) return;
      setState(() {
        _syncLogEntries = entries.reversed.toList(); // newest first
      });
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Background sync log'),
                    subtitle: Text(
                      _syncLogEntries.isEmpty
                          ? 'No background sync events recorded yet.'
                          : '${_syncLogEntries.length} recent entries',
                    ),
                    trailing:
                        _syncLogEntries.isEmpty
                            ? null
                            : TextButton(
                              onPressed: () async {
                                await _storage.clearSyncLogEntries();
                                if (!mounted) return;
                                setState(() {
                                  _syncLogEntries = const [];
                                });
                                Navigator.of(context).pop();
                              },
                              child: const Text('Clear'),
                            ),
                  ),
                  const Divider(height: 0),
                  Expanded(
                    child:
                        _syncLogEntries.isEmpty
                            ? const Center(
                              child: Text(
                                'No background sync activity yet.\n'
                                'Leave the app installed and Background App Refresh enabled\n'
                                'to see background sync events here.',
                                textAlign: TextAlign.center,
                              ),
                            )
                            : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _syncLogEntries.length,
                              itemBuilder: (context, index) {
                                final line = _syncLogEntries[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4.0,
                                  ),
                                  child: Text(
                                    line,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(fontFamily: 'monospace'),
                                  ),
                                );
                              },
                            ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSyncLog = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
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
      builder:
          (context) => AlertDialog(
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
          const SnackBar(
            content: Text('Local data cleared. A fresh sync will be required.'),
          ),
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

  String _describeListPadding(double value) {
    final label =
        value <= 12
            ? 'Compact'
            : value <= 20
            ? 'Comfortable'
            : 'Roomy';
    return '$label (${value.toStringAsFixed(0)} px)';
  }

  Future<void> _pickArticleListPadding() async {
    final selected = await showDialog<double>(
      context: context,
      builder: (context) {
        double tempPadding = _articleListPadding;
        return StatefulBuilder(
          builder:
              (context, setDialogState) => AlertDialog(
                title: const Text('Article list padding'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Slider(
                      min: 8,
                      max: 32,
                      divisions: 12,
                      value: tempPadding,
                      label: _describeListPadding(tempPadding),
                      onChanged: (value) {
                        setDialogState(() => tempPadding = value);
                      },
                    ),
                    Text(_describeListPadding(tempPadding)),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, tempPadding),
                    child: const Text('Save'),
                  ),
                ],
              ),
        );
      },
    );

    if (selected != null) {
      await _storage.saveArticleListPadding(selected);
      _listPaddingNotifier.setPadding(selected);
      setState(() => _articleListPadding = selected);
    }
  }

  Widget _buildSection(String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1)
                    const Divider(height: 0, thickness: 0.7),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
          const SnackBar(
            content: Text('Please login again to refresh offline content.'),
          ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Offline refresh failed: $e')));
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
      appBar: const PlatformAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _buildSection('Sync & Background', [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Background sync interval'),
              subtitle: Text('$_syncInterval minutes'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final interval = await showDialog<int>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('Sync Interval'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile<int>(
                              title: const Text('15 minutes'),
                              value: 15,
                              groupValue: _syncInterval,
                              onChanged:
                                  (value) => Navigator.pop(context, value),
                            ),
                            RadioListTile<int>(
                              title: const Text('30 minutes'),
                              value: 30,
                              groupValue: _syncInterval,
                              onChanged:
                                  (value) => Navigator.pop(context, value),
                            ),
                            RadioListTile<int>(
                              title: const Text('60 minutes'),
                              value: 60,
                              groupValue: _syncInterval,
                              onChanged:
                                  (value) => Navigator.pop(context, value),
                            ),
                            RadioListTile<int>(
                              title: const Text('120 minutes'),
                              value: 120,
                              groupValue: _syncInterval,
                              onChanged:
                                  (value) => Navigator.pop(context, value),
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
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Background sync log'),
              subtitle: const Text('View recent background sync activity'),
              trailing:
                  _isLoadingSyncLog
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.chevron_right),
              onTap: _isLoadingSyncLog ? null : _openSyncLog,
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Article fetch limit'),
              subtitle: Text('$_articleFetchLimit articles'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final limit = await showDialog<int>(
                  context: context,
                  builder: (context) {
                    int selectedLimit = _articleFetchLimit;
                    return StatefulBuilder(
                      builder:
                          (context, setDialogState) => AlertDialog(
                            title: const Text('Article Fetch Limit'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                RadioListTile<int>(
                                  title: const Text('100 articles'),
                                  value: 100,
                                  groupValue: selectedLimit,
                                  onChanged: (value) {
                                    setDialogState(
                                      () => selectedLimit = value!,
                                    );
                                    Navigator.pop(context, value);
                                  },
                                ),
                                RadioListTile<int>(
                                  title: const Text('200 articles'),
                                  value: 200,
                                  groupValue: selectedLimit,
                                  onChanged: (value) {
                                    setDialogState(
                                      () => selectedLimit = value!,
                                    );
                                    Navigator.pop(context, value);
                                  },
                                ),
                                RadioListTile<int>(
                                  title: const Text('500 articles'),
                                  value: 500,
                                  groupValue: selectedLimit,
                                  onChanged: (value) {
                                    setDialogState(
                                      () => selectedLimit = value!,
                                    );
                                    Navigator.pop(context, value);
                                  },
                                ),
                                RadioListTile<int>(
                                  title: const Text('1000 articles'),
                                  value: 1000,
                                  groupValue: selectedLimit,
                                  onChanged: (value) {
                                    setDialogState(
                                      () => selectedLimit = value!,
                                    );
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
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Article age limit'),
              subtitle: Text('Last $_maxArticleAgeDays days'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final options = [3, 7, 14, 30, 60, 90, 180];
                final selection = await showDialog<int>(
                  context: context,
                  builder: (context) {
                    int selected = _maxArticleAgeDays;
                    return StatefulBuilder(
                      builder:
                          (context, setDialogState) => AlertDialog(
                            title: const Text('Only fetch articles from'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: options
                                  .map(
                                    (days) => RadioListTile<int>(
                                      title: Text('Last $days days'),
                                      value: days,
                                      groupValue: selected,
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setDialogState(() => selected = value);
                                        Navigator.pop(context, value);
                                      },
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                    );
                  },
                );
                if (selection != null) {
                  await _storage.saveMaxArticleAgeDays(selection);
                  setState(() => _maxArticleAgeDays = selection);
                }
              },
            ),
          ]),
          _buildSection('Reading Experience', [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Article font size'),
              subtitle: Text('${_articleFontSize.toStringAsFixed(0)} pt'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final selected = await showDialog<double>(
                  context: context,
                  builder: (context) {
                    double tempSize = _articleFontSize;
                    return StatefulBuilder(
                      builder:
                          (context, setDialogState) => AlertDialog(
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
                                onPressed:
                                    () => Navigator.pop(context, tempSize),
                                child: const Text('Save'),
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
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Article list padding'),
              subtitle: Text(_describeListPadding(_articleListPadding)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickArticleListPadding,
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Article preview lines'),
              subtitle: Text(
                '$_previewLines line${_previewLines == 1 ? '' : 's'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final selected = await showDialog<int>(
                  context: context,
                  builder: (context) {
                    int tempSelection = _previewLines;
                    return StatefulBuilder(
                      builder:
                          (context, setDialogState) => AlertDialog(
                            title: const Text('Preview lines'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(4, (index) {
                                final value = index + 1;
                                return RadioListTile<int>(
                                  title: Text(
                                    '$value line${value == 1 ? '' : 's'}',
                                  ),
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
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              title: const Text('Auto mark article as read'),
              subtitle: const Text(
                'Opening an article will automatically mark it as read',
              ),
              value: _autoMarkRead,
              onChanged: (value) async {
                await _storage.saveAutoMarkRead(value);
                setState(() => _autoMarkRead = value);
              },
            ),
          ]),
          _buildSection('Navigation & Tabs', [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Default tab'),
              subtitle: Text(_defaultTab == 'home' ? 'Home' : 'Unread'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final selected = await showDialog<String>(
                  context: context,
                  builder: (context) {
                    String tempSelection = _defaultTab;
                    return StatefulBuilder(
                      builder:
                          (context, setDialogState) => AlertDialog(
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
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              title: const Text('Show Starred tab'),
              subtitle: const Text(
                'Toggle the Starred tab in the bottom navigation',
              ),
              value: _showStarredTab,
              onChanged: (value) async {
                await _storage.saveShowStarredTab(value);
                setState(() => _showStarredTab = value);
                widget.onShowStarredTabChanged?.call(value);
              },
            ),
          ]),
          _buildSection('Swipe Actions', [
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              title: const Text('Allow swipe to delete'),
              subtitle: const Text(
                'Swipe actions can permanently remove articles',
              ),
              value: _swipeAllowsDelete,
              onChanged: (value) async {
                await _storage.saveSwipeAllowsDelete(value);
                setState(() => _swipeAllowsDelete = value);
                SwipePrefsNotifier.instance.ping();
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Left swipe action'),
              subtitle: const Text('Swipe right → left'),
              trailing: DropdownButton<SwipeAction>(
                value: _leftSwipeAction,
                items:
                    SwipeAction.values
                        .map(
                          (action) => DropdownMenuItem(
                            value: action,
                            child: Text(action.label),
                          ),
                        )
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Right swipe action'),
              subtitle: const Text('Swipe left → right'),
              trailing: DropdownButton<SwipeAction>(
                value: _rightSwipeAction,
                items:
                    SwipeAction.values
                        .map(
                          (action) => DropdownMenuItem(
                            value: action,
                            child: Text(action.label),
                          ),
                        )
                        .toList(),
                onChanged: (action) async {
                  if (action == null) return;
                  await _storage.saveSwipeRightAction(action);
                  setState(() => _rightSwipeAction = action);
                  SwipePrefsNotifier.instance.ping();
                },
              ),
            ),
          ]),
          _buildSection('Offline & Storage', [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Refresh offline content'),
              subtitle: const Text(
                'Download full articles & images for offline reading',
              ),
              trailing:
                  _isRefreshingOffline
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.download_for_offline_outlined),
              onTap: _isRefreshingOffline ? null : _refreshOfflineContent,
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Clear local data'),
              subtitle: const Text(
                'Delete local database, offline articles, and cached images',
              ),
              leading: const Icon(Icons.delete_forever_outlined),
              trailing:
                  _isClearingLocalData
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.cleaning_services_outlined),
              onTap: _isClearingLocalData ? null : _confirmAndClearLocalData,
            ),
          ]),
          _buildSection('Account', [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Feeds'),
              subtitle: const Text('View all of your RSS feeds'),
              leading: const Icon(Icons.list),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FeedsScreen()),
                );
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              leading: const Icon(Icons.logout, color: Colors.red),
              onTap: _handleLogout,
            ),
          ]),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
