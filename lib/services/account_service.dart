import '../models/account.dart';
import '../models/group.dart';
import '../database/account_dao.dart';
import '../database/group_dao.dart';
import 'shared_preferences_service.dart';

class AccountService {
  final AccountDao _accountDao;
  final GroupDao _groupDao;
  final SharedPreferencesService _prefs;

  AccountService(this._accountDao, this._groupDao, this._prefs);

  Future<Account> createLocalAccount(String name) async {
    final account = Account(
      name: name,
      type: AccountType.local,
      updateAt: DateTime.now(),
    );

    final id = await _accountDao.insert(account);
    final createdAccount = account.copyWith(id: id);

    // Create default group
    final defaultGroupId = _groupDao.getDefaultGroupId(id);
    await _groupDao.insert(
      Group(
        id: defaultGroupId,
        name: 'Default',
        accountId: id,
      ),
    );

    // Set as current account if it's the first one
    final accounts = await _accountDao.getAll();
    if (accounts.length == 1) {
      await setCurrentAccount(id);
    }

    return createdAccount;
  }

  Future<Account?> getById(int id) async {
    return await _accountDao.getById(id);
  }

  Future<List<Account>> getAll() async {
    return await _accountDao.getAll();
  }

  Future<Account?> getCurrentAccount() async {
    final accountId = await getCurrentAccountId();
    if (accountId == null) return null;
    return await _accountDao.getById(accountId);
  }

  Future<int?> getCurrentAccountId() async {
    return await _prefs.getInt('currentAccountId');
  }

  Future<void> setCurrentAccount(int accountId) async {
    await _prefs.setInt('currentAccountId', accountId);
  }

  Future<void> update(Account account) async {
    await _accountDao.update(account);
  }

  Future<void> updateAccount(Account account) async {
    await _accountDao.update(account);
  }

  Future<void> delete(int id) async {
    await _accountDao.delete(id);
    
    // If deleted account was current, set first available as current
    final currentId = await getCurrentAccountId();
    if (currentId == id) {
      final accounts = await _accountDao.getAll();
      if (accounts.isNotEmpty) {
        await setCurrentAccount(accounts.first.id!);
      } else {
        await _prefs.remove('currentAccountId');
      }
    }
  }
}

