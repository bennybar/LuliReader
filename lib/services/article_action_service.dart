import '../database/account_dao.dart';
import '../database/article_dao.dart';
import '../models/account.dart';
import '../models/article.dart';
import 'freshrss_service.dart';

/// Handles local + remote state changes for articles based on account type.
class ArticleActionService {
  final ArticleDao _articleDao;
  final AccountDao _accountDao;
  final FreshRssService _freshRssService;

  ArticleActionService(
    this._articleDao,
    this._accountDao,
    this._freshRssService,
  );

  Future<void> markAsRead(Article article) async {
    await _applyRemote(
      accountId: article.accountId,
      ids: [article.id],
      action: _freshRssService.markAsRead,
    );
    await _articleDao.markAsRead(article.id);
  }

  Future<void> markAsUnread(Article article) async {
    await _applyRemote(
      accountId: article.accountId,
      ids: [article.id],
      action: _freshRssService.markAsUnread,
    );
    await _articleDao.markAsUnread(article.id);
  }

  Future<void> toggleStar(Article article) async {
    final targetStarred = !article.isStarred;
    await _applyRemote(
      accountId: article.accountId,
      ids: [article.id],
      action: (endpoint, token, ids) =>
          _freshRssService.starArticles(endpoint, token, ids, targetStarred),
    );
    await _articleDao.toggleStarred(article.id);
  }

  Future<void> batchMarkAsRead(List<String> articleIds, int accountId) async {
    await _applyRemote(
      accountId: accountId,
      ids: articleIds,
      action: _freshRssService.markAsRead,
    );
    await _articleDao.batchMarkAsRead(articleIds);
  }

  Future<void> batchMarkAsUnread(List<String> articleIds, int accountId) async {
    await _applyRemote(
      accountId: accountId,
      ids: articleIds,
      action: _freshRssService.markAsUnread,
    );
    await _articleDao.batchMarkAsUnread(articleIds);
  }

  Future<void> batchStar(List<String> articleIds, int accountId) async {
    await _applyRemote(
      accountId: accountId,
      ids: articleIds,
      action: (endpoint, token, ids) =>
          _freshRssService.starArticles(endpoint, token, ids, true),
    );
    await _articleDao.batchStar(articleIds);
  }

  Future<void> batchUnstar(List<String> articleIds, int accountId) async {
    await _applyRemote(
      accountId: accountId,
      ids: articleIds,
      action: (endpoint, token, ids) =>
          _freshRssService.starArticles(endpoint, token, ids, false),
    );
    await _articleDao.batchUnstar(articleIds);
  }

  Future<void> _applyRemote({
    required int accountId,
    required List<String> ids,
    required Future<void> Function(String endpoint, String token, List<String> ids) action,
  }) async {
    if (ids.isEmpty) return;
    final account = await _accountDao.getById(accountId);
    if (account == null || account.type != AccountType.freshrss) {
      return;
    }
    final endpoint = FreshRssService.normalizeApiEndpoint(account.apiEndpoint ?? '');
    try {
      final token = await _ensureToken(account, endpoint);
      await action(endpoint, token, ids);
    } catch (_) {
      // Retry once after refreshing token
      final refreshedToken = await _refreshToken(account, endpoint);
      await action(endpoint, refreshedToken, ids);
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
      throw Exception('FreshRSS credentials missing');
    }
    final token = await _freshRssService.authenticate(
      apiEndpoint,
      account.username!,
      account.password!,
    );
    await _accountDao.update(account.copyWith(authToken: token, apiEndpoint: apiEndpoint));
    return token;
  }

  Future<String> _refreshToken(Account account, String apiEndpoint) async {
    final token = await _freshRssService.authenticate(
      apiEndpoint,
      account.username ?? '',
      account.password ?? '',
    );
    await _accountDao.update(account.copyWith(authToken: token, apiEndpoint: apiEndpoint));
    return token;
  }
}

