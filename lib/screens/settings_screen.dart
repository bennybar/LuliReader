import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../services/account_service.dart';
import '../models/account.dart';
import 'opml_import_export_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {

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
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Max Past Days to Sync'),
                  subtitle: Text('${account.maxPastDays} days'),
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
    final controller = TextEditingController(text: account.syncInterval.toString());
    final interval = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Interval'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Minutes',
            hintText: 'Enter sync interval in minutes',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value > 0) {
                Navigator.of(context).pop(value);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (interval != null && interval != account.syncInterval) {
      await _updateAccountSetting('syncInterval', interval);
    }
  }
}

