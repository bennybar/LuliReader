import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:readability/article.dart' as readability;
import 'package:readability/readability.dart';

import '../models/article.dart';
import 'database_service.dart';

class OfflineCacheService {
  OfflineCacheService._internal();
  static final OfflineCacheService _instance = OfflineCacheService._internal();
  factory OfflineCacheService() => _instance;

  final DatabaseService _db = DatabaseService();
  final http.Client _client = http.Client();
  Directory? _baseDir;

  Future<void> refreshUnreadArticles({bool force = false}) async {
    final unreadArticles = await _db.getArticles(isRead: false);
    for (final article in unreadArticles) {
      if (!force &&
          article.offlineCachePath != null &&
          await _fileExists(article.offlineCachePath!)) {
        continue;
      }
      await _cacheArticle(article, force: force);
    }
  }

  Future<void> cleanupExpiredCache({Duration gracePeriod = const Duration(days: 3)}) async {
    final threshold = DateTime.now().subtract(gracePeriod);
    final expiredArticles = await _db.getArticlesForOfflineCleanup(threshold);
    for (final article in expiredArticles) {
      await _removeCache(article);
    }
  }

  Future<void> refreshAndCleanup({bool force = false}) async {
    await refreshUnreadArticles(force: force);
    await cleanupExpiredCache();
  }

  Future<void> _cacheArticle(Article article, {bool force = false}) async {
    try {
      final dir = await _prepareArticleDirectory(article.id, force: force);
      final offlineContent = await _buildOfflineContent(article);
      final processedHtml = await _downloadImagesAndRewrite(
        offlineContent.html,
        dir,
        article.link != null ? Uri.tryParse(article.link!) : null,
      );
      final filePath = p.join(dir.path, 'index.html');
      final file = File(filePath);
      await file.writeAsString(_wrapHtml(
        title: article.title,
        body: processedHtml,
        author: offlineContent.author ?? article.author,
        siteName: offlineContent.siteName ?? (article.link != null ? Uri.tryParse(article.link!)?.host : null),
        published: offlineContent.published ?? article.publishedDate.toLocal().toIso8601String(),
        originalUrl: article.link,
      ));

      await _db.updateOfflineCacheInfo(
        article.id,
        path: filePath,
        cachedAt: DateTime.now(),
      );
      print('Offline cache saved for article ${article.id}');
    } catch (e) {
      print('Offline cache error for ${article.id}: $e');
    }
  }

