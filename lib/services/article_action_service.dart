import '../database/account_dao.dart';
import '../database/article_dao.dart';
import '../models/account.dart';
import '../models/article.dart';
import 'freshrss_service.dart';
import 'miniflux_service.dart';

/// Type alias for remote article action function
typedef RemoteAction = Future<void> Function(String endpoint, String token, List<String> ids);

/// Handles local + remote state changes for articles based on account type.
class ArticleActionService {
  final ArticleDao _articleDao;
  final AccountDao _accountDao;
  final FreshRssService _freshRssService;
  final MinifluxService _minifluxService;

  ArticleActionService(
    this._articleDao,
    this._accountDao,
    this._freshRssService,
    this._minifluxService,
  );

  Future<void> markAsRead(Article article) async {
    final account = await _accountDao.getById(article.accountId);
    if (account == null) return;
    
    // Update local database first for immediate UI feedback
    await _articleDao.markAsRead(article.id);
    
    // Then sync to remote server (for Miniflux/FreshRSS)
    if (account.type == AccountType.miniflux) {
      final endpoint = MinifluxService.normalizeApiEndpoint(account.apiEndpoint ?? '');
      final token = await _ensureToken(account, endpoint);
      // Fire and forget - don't block UI on network call
      _minifluxService.markAsRead(
        endpoint,
        token,
        [article.id],
        username: account.username,
        password: account.password,
      ).catchError((e) {
        print('[ARTICLE_ACTION] Error syncing read status to Miniflux: $e');
        // Optionally revert local change if sync fails
      });
    } else if (account.type == AccountType.freshrss) {
      // Fire and forget - don't block UI on network call
      _applyRemote(
        accountId: article.accountId,
        ids: [article.id],
        action: _freshRssService.markAsRead,
      ).catchError((e) {
        print('[ARTICLE_ACTION] Error syncing read status to FreshRSS: $e');
      });
    }
  }

  Future<void> markAsUnread(Article article) async {
    final account = await _accountDao.getById(article.accountId);
    if (account == null) return;
    
    // Update local database first for immediate UI feedback
    await _articleDao.markAsUnread(article.id);
    
    // Then sync to remote server (for Miniflux/FreshRSS)
    if (account.type == AccountType.miniflux) {
      final endpoint = MinifluxService.normalizeApiEndpoint(account.apiEndpoint ?? '');
      final token = await _ensureToken(account, endpoint);
      // Fire and forget - don't block UI on network call
      _minifluxService.markAsUnread(
        endpoint,
        token,
        [article.id],
        username: account.username,
        password: account.password,
      ).catchError((e) {
        print('[ARTICLE_ACTION] Error syncing unread status to Miniflux: $e');
      });
    } else if (account.type == AccountType.freshrss) {
      // Fire and forget - don't block UI on network call
      _applyRemote(
        accountId: article.accountId,
        ids: [article.id],
        action: _freshRssService.markAsUnread,
      ).catchError((e) {
        print('[ARTICLE_ACTION] Error syncing unread status to FreshRSS: $e');
      });
    }
  }

  Future<void> toggleStar(Article article) async {
    final account = await _accountDao.getById(article.accountId);
    if (account == null) return;
    
    final targetStarred = !article.isStarred;
    if (account.type == AccountType.miniflux) {
      final endpoint = MinifluxService.normalizeApiEndpoint(account.apiEndpoint ?? '');
      final token = await _ensureToken(account, endpoint);
      await _minifluxService.starArticles(
        endpoint,
        token,
        [article.id],
        targetStarred,
        username: account.username,
        password: account.password,
      );
    } else if (account.type == AccountType.freshrss) {
      await _applyRemote(
        accountId: article.accountId,
        ids: [article.id],
        action: (endpoint, token, ids) => _freshRssService.starArticles(endpoint, token, ids, targetStarred),
      );
    }
    await _articleDao.toggleStarred(article.id);
  }

  Future<void> batchMarkAsRead(List<String> articleIds, int accountId) async {
    final account = await _accountDao.getById(accountId);
    if (account == null) return;
    
    if (account.type == AccountType.miniflux) {
      final endpoint = MinifluxService.normalizeApiEndpoint(account.apiEndpoint ?? '');
      final token = await _ensureToken(account, endpoint);
      await _minifluxService.markAsRead(
        endpoint,
        token,
        articleIds,
        username: account.username,
        password: account.password,
      );
    } else if (account.type == AccountType.freshrss) {
      await _applyRemote(
        accountId: accountId,
        ids: articleIds,
        action: _freshRssService.markAsRead,
      );
    }
    await _articleDao.batchMarkAsRead(articleIds);
  }

