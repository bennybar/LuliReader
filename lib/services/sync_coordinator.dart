import '../database/account_dao.dart';
import '../models/account.dart';
import 'freshrss_sync_service.dart';
import 'local_rss_service.dart';

/// Routes sync calls to the correct backend based on account type.
class SyncCoordinator {
  final AccountDao _accountDao;
  final LocalRssService _localService;
  final FreshRssSyncService _freshRssService;

  SyncCoordinator(
    this._accountDao,
    this._localService,
    this._freshRssService,
  );

  Future<void> syncAccount(
    int accountId, {
    void Function(String)? onProgress,
  }) async {
    final account = await _accountDao.getById(accountId);
    if (account == null) throw Exception('Account not found');

    switch (account.type) {
      case AccountType.local:
        await _localService.sync(account.id!, onProgress: onProgress);
        break;
      case AccountType.freshrss:
        await _freshRssService.sync(account.id!, onProgress: onProgress);
        break;
      case AccountType.miniflux:
        throw Exception('Miniflux support coming soon');
    }
  }
}