  Future<Directory> _prepareArticleDirectory(String articleId, {bool force = false}) async {
    final base = await _getBaseDirectory();
    final dir = Directory(p.join(base.path, articleId));
    if (await dir.exists() && force) {
      await dir.delete(recursive: true);
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final imagesDir = Directory(p.join(dir.path, 'images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _getBaseDirectory() async {
    if (_baseDir != null) return _baseDir!;
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(documents.path, 'offline_articles'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _baseDir = dir;
    return dir;
  }

  Future<_OfflineContent> _buildOfflineContent(Article article) async {
    final fallback = article.content ?? article.summary ?? '<p>No content available.</p>';
    final link = article.link;
    if (link == null) {
      return _OfflineContent(html: fallback);
    }

    try {
      final readability.Article readabilityArticle = await parseAsync(link);
      final content = readabilityArticle.content ?? readabilityArticle.textContent;
      if (content != null && content.isNotEmpty) {
        return _OfflineContent(
          html: content,
          author: readabilityArticle.author,
          siteName: readabilityArticle.siteName,
          published: readabilityArticle.publishedTime,
        );
      }
    } catch (e) {
      print('Failed to parse article with Readability for ${article.id}: $e');
    }

    try {
      final uri = Uri.parse(link);
      final response = await _client.get(uri);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final document = html_parser.parse(response.body);
        return _OfflineContent(
          html: document.body?.innerHtml ?? fallback,
          siteName: uri.host,
        );
      }
    } catch (e) {
      print('Fallback fetch failed for ${article.id}: $e');
    }

    return _OfflineContent(html: fallback);
  }

  Future<String> _downloadImagesAndRewrite(
    String html,
    Directory articleDir,
    Uri? baseUri,
  ) async {
    final document = html_parser.parse(html);
    final images = document.getElementsByTagName('img');
    final imagesDir = Directory(p.join(articleDir.path, 'images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    for (final img in images) {
      final src = img.attributes['src'];
      if (src == null || src.isEmpty) continue;
      final localPath = await _downloadImage(src, imagesDir, baseUri);
      if (localPath != null) {
        img.attributes['src'] = 'images/${p.basename(localPath)}';
      }
    }

    return document.body?.innerHtml ?? html;
  }

  Future<String?> _downloadImage(String src, Directory imagesDir, Uri? baseUri) async {
    try {
      Uri? uri;
      if (src.startsWith('http://') || src.startsWith('https://')) {
        uri = Uri.parse(src);
      } else if (baseUri != null) {
        uri = baseUri.resolve(src);
      }
      if (uri == null) return null;

      final response = await _client.get(uri);
      if (response.statusCode != 200) return null;

      final extension = p.extension(uri.path);
      final fileName =
          '${DateTime.now().microsecondsSinceEpoch}${extension.isNotEmpty ? extension : '.img'}';
      final file = File(p.join(imagesDir.path, fileName));
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } catch (e) {
      print('Failed to download image $src: $e');
      return null;
    }
  }

  String _wrapHtml({
    required String title,
    required String body,
    String? author,
    String? published,
    String? siteName,
    String? originalUrl,
  }) {
    final metaChips = [
      if (siteName != null && siteName.isNotEmpty) '<span>$siteName</span>',
      if (author != null && author.isNotEmpty) '<span>$author</span>',
      if (published != null && published.isNotEmpty) '<span>$published</span>',
      if (originalUrl != null && originalUrl.isNotEmpty)
        '<span><a href="$originalUrl" target="_blank" rel="noopener noreferrer">Original</a></span>',
    ].join();

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>$title</title>
  <style>
    :root {
      color-scheme: light dark;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }
    body {
      margin: 0;
      padding: 0;
      background: #f5f5f5;
      color: #111;
      line-height: 1.7;
    }
    .reader {
      max-width: 760px;
      margin: 0 auto;
      padding: 32px 20px 40px;
      background: #fff;
      min-height: 100vh;
    }
    @media (prefers-color-scheme: dark) {
      body { background: #0f0f0f; color: #f3f3f3; }
      .reader { background: #1a1a1a; }
    }
    header {
      margin-bottom: 24px;
    }
    header h1 {
      font-size: 2rem;
      margin-bottom: 12px;
      line-height: 1.3;
    }
    .meta {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      font-size: 0.9rem;
    }
    .meta span {
      background: rgba(0,0,0,0.06);
      padding: 4px 10px;
      border-radius: 999px;
      color: #444;
    }
    @media (prefers-color-scheme: dark) {
      .meta span { background: rgba(255,255,255,0.12); color: #f0f0f0; }
    }
    article {
      font-size: 1.05rem;
    }
    article p {
      margin: 1.1em 0;
    }
    article img, article video, article iframe {
      max-width: 100%;
      height: auto;
      margin: 18px auto;
      display: block;
      border-radius: 10px;
      box-shadow: 0 10px 25px rgba(0,0,0,0.08);
    }
    blockquote {
      margin: 1.5em 0;
      padding: 0.8em 1em;
      border-inline-start: 4px solid rgba(0,0,0,0.15);
      background: rgba(0,0,0,0.04);
      font-style: italic;
    }
    @media (prefers-color-scheme: dark) {
      blockquote {
        border-color: rgba(255,255,255,0.25);
        background: rgba(255,255,255,0.07);
      }
    }
    pre {
      overflow-x: auto;
      padding: 16px;
      background: rgba(0,0,0,0.08);
      border-radius: 12px;
    }
    code {
      font-family: "Fira Code", SFMono-Regular, Consolas, "Liberation Mono", Menlo, monospace;
    }
    hr {
      border: none;
      border-top: 1px solid rgba(0,0,0,0.1);
      margin: 2rem 0;
    }
    a {
      color: #1a73e8;
      text-decoration: none;
      border-bottom: 1px solid rgba(26,115,232,0.4);
    }
    @media (prefers-color-scheme: dark) {
      a {
        color: #8ab4f8;
        border-bottom-color: rgba(138,180,248,0.4);
      }
    }
  </style>
</head>
<body>
  <div class="reader">
    <header>
      <h1>$title</h1>
      ${metaChips.isNotEmpty ? '<div class="meta">$metaChips</div>' : ''}
    </header>
    <article>
      $body
    </article>
  </div>
</body>
</html>
''';
  }

  Future<void> _removeCache(Article article) async {
    if (article.offlineCachePath == null) return;
    try {
      final file = File(article.offlineCachePath!);
      final dir = file.parent;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      } else if (await file.exists()) {
        await file.delete();
      }
      await _db.updateOfflineCacheInfo(article.id, path: null, cachedAt: null);
      print('Removed offline cache for ${article.id}');
    } catch (e) {
      print('Failed to remove offline cache for ${article.id}: $e');
    }
  }

  Future<bool> _fileExists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }
}

class _OfflineContent {
  final String html;
  final String? author;
  final String? siteName;
  final String? published;

  _OfflineContent({
    required this.html,
    this.author,
    this.siteName,
    this.published,
  });
}