  Future<void> batchMarkAsUnread(List<String> articleIds, int accountId) async {
    final account = await _accountDao.getById(accountId);
    if (account == null) return;
    
    if (account.type == AccountType.miniflux) {
      final endpoint = MinifluxService.normalizeApiEndpoint(account.apiEndpoint ?? '');
      final token = await _ensureToken(account, endpoint);
      await _minifluxService.markAsUnread(
        endpoint,
        token,
        articleIds,
        username: account.username,
        password: account.password,
      );
    } else if (account.type == AccountType.freshrss) {
      await _applyRemote(
        accountId: accountId,
        ids: articleIds,
        action: _freshRssService.markAsUnread,
      );
    }
    await _articleDao.batchMarkAsUnread(articleIds);
  }

  Future<void> batchStar(List<String> articleIds, int accountId) async {
    final account = await _accountDao.getById(accountId);
    if (account == null) return;
    
    if (account.type == AccountType.miniflux) {
      final endpoint = MinifluxService.normalizeApiEndpoint(account.apiEndpoint ?? '');
      final token = await _ensureToken(account, endpoint);
      await _minifluxService.starArticles(
        endpoint,
        token,
        articleIds,
        true,
        username: account.username,
        password: account.password,
      );
    } else if (account.type == AccountType.freshrss) {
      await _applyRemote(
        accountId: accountId,
        ids: articleIds,
        action: (endpoint, token, ids) => _freshRssService.starArticles(endpoint, token, ids, true),
      );
    }
    await _articleDao.batchStar(articleIds);
  }

  Future<void> batchUnstar(List<String> articleIds, int accountId) async {
    final account = await _accountDao.getById(accountId);
    if (account == null) return;
    
    if (account.type == AccountType.miniflux) {
      final endpoint = MinifluxService.normalizeApiEndpoint(account.apiEndpoint ?? '');
      final token = await _ensureToken(account, endpoint);
      await _minifluxService.starArticles(
        endpoint,
        token,
        articleIds,
        false,
        username: account.username,
        password: account.password,
      );
    } else if (account.type == AccountType.freshrss) {
      await _applyRemote(
        accountId: accountId,
        ids: articleIds,
        action: (endpoint, token, ids) => _freshRssService.starArticles(endpoint, token, ids, false),
      );
    }
    await _articleDao.batchUnstar(articleIds);
  }

  Future<void> _applyRemote({
    required int accountId,
    required List<String> ids,
    required RemoteAction action,
  }) async {
    if (ids.isEmpty) return;
    final account = await _accountDao.getById(accountId);
    if (account == null || (account.type != AccountType.freshrss && account.type != AccountType.miniflux)) {
      return;
    }
    final endpoint = account.type == AccountType.miniflux
        ? MinifluxService.normalizeApiEndpoint(account.apiEndpoint ?? '')
        : FreshRssService.normalizeApiEndpoint(account.apiEndpoint ?? '');
    try {
      final token = await _ensureToken(account, endpoint);
      // For Miniflux, pass username/password to action (native API needs them)
      if (account.type == AccountType.miniflux) {
        // Create a wrapper that passes username/password
        await action(endpoint, token, ids);
      } else {
        await action(endpoint, token, ids);
      }
    } catch (_) {
      // Retry once after refreshing token
      final refreshedToken = await _refreshToken(account, endpoint);
      if (account.type == AccountType.miniflux) {
        await action(endpoint, refreshedToken, ids);
      } else {
        await action(endpoint, refreshedToken, ids);
      }
    }
  }

  Future<String> _ensureToken(Account account, String apiEndpoint) async {
    if (account.authToken != null && account.authToken!.isNotEmpty) {
      return account.authToken!;
    }
    if (account.username == null ||
        account.username!.isEmpty ||
        account.password == null ||
        account.password!.isEmpty) {
      throw Exception('Cloud account credentials missing');
    }
    String token;
    String finalEndpoint = apiEndpoint;
    if (account.type == AccountType.miniflux) {
      final result = await _minifluxService.authenticateWithEndpoint(apiEndpoint, account.username!, account.password!);
      token = result['token']!;
      finalEndpoint = result['correctedEndpoint'] ?? apiEndpoint;
    } else {
      token = await _freshRssService.authenticate(apiEndpoint, account.username!, account.password!);
    }
    await _accountDao.update(account.copyWith(authToken: token, apiEndpoint: finalEndpoint));
    return token;
  }

  Future<String> _refreshToken(Account account, String apiEndpoint) async {
    String token;
    String finalEndpoint = apiEndpoint;
    if (account.type == AccountType.miniflux) {
      final result = await _minifluxService.authenticateWithEndpoint(apiEndpoint, account.username ?? '', account.password ?? '');
      token = result['token']!;
      finalEndpoint = result['correctedEndpoint'] ?? apiEndpoint;
    } else {
      token = await _freshRssService.authenticate(apiEndpoint, account.username ?? '', account.password ?? '');
    }
    await _accountDao.update(account.copyWith(authToken: token, apiEndpoint: finalEndpoint));
    return token;
  }
}
