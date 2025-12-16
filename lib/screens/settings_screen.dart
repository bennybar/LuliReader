import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../services/account_service.dart';
import '../services/local_rss_service.dart';
import '../database/database_helper.dart';
import '../background/background_sync.dart';
import '../services/shared_preferences_service.dart';
import '../models/account.dart';
import '../services/sync_log_service.dart';
import 'opml_import_export_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isResyncing = false;
  double _articleFontScale = 1.0;
  double _articlePadding = 16.0;

  @override
  void initState() {
    super.initState();
    _loadReadingPrefs();
  }

  Future<void> _loadReadingPrefs() async {
    final prefs = SharedPreferencesService();
    await prefs.init();
    final font = await prefs.getDouble('articleFontScale') ?? 1.0;
    final pad = await prefs.getDouble('articlePadding') ?? 16.0;
    if (mounted) {
      setState(() {
        _articleFontScale = font;
        _articlePadding = pad;
      });
    }
  }

  Future<void> _saveReadingPref(String key, double value) async {
    final prefs = SharedPreferencesService();
    await prefs.init();
    await prefs.setDouble(key, value);
  }

  Future<void> _updateAccountSetting(String field, dynamic value) async {
    try {
      final accountService = ref.read(accountServiceProvider);
      final account = await accountService.getCurrentAccount();
      if (account == null) return;

      Account updatedAccount;
      switch (field) {
        case 'syncOnlyOnWiFi':
          updatedAccount = account.copyWith(syncOnlyOnWiFi: value as bool);
          break;
        case 'syncOnlyWhenCharging':
          updatedAccount = account.copyWith(syncOnlyWhenCharging: value as bool);
          break;
        case 'isFullContent':
          updatedAccount = account.copyWith(isFullContent: value as bool);
          break;
        case 'swipeStartAction':
          updatedAccount = account.copyWith(swipeStartAction: value as int);
          break;
        case 'swipeEndAction':
          updatedAccount = account.copyWith(swipeEndAction: value as int);
          break;
        case 'syncInterval':
          updatedAccount = account.copyWith(syncInterval: value as int);
          break;
        case 'defaultScreen':
          updatedAccount = account.copyWith(defaultScreen: value as int);
          break;
        case 'maxPastDays':
          updatedAccount = account.copyWith(maxPastDays: value as int);
          break;
        case 'syncOnStart':
          updatedAccount = account.copyWith(syncOnStart: value as bool);
          break;
        default:
          return;
      }

      await accountService.updateAccount(updatedAccount);
      if (mounted) {
        ref.invalidate(currentAccountProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating setting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(currentAccountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: accountAsync.when(
        data: (account) {
          if (account == null) {
            return const Center(child: Text('No account found'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Account Info
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_circle),
                  title: const Text('Account'),
                  subtitle: Text(account.name),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
              const SizedBox(height: 16),

              // App Settings
              Text(
                'App Settings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.home),
                  title: const Text('Default Screen'),
                  subtitle: Text(
                    account.defaultScreen == 0
                        ? 'Feeds (opens on the folder view)'
                        : 'Articles (Flow stream)',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDefaultScreenDialog(context, account),
                ),
              ),
              const SizedBox(height: 24),
              // Article Appearance
              Text(
                'Article Appearance',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Font Size',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Slider(
                        value: _articleFontScale,
                        min: 0.8,
                        max: 1.4,
                        divisions: 12,
                        label: '${_articleFontScale.toStringAsFixed(2)}x',
                        onChanged: (v) async {
                          setState(() => _articleFontScale = v);
                          await _saveReadingPref('articleFontScale', v);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Content Padding',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Slider(
                        value: _articlePadding,
                        min: 8,
                        max: 32,
                        divisions: 24,
                        label: '${_articlePadding.toStringAsFixed(0)} px',
                        onChanged: (v) async {
                          setState(() => _articlePadding = v);
                          await _saveReadingPref('articlePadding', v);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Reading Settings
              Text(
                'Reading Settings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.article_outlined),
                  title: const Text('Parse Full Content'),
                  subtitle: const Text(
                    'Automatically download and parse full article content for ALL feeds in the background during sync',
                  ),
                  value: account.isFullContent,
                  onChanged: (value) => _updateAccountSetting('isFullContent', value),
                ),
              ),
              const SizedBox(height: 24),
              
              // Gesture Settings
              Text(
                'Gesture Settings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.swipe_left),
                  title: const Text('Swipe to Start'),
                  subtitle: Text(_getSwipeActionDescription(account.swipeStartAction)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showSwipeActionDialog(context, account, true),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.swipe_right),
                  title: const Text('Swipe to End'),
                  subtitle: Text(_getSwipeActionDescription(account.swipeEndAction)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showSwipeActionDialog(context, account, false),
                ),
              ),
              const SizedBox(height: 24),
              
              // Sync Settings
              Text(
                'Sync Settings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sync Interval'),
                  subtitle: Text('${account.syncInterval} minutes'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showSyncIntervalDialog(context, account),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.play_circle_outline),
                  title: const Text('Sync on App Start'),
                  subtitle: const Text('Automatically sync when the app starts'),
                  value: account.syncOnStart,
                  onChanged: (value) => _updateAccountSetting('syncOnStart', value),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Max Past Days to Sync'),
                  subtitle: Text(
                    '${account.maxPastDays} days • Older items will be skipped on sync',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showMaxPastDaysDialog(context, account),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.wifi),
                  title: const Text('Sync Only on Wi-Fi'),
                  subtitle: const Text('Only sync when connected to Wi-Fi'),
                  value: account.syncOnlyOnWiFi,
                  onChanged: (value) => _updateAccountSetting('syncOnlyOnWiFi', value),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.battery_charging_full),
                  title: const Text('Sync Only When Charging'),
                  subtitle: const Text('Only sync when device is charging'),
                  value: account.syncOnlyWhenCharging,
                  onChanged: (value) => _updateAccountSetting('syncOnlyWhenCharging', value),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Resync All Articles'),
                  subtitle: const Text('Clear local articles and re-download everything'),
                  trailing: _isResyncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _isResyncing ? null : () => _confirmResync(context, account),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Sync Log'),
                  subtitle: const Text('View background sync history'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showSyncLog(context),
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.import_export),
                title: const Text('OPML Import/Export'),
                subtitle: const Text('Import or export feeds'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OpmlImportExportScreen(),
                    ),
                  );
                  // Refresh if import was successful
                  if (result == true) {
                    // The home screen will refresh automatically
                  }
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('About'),
                subtitle: const Text('Luli Reader v1.0.0'),
                trailing: const Icon(Icons.chevron_right),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }

  String _getSwipeActionDescription(int action) {
    switch (action) {
      case 0:
        return 'None';
      case 1:
        return 'Toggle Read';
      case 2:
        return 'Toggle Starred';
      default:
        return 'None';
    }
  }

  Future<void> _showMaxPastDaysDialog(BuildContext context, Account account) async {
    const options = [3, 5, 10, 30, 90];
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Max Past Days to Sync'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((days) => RadioListTile<int>(
                    title: Text('$days days'),
                    value: days,
                    groupValue: account.maxPastDays,
                    onChanged: (value) => Navigator.of(context).pop(value),
                  ))
              .toList(),
        ),
      ),
    );

    if (selected != null) {
      await _updateAccountSetting('maxPastDays', selected);
    }
  }

  Future<void> _showSwipeActionDialog(BuildContext context, Account account, bool isStart) async {
    final action = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isStart ? 'Swipe to Start' : 'Swipe to End'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int>(
              title: const Text('None'),
              value: 0,
              groupValue: isStart ? account.swipeStartAction : account.swipeEndAction,
              onChanged: (value) => Navigator.of(context).pop(value),
            ),
            RadioListTile<int>(
              title: const Text('Toggle Read'),
              value: 1,
              groupValue: isStart ? account.swipeStartAction : account.swipeEndAction,
              onChanged: (value) => Navigator.of(context).pop(value),
            ),
            RadioListTile<int>(
              title: const Text('Toggle Starred'),
              value: 2,
              groupValue: isStart ? account.swipeStartAction : account.swipeEndAction,
              onChanged: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
    );

    if (action != null) {
      await _updateAccountSetting(
        isStart ? 'swipeStartAction' : 'swipeEndAction',
        action,
      );
    }
  }

  Future<void> _showDefaultScreenDialog(BuildContext context, Account account) async {
    final screen = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Default Screen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int>(
              title: const Text('Feeds'),
              value: 0,
              groupValue: account.defaultScreen,
              onChanged: (value) => Navigator.of(context).pop(value),
            ),
            RadioListTile<int>(
              title: const Text('Flow'),
              value: 1,
              groupValue: account.defaultScreen,
              onChanged: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
    );

    if (screen != null) {
      await _updateAccountSetting('defaultScreen', screen);
    }
  }

  Future<void> _showSyncIntervalDialog(BuildContext context, Account account) async {
    const options = [15, 30, 60, 120];
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Interval'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((mins) => RadioListTile<int>(
                    title: Text('$mins minutes'),
                    value: mins,
                    groupValue: account.syncInterval,
                    onChanged: (value) => Navigator.of(context).pop(value),
                  ))
              .toList(),
        ),
      ),
    );

    if (selected != null && selected != account.syncInterval) {
      await _updateAccountSetting('syncInterval', selected);
      await registerBackgroundSync(
        selected,
        requiresCharging: account.syncOnlyWhenCharging,
      );
    }
  }

  Future<void> _confirmResync(BuildContext context, Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resync All Articles'),
        content: const Text(
          'This will delete all locally stored articles and reset sync markers. '
          'Feeds and settings stay intact. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Resync'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isResyncing = true);
    try {
      await DatabaseHelper.instance.clearArticlesAndSyncState();

      final rssService = ref.read(localRssServiceProvider);
      await rssService.sync(account.id!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resync started')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting resync: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isResyncing = false);
      }
    }
  }

  Future<void> _showSyncLog(BuildContext context) async {
    if (!context.mounted) return;
    
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Sync Log',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: () async {
                            setState(() {});
                          },
                          tooltip: 'Refresh',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: FutureBuilder<List<SyncLogEntry>>(
                        future: SyncLogService().getLogEntries(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          
                          final entries = snapshot.data ?? [];
                          
                          if (entries.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'No sync history yet',
                                style: TextStyle(fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              final timeAgo = _formatTimeAgo(entry.timestamp);
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                leading: Icon(
                                  entry.success ? Icons.check_circle : Icons.error,
                                  color: entry.success ? Colors.green : Colors.red,
                                  size: 18,
                                ),
                                title: Text(
                                  '${entry.type.toUpperCase()} - $timeAgo',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                subtitle: Text(
                                  entry.success
                                      ? '${entry.articlesSynced ?? 0} articles synced'
                                      : 'Error: ${entry.error ?? "Unknown"}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FutureBuilder<List<SyncLogEntry>>(
                          future: SyncLogService().getLogEntries(),
                          builder: (context, snapshot) {
                            final entries = snapshot.data ?? [];
                            if (entries.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return TextButton(
                              onPressed: () async {
                                await SyncLogService().clearLogs();
                                if (context.mounted) {
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Sync log cleared')),
                                  );
                                }
                              },
                              child: const Text('Clear Log', style: TextStyle(fontSize: 12)),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
}

