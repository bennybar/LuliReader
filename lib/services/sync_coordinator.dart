import '../database/account_dao.dart';
import '../models/account.dart';
import 'freshrss_sync_service.dart';
import 'miniflux_sync_service.dart';
import 'local_rss_service.dart';

/// Routes sync calls to the correct backend based on account type.
class SyncCoordinator {
  final AccountDao _accountDao;
  final LocalRssService _localService;
  final FreshRssSyncService _freshRssService;
  final MinifluxSyncService _minifluxService;

  SyncCoordinator(
    this._accountDao,
    this._localService,
    this._freshRssService,
    this._minifluxService,
  );

  Future<void> syncAccount(
    int accountId, {
    void Function(String)? onProgress,
    void Function(double)? onProgressPercent,
  }) async {
    final account = await _accountDao.getById(accountId);
    if (account == null) throw Exception('Account not found');

    switch (account.type) {
      case AccountType.local:
        await _localService.sync(
          account.id!, 
          onProgress: onProgress,
          onProgressPercent: onProgressPercent,
        );
        break;
      case AccountType.freshrss:
        await _freshRssService.sync(
          account.id!, 
          onProgress: onProgress,
          onProgressPercent: onProgressPercent,
        );
        break;
      case AccountType.miniflux:
        await _minifluxService.sync(
          account.id!, 
          onProgress: onProgress,
          onProgressPercent: onProgressPercent,
        );
        break;
    }
  }
}







