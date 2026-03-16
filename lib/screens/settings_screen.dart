import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_provider.dart';
import '../database/database_helper.dart';
import '../background/background_sync.dart';
import '../services/shared_preferences_service.dart';
import '../models/account.dart';
import 'opml_import_export_screen.dart';
import 'sync_log_screen.dart';
import 'startup_screen.dart';
import 'blacklist_screen.dart';
import '../theme/app_symbols.dart';
import '../widgets/settings_components.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isResyncing = false;
  double _articleFontScale = 1.0;
  double _titleFontScale = 1.0;
  double _articlePadding = 16.0;
  double _articleListFontScale = 1.0;
  bool _openLinksExternally = false;
  int _keepReadItemsDays = 3;
  int _feedTimeoutSeconds = 10;
  bool _showPreviewText = true;
  bool _showHeroImage = true; // simple on/off
  bool _backgroundSyncEnabled = true; // controls background worker
  final SharedPreferencesService _prefs = SharedPreferencesService();

  @override
  void initState() {
    super.initState();
    _loadReadingPrefs();
  }

  Future<void> _loadReadingPrefs() async {
    await _prefs.init();
    final font = await _prefs.getDouble('articleFontScale') ?? 1.0;
    final titleFont = await _prefs.getDouble('titleFontScale') ?? 1.0;
    final pad = await _prefs.getDouble('articlePadding') ?? 16.0;
    final listFont = await _prefs.getDouble('articleListFontScale') ?? 1.0;
    final openLinksExternally = await _prefs.getBool('openLinksExternally') ?? false;
    final keepReadItemsDays = await _prefs.getInt('keepReadItemsDays') ?? 3;
    final feedTimeoutSeconds = await _prefs.getInt('feedTimeoutSeconds') ?? 10;
    final showPreviewText = await _prefs.getBool('showPreviewText') ?? true;
    final backgroundSyncEnabled = await _prefs.getBool('backgroundSyncEnabled') ?? true;
    // New: showHeroImage on/off. Backward compatibility: map old heroImagePosition.
    final legacyHeroPosition = await _prefs.getString('heroImagePosition');
    final showHeroImage = await _prefs.getBool('showHeroImage') ??
        (legacyHeroPosition == 'none'
            ? false
            : true); // any non-none legacy value means on
    if (mounted) {
      setState(() {
        _articleFontScale = font;
        _titleFontScale = titleFont;
        _articlePadding = pad;
        _articleListFontScale = listFont;
        _openLinksExternally = openLinksExternally;
        _keepReadItemsDays = keepReadItemsDays;
        _feedTimeoutSeconds = feedTimeoutSeconds;
        _showPreviewText = showPreviewText;
        _showHeroImage = showHeroImage;
        _backgroundSyncEnabled = backgroundSyncEnabled;
      });
    }
  }

  Future<void> _saveReadingPref(String key, double value) async {
    await _prefs.init();
    await _prefs.setDouble(key, value);
  }

  Future<void> _saveBoolPref(String key, bool value) async {
    await _prefs.init();
    await _prefs.setBool(key, value);
  }

  Future<void> _saveIntPref(String key, int value) async {
    await _prefs.init();
    await _prefs.setInt(key, value);
  }

  double _titleFontPx(BuildContext context) =>
      (Theme.of(context).textTheme.headlineSmall?.fontSize ?? 24.0) * _titleFontScale;

  double _articleFontPx(BuildContext context) =>
      (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16.0) * _articleFontScale;

  Widget _buildScaleSlider({
    required BuildContext context,
    required String title,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
              SettingsValueChip(label: valueLabel),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  String _themeSubtitle(WidgetRef ref) {
    final mode = ref.watch(themeModeNotifierProvider);
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      default:
        return 'System';
    }
  }

  Future<void> _showThemeDialog(BuildContext context) async {
    final mode = ref.read(themeModeNotifierProvider);
    final selected = await _showChoiceSheet<ThemeMode>(
      context: context,
      title: 'Theme',
      currentValue: mode,
      options: const [
        _SettingsChoiceOption(
          value: ThemeMode.system,
          title: 'Use system setting',
          subtitle: 'Match your device theme automatically',
        ),
        _SettingsChoiceOption(
          value: ThemeMode.light,
          title: 'Light',
        ),
        _SettingsChoiceOption(
          value: ThemeMode.dark,
          title: 'Dark',
        ),
      ],
    );

    if (selected != null) {
      await ref.read(themeModeNotifierProvider.notifier).setThemeMode(selected);
      if (mounted) setState(() {});
    }
  }

  Future<bool?> _showOpenLinksDialog(BuildContext context) async {
    final selected = await _showChoiceSheet<bool>(
      context: context,
      title: 'Open links in',
      currentValue: _openLinksExternally,
      options: const [
        _SettingsChoiceOption(
          value: false,
          title: 'In-app browser',
          subtitle: 'Keep reading inside the app',
        ),
        _SettingsChoiceOption(
          value: true,
          title: 'External browser',
          subtitle: 'Open links in your default browser',
        ),
      ],
    );

    if (selected != null) {
      await _saveBoolPref('openLinksExternally', selected);
      if (mounted) {
        setState(() {
          _openLinksExternally = selected;
        });
      }
    }
    return selected;
  }

  Future<int?> _showKeepReadItemsDialog(BuildContext context) async {
    const options = [1, 3, 5, 7, 10, 30];
    final selected = await _showChoiceSheet<int>(
      context: context,
      title: 'Auto-delete read articles',
      currentValue: _keepReadItemsDays,
      options: options
          .map(
            (days) => _SettingsChoiceOption<int>(
              value: days,
              title: '$days ${days == 1 ? 'day' : 'days'}',
              subtitle: 'Delete read articles older than this',
            ),
          )
          .toList(),
    );

    if (selected != null) {
      await _saveIntPref('keepReadItemsDays', selected);
      if (mounted) {
        setState(() {
          _keepReadItemsDays = selected;
        });
      }
    }
    return selected;
  }

  Future<int?> _showFeedTimeoutDialog(BuildContext context) async {
    const options = [5, 10, 15, 30, 60];
    final selected = await _showChoiceSheet<int>(
      context: context,
      title: 'Network timeout',
      currentValue: _feedTimeoutSeconds,
      options: options
          .map(
            (seconds) => _SettingsChoiceOption<int>(
              value: seconds,
              title: '$seconds seconds',
              subtitle: 'Stop waiting for a feed after this long',
            ),
          )
          .toList(),
    );

    if (selected != null) {
      await _saveIntPref('feedTimeoutSeconds', selected);
      if (mounted) {
        setState(() {
          _feedTimeoutSeconds = selected;
        });
      }
    }
    return selected;
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
      await _applyBackgroundSyncSetting(updatedAccount);
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

  Future<void> _applyBackgroundSyncSetting(Account account) async {
    await _prefs.init();
    final enabled = await _prefs.getBool('backgroundSyncEnabled') ?? true;
    if (!enabled || account.syncInterval <= 0) {
      await cancelBackgroundSync();
      return;
    }
    await registerBackgroundSync(
      account.syncInterval,
      requiresCharging: account.syncOnlyWhenCharging,
      requiresWiFi: account.syncOnlyOnWiFi,
    );
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SettingsSectionHeader(
                title: 'Account',
                subtitle: 'This device is currently using one reader account',
              ),
              SettingsGroup(
                children: [
                  SettingsNavTile(
                    title: 'Current account',
                    subtitle: account.name,
                    leading: const Icon(AppSymbols.account_circle),
                    trailing: const SettingsValueChip(label: 'Active', highlight: true),
                  ),
                  SettingsNavTile(
                    title: 'Start screen',
                    subtitle: _defaultScreenSubtitle(account.defaultScreen),
                    leading: const Icon(AppSymbols.home),
                    onTap: () => _showDefaultScreenDialog(context, account),
                  ),
                ],
              ),
              SettingsSectionHeader(
                title: 'Appearance',
                subtitle: 'Theme, list density, thumbnails, and preview text',
              ),
              SettingsGroup(
                children: [
                  SettingsNavTile(
                    title: 'Theme',
                    subtitle: _themeSubtitle(ref),
                    leading: const Icon(AppSymbols.brightness_6),
                    onTap: () => _showThemeDialog(context),
                  ),
                  SettingsNavTile(
                    title: 'Reading & layout',
                    subtitle: 'Adjust typography, thumbnails, preview text, and list density',
                    onTap: () => _openSubPage(
                      _AppearanceSettingsPage(
                        listFontScale: _articleListFontScale,
                        showHeroImage: _showHeroImage,
                        showPreviewText: _showPreviewText,
                        buildScaleSlider: _buildScaleSlider,
                        onListFontChanged: (value) async {
                          setState(() => _articleListFontScale = value);
                          await _saveReadingPref('articleListFontScale', value);
                        },
                        onResetListFont: () async {
                          setState(() => _articleListFontScale = 1.0);
                          await _saveReadingPref('articleListFontScale', 1.0);
                        },
                        onShowHeroImageChanged: (value) async {
                          await _saveBoolPref('showHeroImage', value);
                          if (!mounted) return;
                          setState(() => _showHeroImage = value);
                        },
                        onShowPreviewTextChanged: (value) async {
                          await _saveBoolPref('showPreviewText', value);
                          if (!mounted) return;
                          setState(() => _showPreviewText = value);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              SettingsSectionHeader(
                title: 'Reading',
                subtitle: 'Reader comfort, article content, and link behavior',
              ),
              SettingsGroup(
                children: [
                  SettingsNavTile(
                    title: 'Reader options',
                    subtitle: 'Live preview, text size, article padding, link handling, and cleanup',
                    leading: const Icon(AppSymbols.article_outlined),
                    onTap: () => _openSubPage(
                      _ReadingSettingsPage(
                        titleFontScale: _titleFontScale,
                        articleFontScale: _articleFontScale,
                        articlePadding: _articlePadding,
                        titleFontPx: _titleFontPx(context),
                        articleFontPx: _articleFontPx(context),
                        openLinksExternally: _openLinksExternally,
                        keepReadItemsDays: _keepReadItemsDays,
                        feedTimeoutSeconds: _feedTimeoutSeconds,
                        fullContentEnabled: account.isFullContent,
                        buildScaleSlider: _buildScaleSlider,
                        onTitleFontChanged: (value) async {
                          setState(() => _titleFontScale = value);
                          await _saveReadingPref('titleFontScale', value);
                        },
                        onArticleFontChanged: (value) async {
                          setState(() => _articleFontScale = value);
                          await _saveReadingPref('articleFontScale', value);
                        },
                        onArticlePaddingChanged: (value) async {
                          setState(() => _articlePadding = value);
                          await _saveReadingPref('articlePadding', value);
                        },
                        onResetReading: () async {
                          setState(() {
                            _titleFontScale = 1.0;
                            _articleFontScale = 1.0;
                            _articlePadding = 16.0;
                          });
                          await _saveReadingPref('titleFontScale', 1.0);
                          await _saveReadingPref('articleFontScale', 1.0);
                          await _saveReadingPref('articlePadding', 16.0);
                        },
                        onFullContentChanged: (value) =>
                            _updateAccountSetting('isFullContent', value),
                        onOpenLinksTap: () => _showOpenLinksDialog(context),
                        onKeepReadItemsTap: () => _showKeepReadItemsDialog(context),
                        onFeedTimeoutTap: () => _showFeedTimeoutDialog(context),
                      ),
                    ),
                  ),
                ],
              ),
              SettingsSectionHeader(
                title: 'Sync',
                subtitle: 'Schedules, network limits, and background behavior',
              ),
              SettingsGroup(
                children: [
                  SettingsNavTile(
                    title: 'Sync & network',
                    subtitle: _syncSummary(account),
                    leading: const Icon(AppSymbols.sync),
                    onTap: () => _openSubPage(
                      _SyncSettingsPage(
                        account: account,
                        backgroundSyncEnabled: _backgroundSyncEnabled,
                        onSyncIntervalTap: () => _showSyncIntervalDialog(context, account),
                        onBackgroundSyncChanged: (value) async {
                          await _prefs.init();
                          await _prefs.setBool('backgroundSyncEnabled', value);
                          if (!value) {
                            await cancelBackgroundSync();
                          } else {
                            await _applyBackgroundSyncSetting(account);
                          }
                          if (!mounted) return;
                          setState(() => _backgroundSyncEnabled = value);
                        },
                        onSyncOnStartChanged: (value) =>
                            _updateAccountSetting('syncOnStart', value),
                        onMaxPastDaysTap: () => _showMaxPastDaysDialog(context, account),
                        onSyncOnlyWifiChanged: (value) =>
                            _updateAccountSetting('syncOnlyOnWiFi', value),
                        onSyncOnlyWhenChargingChanged: (value) =>
                            _updateAccountSetting('syncOnlyWhenCharging', value),
                        onSyncHistoryTap: () => _showSyncLog(context),
                      ),
                    ),
                  ),
                  SettingsNavTile(
                    title: 'Sync history',
                    subtitle: 'View recent manual and background sync activity',
                    leading: const Icon(AppSymbols.history),
                    onTap: () => _showSyncLog(context),
                  ),
                ],
              ),
              SettingsSectionHeader(
                title: 'Gestures',
                subtitle: 'Choose what article swipes do in the list',
              ),
              SettingsGroup(
                children: [
                  SettingsNavTile(
                    title: 'Article swipe actions',
                    subtitle:
                        'Right: ${_getSwipeActionDescription(account.swipeStartAction)} • Left: ${_getSwipeActionDescription(account.swipeEndAction)}',
                    leading: const Icon(AppSymbols.swipe_right),
                    onTap: () => _openSubPage(
                      _GestureSettingsPage(
                        swipeRightDescription:
                            _getSwipeActionDescription(account.swipeStartAction),
                        swipeLeftDescription:
                            _getSwipeActionDescription(account.swipeEndAction),
                        onSwipeRightTap: () =>
                            _showSwipeActionDialog(context, account, true),
                        onSwipeLeftTap: () =>
                            _showSwipeActionDialog(context, account, false),
                      ),
                    ),
                  ),
                ],
              ),
              SettingsSectionHeader(
                title: 'Content Filtering',
                subtitle: 'Hide articles you never want to see',
              ),
              SettingsGroup(
                children: [
                  SettingsNavTile(
                    title: 'Blocked titles',
                    subtitle: 'Hide articles that match blacklist keywords',
                    leading: const Icon(AppSymbols.block),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BlacklistScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              SettingsSectionHeader(
                title: 'Import / Export',
                subtitle: 'Move subscriptions in or out with OPML',
              ),
              SettingsGroup(
                children: [
                  SettingsNavTile(
                    title: 'OPML import / export',
                    subtitle: 'Import feeds or back them up to an OPML file',
                    leading: const Icon(AppSymbols.import_export),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const OpmlImportExportScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              SettingsSectionHeader(
                title: 'Help & About',
                subtitle: 'Support links and app details',
              ),
              SettingsGroup(
                children: [
                  SettingsNavTile(
                    title: 'Help & support',
                    subtitle: 'Report issues or get help',
                    leading: const Icon(AppSymbols.help_outline),
                    onTap: _openHelp,
                  ),
                  SettingsNavTile(
                    title: 'About',
                    subtitle: 'Luli Reader v1.1.80',
                    leading: const Icon(AppSymbols.info),
                    onTap: _showAbout,
                  ),
                ],
              ),
              SettingsSectionHeader(
                title: 'Storage & Data',
                subtitle: 'Local article storage and data refresh tools',
              ),
              SettingsGroup(
                children: [
                  SettingsNavTile(
                    title: 'Re-download articles',
                    subtitle: 'Clear local article data, then fetch everything again',
                    leading: const Icon(AppSymbols.restart_alt),
                    trailing: _isResyncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: _isResyncing ? null : () => _confirmResync(context, account),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SettingsDangerTile(
                title: 'Clear downloaded articles',
                subtitle:
                    'Delete stored articles and reset sync markers. Feeds and account settings stay intact.',
                leading: const Icon(AppSymbols.delete_sweep),
                onTap: _confirmClearArticles,
              ),
              SettingsSectionHeader(
                title: 'Danger Zone',
                subtitle: 'This permanently removes the current account from this device',
              ),
              SettingsDangerTile(
                title: 'Delete account',
                subtitle: 'Remove this account, all feeds, and all downloaded articles from this device.',
                leading: const Icon(AppSymbols.delete_forever),
                severe: true,
                onTap: () => _confirmDeleteAccount(account),
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
        return 'Mark read / unread';
      case 2:
        return 'Star / unstar';
      default:
        return 'None';
    }
  }

  Future<int?> _showMaxPastDaysDialog(BuildContext context, Account account) async {
    const options = [3, 5, 10, 30, 90];
    final selected = await _showChoiceSheet<int>(
      context: context,
      title: 'How far back to sync',
      currentValue: account.maxPastDays,
      options: options
          .map(
            (days) => _SettingsChoiceOption<int>(
              value: days,
              title: '$days days',
              subtitle: 'Skip older items when syncing feeds',
            ),
          )
          .toList(),
    );

    if (selected != null) {
      await _updateAccountSetting('maxPastDays', selected);
    }
    return selected;
  }

  Future<void> _confirmDeleteAccount(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
          'This will remove "${account.name}" and all its feeds and articles from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final accountService = ref.read(accountServiceProvider);
      await accountService.delete(account.id!);
      await cancelBackgroundSync();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const StartupScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting account: $e')),
        );
      }
    }
  }

  Future<void> _confirmClearArticles() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear downloaded articles?'),
        content: const Text(
          'This deletes every stored article and resets sync markers for all accounts. '
          'Feeds and accounts remain. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear articles'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await DatabaseHelper.instance.clearArticlesAndSyncState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All articles cleared; next sync will re-download.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing articles: $e')),
        );
      }
    }
  }

  Future<int?> _showSwipeActionDialog(BuildContext context, Account account, bool isStart) async {
    final currentValue = isStart ? account.swipeStartAction : account.swipeEndAction;
    final action = await _showChoiceSheet<int>(
      context: context,
      title: isStart ? 'Swipe right action' : 'Swipe left action',
      currentValue: currentValue,
      options: const [
        _SettingsChoiceOption(
          value: 0,
          title: 'None',
          subtitle: 'Do nothing when swiping',
        ),
        _SettingsChoiceOption(
          value: 1,
          title: 'Mark read / unread',
          subtitle: 'Toggle the read state of the article',
        ),
        _SettingsChoiceOption(
          value: 2,
          title: 'Star / unstar',
          subtitle: 'Toggle the saved state of the article',
        ),
      ],
    );

    if (action != null) {
      await _updateAccountSetting(
        isStart ? 'swipeStartAction' : 'swipeEndAction',
        action,
      );
    }
    return action;
  }

  Future<int?> _showDefaultScreenDialog(BuildContext context, Account account) async {
    final screen = await _showChoiceSheet<int>(
      context: context,
      title: 'Start screen',
      currentValue: account.defaultScreen,
      options: const [
        _SettingsChoiceOption(
          value: 0,
          title: 'Feeds',
          subtitle: 'Open the feed and folder view first',
        ),
        _SettingsChoiceOption(
          value: 1,
          title: 'Articles',
          subtitle: 'Open the article stream first',
        ),
      ],
    );

    if (screen != null) {
      await _updateAccountSetting('defaultScreen', screen);
    }
    return screen;
  }

  Future<int?> _showSyncIntervalDialog(BuildContext context, Account account) async {
    const options = [15, 30, 60, 120];
    final selected = await _showChoiceSheet<int>(
      context: context,
      title: 'Sync interval',
      currentValue: account.syncInterval,
      options: options
          .map(
            (mins) => _SettingsChoiceOption<int>(
              value: mins,
              title: '$mins minutes',
              subtitle: 'Run automatic sync on this schedule',
            ),
          )
          .toList(),
    );

    if (selected != null && selected != account.syncInterval) {
      await _updateAccountSetting('syncInterval', selected);
      await registerBackgroundSync(
        selected,
        requiresCharging: account.syncOnlyWhenCharging,
        requiresWiFi: account.syncOnlyOnWiFi,
      );
    }
    return selected;
  }

  Future<void> _confirmResync(BuildContext context, Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-download articles?'),
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
            child: const Text('Re-download'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isResyncing = true);
    try {
      // Clear articles and sync state
      await DatabaseHelper.instance.clearArticlesAndSyncState();
      
      // Also clear read_history for this account to allow articles to be re-inserted
      final db = await DatabaseHelper.instance.database;
      await db.delete(
        'read_history',
        where: 'accountId = ?',
        whereArgs: [account.id!],
      );

      final syncCoordinator = ref.read(syncCoordinatorProvider);
      await syncCoordinator.syncAccount(account.id!);

      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(content: Text('Re-download started')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Error starting resync: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isResyncing = false);
      }
    }
  }

  Future<void> _showSyncLog(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SyncLogScreen(),
      ),
    );
  }

  Future<void> _openSubPage(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  String _defaultScreenSubtitle(int screen) {
    return screen == 0
        ? 'Open on Feeds first'
        : 'Open on Articles first';
  }

  String _syncSummary(Account account) {
    return '${account.syncInterval} min interval'
        ' • ${_backgroundSyncEnabled ? 'Background on' : 'Background off'}';
  }

  Future<void> _openHelp() async {
    final uri = Uri.parse('https://github.com/bennybar/LuliReader/issues');
    if (!await canLaunchUrl(uri)) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open help page: $e')),
      );
    }
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Luli Reader',
      applicationVersion: '1.1.80',
      applicationIcon: const Icon(AppSymbols.article_outlined),
    );
  }

  Future<T?> _showChoiceSheet<T>({
    required BuildContext context,
    required String title,
    required T currentValue,
    required List<_SettingsChoiceOption<T>> options,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              SettingsGroup(
                children: [
                  for (final option in options)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      title: Text(
                        option.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      subtitle: option.subtitle == null ? null : Text(option.subtitle!),
                      trailing: option.value == currentValue
                          ? const Icon(AppSymbols.check)
                          : null,
                      onTap: () => Navigator.of(context).pop(option.value),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

typedef _SliderBuilder = Widget Function({
  required BuildContext context,
  required String title,
  required String valueLabel,
  required double value,
  required double min,
  required double max,
  required int divisions,
  required ValueChanged<double> onChanged,
  String? subtitle,
});

class _SettingsChoiceOption<T> {
  const _SettingsChoiceOption({
    required this.value,
    required this.title,
    this.subtitle,
  });

  final T value;
  final String title;
  final String? subtitle;
}

class _AppearanceSettingsPage extends StatefulWidget {
  const _AppearanceSettingsPage({
    required this.listFontScale,
    required this.showHeroImage,
    required this.showPreviewText,
    required this.buildScaleSlider,
    required this.onListFontChanged,
    required this.onResetListFont,
    required this.onShowHeroImageChanged,
    required this.onShowPreviewTextChanged,
  });

  final double listFontScale;
  final bool showHeroImage;
  final bool showPreviewText;
  final _SliderBuilder buildScaleSlider;
  final Future<void> Function(double) onListFontChanged;
  final Future<void> Function() onResetListFont;
  final Future<void> Function(bool) onShowHeroImageChanged;
  final Future<void> Function(bool) onShowPreviewTextChanged;

  @override
  State<_AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<_AppearanceSettingsPage> {
  late double _listFontScale;
  late bool _showHeroImage;
  late bool _showPreviewText;

  @override
  void initState() {
    super.initState();
    _listFontScale = widget.listFontScale;
    _showHeroImage = widget.showHeroImage;
    _showPreviewText = widget.showPreviewText;
  }

  @override
  Widget build(BuildContext context) {
    final baseFont = Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16.0;
    final listFontPx = baseFont * _listFontScale;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SettingsSectionHeader(
            title: 'Article list',
            subtitle: 'Tune density and scanning speed in the article feed',
            action: TextButton(
              onPressed: () async {
                setState(() => _listFontScale = 1.0);
                await widget.onResetListFont();
              },
              child: const Text('Reset'),
            ),
          ),
          SettingsGroup(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: widget.buildScaleSlider(
                  context: context,
                  title: 'List text size',
                  subtitle: 'Optimized for fast article scanning',
                  valueLabel: '${listFontPx.toStringAsFixed(0)} px',
                  value: _listFontScale,
                  min: 0.85,
                  max: 1.4,
                  divisions: 11,
                  onChanged: (value) async {
                    setState(() => _listFontScale = value);
                    await widget.onListFontChanged(value);
                  },
                ),
              ),
            ],
          ),
          SettingsSectionHeader(
            title: 'Article cards',
            subtitle: 'Control how much visual detail appears in lists',
          ),
          SettingsGroup(
            children: [
              SettingsSwitchTile(
                title: 'Show thumbnails',
                subtitle: 'Display article images in lists',
                leading: const Icon(AppSymbols.image),
                value: _showHeroImage,
                onChanged: (value) async {
                  setState(() => _showHeroImage = value);
                  await widget.onShowHeroImageChanged(value);
                },
              ),
              SettingsSwitchTile(
                title: 'Show article preview',
                subtitle: 'Display a short text preview under each title',
                value: _showPreviewText,
                onChanged: (value) async {
                  setState(() => _showPreviewText = value);
                  await widget.onShowPreviewTextChanged(value);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadingSettingsPage extends StatefulWidget {
  const _ReadingSettingsPage({
    required this.titleFontScale,
    required this.articleFontScale,
    required this.articlePadding,
    required this.titleFontPx,
    required this.articleFontPx,
    required this.openLinksExternally,
    required this.keepReadItemsDays,
    required this.feedTimeoutSeconds,
    required this.fullContentEnabled,
    required this.buildScaleSlider,
    required this.onTitleFontChanged,
    required this.onArticleFontChanged,
    required this.onArticlePaddingChanged,
    required this.onResetReading,
    required this.onFullContentChanged,
    required this.onOpenLinksTap,
    required this.onKeepReadItemsTap,
    required this.onFeedTimeoutTap,
  });

  final double titleFontScale;
  final double articleFontScale;
  final double articlePadding;
  final double titleFontPx;
  final double articleFontPx;
  final bool openLinksExternally;
  final int keepReadItemsDays;
  final int feedTimeoutSeconds;
  final bool fullContentEnabled;
  final _SliderBuilder buildScaleSlider;
  final Future<void> Function(double) onTitleFontChanged;
  final Future<void> Function(double) onArticleFontChanged;
  final Future<void> Function(double) onArticlePaddingChanged;
  final Future<void> Function() onResetReading;
  final Future<void> Function(bool) onFullContentChanged;
  final Future<bool?> Function() onOpenLinksTap;
  final Future<int?> Function() onKeepReadItemsTap;
  final Future<int?> Function() onFeedTimeoutTap;

  @override
  State<_ReadingSettingsPage> createState() => _ReadingSettingsPageState();
}

class _ReadingSettingsPageState extends State<_ReadingSettingsPage> {
  late double _titleFontScale;
  late double _articleFontScale;
  late double _articlePadding;
  late bool _openLinksExternally;
  late int _keepReadItemsDays;
  late int _feedTimeoutSeconds;
  late bool _fullContentEnabled;

  @override
  void initState() {
    super.initState();
    _titleFontScale = widget.titleFontScale;
    _articleFontScale = widget.articleFontScale;
    _articlePadding = widget.articlePadding;
    _openLinksExternally = widget.openLinksExternally;
    _keepReadItemsDays = widget.keepReadItemsDays;
    _feedTimeoutSeconds = widget.feedTimeoutSeconds;
    _fullContentEnabled = widget.fullContentEnabled;
  }

  Widget _buildLocalPreviewCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseTitle = Theme.of(context).textTheme.headlineSmall?.fontSize ?? 24.0;
    final baseBody = Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16.0;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_articlePadding.clamp(12.0, 24.0)),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview article title',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: baseTitle * _titleFontScale,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'Feed name  •  5 min ago',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          Text(
            'This preview updates live so you can tune reading comfort before leaving settings.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: baseBody * _articleFontScale,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTitle = Theme.of(context).textTheme.headlineSmall?.fontSize ?? 24.0;
    final baseBody = Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16.0;
    final titleFontPx = baseTitle * _titleFontScale;
    final articleFontPx = baseBody * _articleFontScale;
    final dayLabel = _keepReadItemsDays == 1 ? 'day' : 'days';
    return Scaffold(
      appBar: AppBar(title: const Text('Reading')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SettingsSectionHeader(
            title: 'Live preview',
            subtitle: 'See your reading settings update instantly',
            action: TextButton(
              onPressed: () async {
                setState(() {
                  _titleFontScale = 1.0;
                  _articleFontScale = 1.0;
                  _articlePadding = 16.0;
                });
                await widget.onResetReading();
              },
              child: const Text('Reset'),
            ),
          ),
          SettingsGroup(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: _buildLocalPreviewCard(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Column(
                  children: [
                    widget.buildScaleSlider(
                      context: context,
                      title: 'Title size',
                      valueLabel: '${titleFontPx.toStringAsFixed(0)} px',
                      value: _titleFontScale,
                      min: 0.8,
                      max: 1.8,
                      divisions: 10,
                      onChanged: (value) async {
                        setState(() => _titleFontScale = value);
                        await widget.onTitleFontChanged(value);
                      },
                    ),
                    widget.buildScaleSlider(
                      context: context,
                      title: 'Article text size',
                      valueLabel: '${articleFontPx.toStringAsFixed(0)} px',
                      value: _articleFontScale,
                      min: 0.85,
                      max: 1.7,
                      divisions: 17,
                      onChanged: (value) async {
                        setState(() => _articleFontScale = value);
                        await widget.onArticleFontChanged(value);
                      },
                    ),
                    widget.buildScaleSlider(
                      context: context,
                      title: 'Reading padding',
                      subtitle: 'Controls the side margins in the reader',
                      valueLabel: '${_articlePadding.toStringAsFixed(0)} px',
                      value: _articlePadding,
                      min: 8,
                      max: 32,
                      divisions: 24,
                      onChanged: (value) async {
                        setState(() => _articlePadding = value);
                        await widget.onArticlePaddingChanged(value);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          SettingsSectionHeader(
            title: 'Article behavior',
            subtitle: 'Control how articles open, download, and clean up',
          ),
          SettingsGroup(
            children: [
              SettingsSwitchTile(
                title: 'Download full article text',
                subtitle:
                    'Fetch complete article content in the background when feeds sync',
                leading: const Icon(AppSymbols.article_outlined),
                value: _fullContentEnabled,
                onChanged: (value) async {
                  setState(() => _fullContentEnabled = value);
                  await widget.onFullContentChanged(value);
                },
              ),
              SettingsNavTile(
                title: 'Open links in',
                subtitle: _openLinksExternally ? 'External browser' : 'In-app browser',
                leading: const Icon(AppSymbols.open_in_browser),
                onTap: () async {
                  final selected = await widget.onOpenLinksTap();
                  if (selected != null && mounted) {
                    setState(() => _openLinksExternally = selected);
                  }
                },
              ),
              SettingsNavTile(
                title: 'Auto-delete read articles',
                subtitle: 'Delete read articles after $_keepReadItemsDays $dayLabel',
                onTap: () async {
                  final selected = await widget.onKeepReadItemsTap();
                  if (selected != null && mounted) {
                    setState(() => _keepReadItemsDays = selected);
                  }
                },
              ),
              SettingsNavTile(
                title: 'Network timeout',
                subtitle: 'Stop loading a feed after $_feedTimeoutSeconds seconds',
                leading: const Icon(AppSymbols.timer),
                onTap: () async {
                  final selected = await widget.onFeedTimeoutTap();
                  if (selected != null && mounted) {
                    setState(() => _feedTimeoutSeconds = selected);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncSettingsPage extends StatefulWidget {
  const _SyncSettingsPage({
    required this.account,
    required this.backgroundSyncEnabled,
    required this.onSyncIntervalTap,
    required this.onBackgroundSyncChanged,
    required this.onSyncOnStartChanged,
    required this.onMaxPastDaysTap,
    required this.onSyncOnlyWifiChanged,
    required this.onSyncOnlyWhenChargingChanged,
    required this.onSyncHistoryTap,
  });

  final Account account;
  final bool backgroundSyncEnabled;
  final Future<int?> Function() onSyncIntervalTap;
  final Future<void> Function(bool) onBackgroundSyncChanged;
  final Future<void> Function(bool) onSyncOnStartChanged;
  final Future<int?> Function() onMaxPastDaysTap;
  final Future<void> Function(bool) onSyncOnlyWifiChanged;
  final Future<void> Function(bool) onSyncOnlyWhenChargingChanged;
  final VoidCallback onSyncHistoryTap;

  @override
  State<_SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<_SyncSettingsPage> {
  late int _syncInterval;
  late bool _backgroundSyncEnabled;
  late bool _syncOnStart;
  late int _maxPastDays;
  late bool _syncOnlyOnWiFi;
  late bool _syncOnlyWhenCharging;

  @override
  void initState() {
    super.initState();
    _syncInterval = widget.account.syncInterval;
    _backgroundSyncEnabled = widget.backgroundSyncEnabled;
    _syncOnStart = widget.account.syncOnStart;
    _maxPastDays = widget.account.maxPastDays;
    _syncOnlyOnWiFi = widget.account.syncOnlyOnWiFi;
    _syncOnlyWhenCharging = widget.account.syncOnlyWhenCharging;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SettingsSectionHeader(
            title: 'Schedule',
            subtitle: 'Automatic syncing and app startup behavior',
          ),
          SettingsGroup(
            children: [
              SettingsNavTile(
                title: 'Sync interval',
                subtitle: '$_syncInterval minutes',
                leading: const Icon(AppSymbols.sync),
                onTap: () async {
                  final selected = await widget.onSyncIntervalTap();
                  if (selected != null && mounted) {
                    setState(() => _syncInterval = selected);
                  }
                },
              ),
              SettingsSwitchTile(
                title: 'Background sync',
                subtitle: 'Allow sync to run even when the app is not open',
                leading: const Icon(AppSymbols.sync_lock),
                value: _backgroundSyncEnabled,
                onChanged: (value) async {
                  setState(() => _backgroundSyncEnabled = value);
                  await widget.onBackgroundSyncChanged(value);
                },
              ),
              SettingsSwitchTile(
                title: 'Sync on app start',
                subtitle: 'Refresh feeds automatically when the app opens',
                leading: const Icon(AppSymbols.play_circle_outline),
                value: _syncOnStart,
                onChanged: (value) async {
                  setState(() => _syncOnStart = value);
                  await widget.onSyncOnStartChanged(value);
                },
              ),
            ],
          ),
          SettingsSectionHeader(
            title: 'Network & battery',
            subtitle: 'Limit syncing based on time, Wi-Fi, and charging',
          ),
          SettingsGroup(
            children: [
              SettingsNavTile(
                title: 'How far back to sync',
                subtitle: '$_maxPastDays days',
                onTap: () async {
                  final selected = await widget.onMaxPastDaysTap();
                  if (selected != null && mounted) {
                    setState(() => _maxPastDays = selected);
                  }
                },
              ),
              SettingsSwitchTile(
                title: 'Sync only on Wi-Fi',
                subtitle: 'Avoid syncing on mobile data',
                leading: const Icon(AppSymbols.wifi),
                value: _syncOnlyOnWiFi,
                onChanged: (value) async {
                  setState(() => _syncOnlyOnWiFi = value);
                  await widget.onSyncOnlyWifiChanged(value);
                },
              ),
              SettingsSwitchTile(
                title: 'Sync only when charging',
                subtitle: 'Reduce battery use during automatic sync',
                leading: const Icon(AppSymbols.battery_charging_full),
                value: _syncOnlyWhenCharging,
                onChanged: (value) async {
                  setState(() => _syncOnlyWhenCharging = value);
                  await widget.onSyncOnlyWhenChargingChanged(value);
                },
              ),
            ],
          ),
          SettingsSectionHeader(
            title: 'History',
            subtitle: 'Review recent sync activity',
          ),
          SettingsGroup(
            children: [
              SettingsNavTile(
                title: 'Sync history',
                subtitle: 'View recent manual and background sync activity',
                leading: const Icon(AppSymbols.history),
                onTap: widget.onSyncHistoryTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GestureSettingsPage extends StatefulWidget {
  const _GestureSettingsPage({
    required this.swipeRightDescription,
    required this.swipeLeftDescription,
    required this.onSwipeRightTap,
    required this.onSwipeLeftTap,
  });

  final String swipeRightDescription;
  final String swipeLeftDescription;
  final Future<int?> Function() onSwipeRightTap;
  final Future<int?> Function() onSwipeLeftTap;

  @override
  State<_GestureSettingsPage> createState() => _GestureSettingsPageState();
}

class _GestureSettingsPageState extends State<_GestureSettingsPage> {
  late String _swipeRightDescription;
  late String _swipeLeftDescription;

  @override
  void initState() {
    super.initState();
    _swipeRightDescription = widget.swipeRightDescription;
    _swipeLeftDescription = widget.swipeLeftDescription;
  }

  String _describe(int action) {
    switch (action) {
      case 1:
        return 'Mark read / unread';
      case 2:
        return 'Star / unstar';
      default:
        return 'None';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestures')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SettingsSectionHeader(
            title: 'Article list gestures',
            subtitle: 'Choose what happens when you swipe an article',
          ),
          SettingsGroup(
            children: [
              SettingsNavTile(
                title: 'Swipe right action',
                subtitle: _swipeRightDescription,
                leading: const Icon(AppSymbols.swipe_right),
                onTap: () async {
                  final selected = await widget.onSwipeRightTap();
                  if (selected != null && mounted) {
                    setState(() => _swipeRightDescription = _describe(selected));
                  }
                },
              ),
              SettingsNavTile(
                title: 'Swipe left action',
                subtitle: _swipeLeftDescription,
                leading: const Icon(AppSymbols.swipe_left),
                onTap: () async {
                  final selected = await widget.onSwipeLeftTap();
                  if (selected != null && mounted) {
                    setState(() => _swipeLeftDescription = _describe(selected));
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* old stateless implementations removed below */

