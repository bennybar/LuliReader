import '../database/account_dao.dart';
import '../database/group_dao.dart';
import '../models/account.dart';
import '../models/group.dart';
import 'freshrss_service.dart';
import 'shared_preferences_service.dart';

/// Creates and configures FreshRSS cloud accounts.
class FreshRssAccountService {
  final AccountDao _accountDao;
  final GroupDao _groupDao;
  final SharedPreferencesService _prefs;
  final FreshRssService _freshRssService;

  FreshRssAccountService(
    this._accountDao,
    this._groupDao,
    this._prefs,
    this._freshRssService,
  );

  Future<Account> create({
    required String name,
    required String baseUrlOrApi,
    required String username,
    required String password,
  }) async {
    await _prefs.init();
    final apiEndpoint = FreshRssService.normalizeApiEndpoint(baseUrlOrApi);
    final token = await _freshRssService.authenticate(apiEndpoint, username, password);

    final account = Account(
      name: name,
      type: AccountType.freshrss,
      apiEndpoint: apiEndpoint,
      username: username,
      password: password,
      authToken: token,
      updateAt: DateTime.now(),
    );

    final id = await _accountDao.insert(account);
    final created = account.copyWith(id: id);

    // Set as current account if it's the first one.
    final accounts = await _accountDao.getAll();
    if (accounts.length == 1) {
      await _prefs.setInt('currentAccountId', id);
    }

    // Ensure a default group exists for compatibility with UI even before first sync.
    final defaultGroupId = _groupDao.getDefaultGroupId(id);
    await _groupDao.insert(
      Group(
        id: defaultGroupId,
        name: 'Default',
        accountId: id,
      ),
    );

    return created;
  }
}

