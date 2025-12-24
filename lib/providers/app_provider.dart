import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_helper.dart';
import '../database/account_dao.dart';
import '../database/article_dao.dart';
import '../database/feed_dao.dart';
import '../database/group_dao.dart';
import '../database/blacklist_dao.dart';
import '../services/account_service.dart';
import '../services/article_action_service.dart';
import '../services/freshrss_account_service.dart';
import '../services/freshrss_service.dart';
import '../services/freshrss_sync_service.dart';
import '../services/miniflux_account_service.dart';
import '../services/miniflux_service.dart';
import '../services/miniflux_sync_service.dart';
import '../services/local_rss_service.dart';
import '../services/rss_helper.dart';
import '../services/rss_service.dart';
import '../services/shared_preferences_service.dart';
import '../services/sync_coordinator.dart';
import '../services/opml_service.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

// Database
final databaseHelperProvider = Provider((ref) => DatabaseHelper.instance);

final accountDaoProvider = Provider((ref) => AccountDao());
final articleDaoProvider = Provider((ref) => ArticleDao());
final feedDaoProvider = Provider((ref) => FeedDao());
final groupDaoProvider = Provider((ref) => GroupDao());
final blacklistDaoProvider = Provider((ref) => BlacklistDao());

// Services
final httpClientProvider = Provider((ref) => http.Client());
final sharedPreferencesProvider = Provider((ref) => SharedPreferencesService());

final rssHelperProvider = Provider((ref) {
  return RssHelper(ref.watch(httpClientProvider));
});

final rssServiceProvider = Provider((ref) {
  return RssService(ref.watch(httpClientProvider));
});

final freshRssServiceProvider = Provider((ref) {
  return FreshRssService(ref.watch(httpClientProvider));
});

final minifluxServiceProvider = Provider((ref) {
  return MinifluxService(ref.watch(httpClientProvider));
});

final accountServiceProvider = Provider((ref) {
  return AccountService(
    ref.watch(accountDaoProvider),
    ref.watch(groupDaoProvider),
    ref.watch(sharedPreferencesProvider),
  );
});

final freshRssAccountServiceProvider = Provider((ref) {
  return FreshRssAccountService(
    ref.watch(accountDaoProvider),
    ref.watch(groupDaoProvider),
    ref.watch(sharedPreferencesProvider),
    ref.watch(freshRssServiceProvider),
  );
});

final minifluxAccountServiceProvider = Provider((ref) {
  return MinifluxAccountService(
    ref.watch(accountDaoProvider),
    ref.watch(groupDaoProvider),
    ref.watch(sharedPreferencesProvider),
    ref.watch(minifluxServiceProvider),
  );
});

final localRssServiceProvider = Provider((ref) {
  return LocalRssService(
    ref.watch(articleDaoProvider),
    ref.watch(feedDaoProvider),
    ref.watch(groupDaoProvider),
    ref.watch(accountDaoProvider),
    ref.watch(rssHelperProvider),
    ref.watch(rssServiceProvider),
    ref.watch(httpClientProvider),
  );
});

final freshRssSyncServiceProvider = Provider((ref) {
  return FreshRssSyncService(
    ref.watch(freshRssServiceProvider),
    ref.watch(articleDaoProvider),
    ref.watch(feedDaoProvider),
    ref.watch(groupDaoProvider),
    ref.watch(accountDaoProvider),
    ref.watch(rssServiceProvider),
  );
});

final minifluxSyncServiceProvider = Provider((ref) {
  return MinifluxSyncService(
    ref.watch(minifluxServiceProvider),
    ref.watch(articleDaoProvider),
    ref.watch(feedDaoProvider),
    ref.watch(groupDaoProvider),
    ref.watch(accountDaoProvider),
    ref.watch(rssServiceProvider),
  );
});

final syncCoordinatorProvider = Provider((ref) {
  return SyncCoordinator(
    ref.watch(accountDaoProvider),
    ref.watch(localRssServiceProvider),
    ref.watch(freshRssSyncServiceProvider),
    ref.watch(minifluxSyncServiceProvider),
  );
});

