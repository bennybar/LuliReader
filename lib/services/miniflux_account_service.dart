import '../database/account_dao.dart';
import '../database/group_dao.dart';
import '../models/account.dart';
import '../models/group.dart';
import 'miniflux_service.dart';
import 'shared_preferences_service.dart';

/// Creates and configures Miniflux cloud accounts.
class MinifluxAccountService {
  final AccountDao _accountDao;
  final GroupDao _groupDao;
  final SharedPreferencesService _prefs;
  final MinifluxService _minifluxService;

  MinifluxAccountService(
    this._accountDao,
    this._groupDao,
    this._prefs,
    this._minifluxService,
  );

  Future<Account> create({
    required String name,
    required String baseUrlOrApi,
    required String username,
    required String password,
  }) async {
    await _prefs.init();
    final apiEndpoint = MinifluxService.normalizeApiEndpoint(baseUrlOrApi);
    final result = await _minifluxService.authenticateWithEndpoint(apiEndpoint, username, password);
    final token = result['token']!;
    final correctedEndpoint = result['correctedEndpoint'] ?? apiEndpoint;

    final account = Account(
      name: name,
      type: AccountType.miniflux,
      apiEndpoint: correctedEndpoint,
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

