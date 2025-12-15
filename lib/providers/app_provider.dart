import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_helper.dart';
import '../database/account_dao.dart';
import '../database/article_dao.dart';
import '../database/feed_dao.dart';
import '../database/group_dao.dart';
import '../services/account_service.dart';
import '../services/local_rss_service.dart';
import '../services/rss_helper.dart';
import '../services/rss_service.dart';
import '../services/shared_preferences_service.dart';
import '../services/opml_service.dart';
import 'package:http/http.dart' as http;

// Database
final databaseHelperProvider = Provider((ref) => DatabaseHelper.instance);

final accountDaoProvider = Provider((ref) => AccountDao());
final articleDaoProvider = Provider((ref) => ArticleDao());
final feedDaoProvider = Provider((ref) => FeedDao());
final groupDaoProvider = Provider((ref) => GroupDao());

// Services
final httpClientProvider = Provider((ref) => http.Client());
final sharedPreferencesProvider = Provider((ref) => SharedPreferencesService());

final rssHelperProvider = Provider((ref) {
  return RssHelper(ref.watch(httpClientProvider));
});

final rssServiceProvider = Provider((ref) {
  return RssService(ref.watch(httpClientProvider));
});

final accountServiceProvider = Provider((ref) {
  return AccountService(
    ref.watch(accountDaoProvider),
    ref.watch(groupDaoProvider),
    ref.watch(sharedPreferencesProvider),
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

final opmlServiceProvider = Provider((ref) {
  return OpmlService(
    ref.watch(feedDaoProvider),
    ref.watch(groupDaoProvider),
    ref.watch(accountServiceProvider),
    ref.watch(localRssServiceProvider),
  );
});

// Current account
final currentAccountProvider = FutureProvider((ref) async {
  final accountService = ref.watch(accountServiceProvider);
  return await accountService.getCurrentAccount();
});

