import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;

import '../services/account_service.dart';
import '../services/local_rss_service.dart';
import '../services/shared_preferences_service.dart';
import '../database/database_helper.dart';
import '../database/account_dao.dart';
import '../database/group_dao.dart';
import '../database/article_dao.dart';
import '../database/feed_dao.dart';
import '../services/rss_helper.dart';
import '../services/rss_service.dart';

const String kBackgroundSyncTask = 'background_sync_task';

/// Registers periodic background sync. Interval is in minutes.
Future<void> registerBackgroundSync(int minutes) async {
  await Workmanager().cancelByUniqueName(kBackgroundSyncTask);
  if (minutes <= 0) return;
  await Workmanager().registerPeriodicTask(
    kBackgroundSyncTask,
    kBackgroundSyncTask,
    frequency: Duration(minutes: minutes),
    initialDelay: Duration(minutes: minutes),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );
}

Future<void> cancelBackgroundSync() async {
  await Workmanager().cancelByUniqueName(kBackgroundSyncTask);
}

/// Background entrypoint used by Workmanager.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kBackgroundSyncTask) return false;

    try {
      // Initialize singletons/services
      final prefs = SharedPreferencesService();
      await prefs.init();
      final accountId = await prefs.getInt('currentAccountId');
      if (accountId == null) return false;

      final databaseHelper = DatabaseHelper.instance;
      await databaseHelper.database; // ensure DB opened

      final accountDao = AccountDao();
      final groupDao = GroupDao();
      final articleDao = ArticleDao();
      final feedDao = FeedDao();
      final accountService = AccountService(accountDao, groupDao, prefs);
      final account = await accountService.getById(accountId);
      if (account == null) return false;

      final rssHelper = RssHelper(http.Client());
      final rssService = RssService(http.Client());
      final localRssService = LocalRssService(
        articleDao,
        feedDao,
        groupDao,
        accountDao,
        rssHelper,
        rssService,
        http.Client(),
      );

      await localRssService.sync(account.id!);
      await accountService.updateAccount(account.copyWith(updateAt: DateTime.now()));
      return true;
    } catch (_) {
      return false;
    }
  });
}