final articleActionServiceProvider = Provider((ref) {
  return ArticleActionService(
    ref.watch(articleDaoProvider),
    ref.watch(accountDaoProvider),
    ref.watch(freshRssServiceProvider),
    ref.watch(minifluxServiceProvider),
  );
});

final opmlServiceProvider = Provider((ref) {
  return OpmlService(
    ref.watch(feedDaoProvider),
    ref.watch(groupDaoProvider),
    ref.watch(accountServiceProvider),
    ref.watch(localRssServiceProvider),
  );
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SharedPreferencesService _prefs;
  ThemeModeNotifier(this._prefs) : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    await _prefs.init();
    final stored = await _prefs.getString('themeMode');
    if (stored == null) return;
    switch (stored) {
      case 'light':
        state = ThemeMode.light;
        break;
      case 'dark':
        state = ThemeMode.dark;
        break;
      default:
        state = ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await _prefs.setString('themeMode', value);
  }
}

final themeModeNotifierProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(sharedPreferencesProvider));
});

// Current account
final currentAccountProvider = FutureProvider((ref) async {
  final accountService = ref.watch(accountServiceProvider);
  return await accountService.getCurrentAccount();
});

// Group filter provider - stores which groups are visible
final groupFilterProvider = StateNotifierProvider.family<GroupFilterNotifier, Set<String>, int>((ref, accountId) {
  return GroupFilterNotifier(ref.watch(sharedPreferencesProvider), accountId);
});

// Feed filter provider - stores which feeds are visible
final feedFilterProvider = StateNotifierProvider.family<FeedFilterNotifier, Set<String>, int>((ref, accountId) {
  return FeedFilterNotifier(ref.watch(sharedPreferencesProvider), accountId);
});

class GroupFilterNotifier extends StateNotifier<Set<String>> {
  final SharedPreferencesService _prefs;
  final int accountId;
  static const String _keyPrefix = 'visible_groups_';

  GroupFilterNotifier(this._prefs, this.accountId) : super({}) {
    _loadFilter();
  }

  Future<void> _loadFilter() async {
    await _prefs.init();
    final key = '$_keyPrefix$accountId';
    final groupIdsStr = await _prefs.getString(key);
    if (groupIdsStr != null && groupIdsStr.isNotEmpty) {
      state = groupIdsStr.split(',').where((id) => id.isNotEmpty).toSet();
    } else {
      // Empty set means all groups are visible
      state = {};
    }
  }

  Future<void> setFilter(Set<String> groupIds) async {
    await _prefs.init();
    state = groupIds;
    final key = '$_keyPrefix$accountId';
    if (groupIds.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, groupIds.join(','));
    }
  }

  bool isGroupVisible(String groupId) {
    // Empty set means all groups are visible
    return state.isEmpty || state.contains(groupId);
  }
}

class FeedFilterNotifier extends StateNotifier<Set<String>> {
  final SharedPreferencesService _prefs;
  final int accountId;
  static const String _keyPrefix = 'visible_feeds_';

  FeedFilterNotifier(this._prefs, this.accountId) : super({}) {
    _loadFilter();
  }

  Future<void> _loadFilter() async {
    await _prefs.init();
    final key = '$_keyPrefix$accountId';
    final feedIdsStr = await _prefs.getString(key);
    if (feedIdsStr != null && feedIdsStr.isNotEmpty) {
      state = feedIdsStr.split(',').where((id) => id.isNotEmpty).toSet();
    } else {
      // Empty set means all feeds are visible
      state = {};
    }
  }

  Future<void> setFilter(Set<String> feedIds) async {
    await _prefs.init();
    state = feedIds;
    final key = '$_keyPrefix$accountId';
    if (feedIds.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, feedIds.join(','));
    }
  }

  bool isFeedVisible(String feedId) {
    // Empty set means all feeds are visible
    return state.isEmpty || state.contains(feedId);
  }
}

