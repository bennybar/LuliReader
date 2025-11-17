import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../models/article.dart';
import '../notifiers/starred_refresh_notifier.dart';
import '../notifiers/unread_refresh_notifier.dart';
import '../services/database_service.dart';
import '../services/offline_cache_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../utils/image_utils.dart';
import '../utils/platform_utils.dart';
import '../widgets/platform_app_bar.dart';
import 'offline_article_screen.dart';
import 'reader_article_screen.dart';
import 'web_article_screen.dart';

class ArticleDetailScreen extends StatefulWidget {
  final Article article;

  const ArticleDetailScreen({super.key, required this.article});

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  late Article _article;
  final SyncService _syncService = SyncService();
  final DatabaseService _db = DatabaseService();
  final StorageService _storage = StorageService();
  final OfflineCacheService _offlineCacheService = OfflineCacheService();
  bool _isLoading = false;
  bool _autoMarkRead = true;
  bool _hasSyncConfig = false;
  double _articleFontSize = 16.0;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _initializePreferences();
  }

  Future<void> _initializePreferences() async {
    final autoMark = await _storage.getAutoMarkRead();
    final fontSize = await _storage.getArticleFontSize();
    final config = await _storage.getUserConfig();
    if (config != null) {
      _syncService.setUserConfig(config);
      _hasSyncConfig = true;
    }
    if (!mounted) return;
    setState(() {
      _autoMarkRead = autoMark;
      _articleFontSize = fontSize;
    });
    await _loadLatestArticle();
    if (autoMark) {
      await _markAsRead();
    }
  }

  Future<bool> _ensureSyncConfigured() async {
    if (_hasSyncConfig) return true;
    final config = await _storage.getUserConfig();
    if (config == null) return false;
    _syncService.setUserConfig(config);
    _hasSyncConfig = true;
    return true;
  }

  Future<void> _markAsRead() async {
    if (!_article.isRead) {
      final ready = await _ensureSyncConfigured();
      if (!ready) {
        debugPrint('Cannot mark article as read: missing sync config.');
        return;
      }
      await _syncService.markArticleAsRead(_article.id, true);
      setState(() {
        _article = _article.copyWith(isRead: true);
      });
      await _loadLatestArticle();
      // UnreadRefreshNotifier will be pinged by sync_service
    }
  }

  Future<void> _loadLatestArticle() async {
    final latest = await _db.getArticle(_article.id);
    if (latest != null && mounted) {
      setState(() {
        _article = latest;
      });
    }
  }

  Future<void> _toggleStarred() async {
    setState(() => _isLoading = true);
    final newStarred = !_article.isStarred;
    await _syncService.markArticleAsStarred(_article.id, newStarred);
    StarredRefreshNotifier.instance.ping();
    setState(() {
      _article = _article.copyWith(isStarred: newStarred);
      _isLoading = false;
    });
    await _loadLatestArticle();
  }

  Future<void> _openInBrowser() async {
    final link = _article.link;
    if (link == null) return;

    final uri = Uri.tryParse(link);
    if (uri == null || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebArticleScreen(
          title: _article.title,
          url: uri.toString(),
        ),
      ),
    );
  }

  Future<void> _repullFullText() async {
    final link = _article.link;
    if (link == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No original link available for this article')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final html =
          await _offlineCacheService.repullArticleContentWithChromeUA(_article);
      if (html == null || html.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to fetch full text')),
          );
        }
        return;
      }

      final updated = _article.copyWith(
        content: html,
        lastSyncedAt: DateTime.now(),
      );
      await _db.updateArticle(updated);
      if (mounted) {
        setState(() {
          _article = updated;
        });
      }

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReaderArticleScreen(
              title: _article.title,
              html: html,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Full text refresh failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openOfflineCopy() async {
    final path = _article.offlineCachePath;
    if (path == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline copy not available yet.')),
      );
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline file missing. Please refresh offline content.')),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OfflineArticleScreen(
          filePath: file.path,
          title: _article.title,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, y • h:mm a').format(date);
  }

  String _stripHtml(String? html) {
    if (html == null) return '';

    // Treat common block/line-break tags as paragraph separators before stripping.
    var text = html
        .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</\s*p\s*>', caseSensitive: false), '\n\n');

    // Remove remaining HTML tags
    text = text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    // Normalize whitespace and collapse excessive blank lines
    text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return text.trim();
  }

  bool _isRTLText(String text) {
    final rtlRegex = RegExp(r'[\u0590-\u08FF]');
    return rtlRegex.hasMatch(text);
  }

  TextAlign _getTextAlign(String text) => _isRTLText(text) ? TextAlign.right : TextAlign.left;

  ui.TextDirection _getTextDirection(String text) =>
      _isRTLText(text) ? ui.TextDirection.rtl : ui.TextDirection.ltr;

  String _resolveContentImageUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';

    Uri? base;
    if (_article.link != null) {
      base = Uri.tryParse(_article.link!);
    }

    Uri? resolved;

    // Protocol-relative URLs: //example.com/image.jpg
    if (trimmed.startsWith('//')) {
      final scheme = base?.scheme?.isNotEmpty == true ? base!.scheme : 'https';
      resolved = Uri.parse('$scheme:$trimmed');
    }
    // Root-relative URLs: /path/to/image.jpg
    else if (trimmed.startsWith('/') && base != null) {
      resolved = Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: trimmed,
      );
    }
    // No scheme: image.jpg or path/image.jpg
    else if (!trimmed.contains('://') && base != null) {
      resolved = base.resolve(trimmed);
    }

    final finalUrl = (resolved ?? Uri.tryParse(trimmed))?.toString() ?? trimmed;
    debugPrint('Article image URL resolved: raw=$trimmed -> final=$finalUrl');
    return finalUrl;
  }

  List<Widget> _buildInlineBody(BuildContext context) {
    final html = _article.content ?? _article.summary ?? '';
    if (html.isEmpty) {
      return [
        SelectableText(
          _stripHtml(html),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: _articleFontSize,
                height: 1.6,
              ),
          textAlign: _getTextAlign(html),
          textDirection: _getTextDirection(html),
        ),
      ];
    }

    final widgets = <Widget>[];
    final seenImages = <String>{};
    final heroUrl = _article.imageUrl;
    final imgRegex = RegExp(
      '<img[^>]+src=(["\']?)([^"\'\\s]+)\\1[^>]*>',
      caseSensitive: false,
    );

    int cursor = 0;
    for (final match in imgRegex.allMatches(html)) {
      final before = html.substring(cursor, match.start);
      final beforeText = _stripHtml(before);
      if (beforeText.trim().isNotEmpty) {
        widgets.add(
          SelectableText(
            beforeText,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: _articleFontSize,
                  height: 1.6,
                ),
            textAlign: _getTextAlign(beforeText),
            textDirection: _getTextDirection(beforeText),
          ),
        );
        widgets.add(const SizedBox(height: 12));
      }

      final rawSrc = match.group(2);
      if (rawSrc != null && rawSrc.isNotEmpty) {
        final resolved = _resolveContentImageUrl(rawSrc);
        if (resolved.isNotEmpty) {
          // Skip if same as hero image
          if (heroUrl != null && resolved == heroUrl) {
            debugPrint(
                'Skipping inline image equal to hero image: resolved=$resolved');
          }
          // Skip duplicates we've already rendered in the body
          else if (!seenImages.add(resolved)) {
            debugPrint(
                'Skipping duplicate inline image already seen: resolved=$resolved');
          } else {
            debugPrint(
                'Article content image candidate (inline): raw=$rawSrc, resolved=$resolved');
            widgets.add(_ArticleContentImage(url: resolved));
            widgets.add(const SizedBox(height: 12));
          }
        }
      }

      cursor = match.end;
    }

    // Trailing text after the last <img>
    if (cursor < html.length) {
      final tail = html.substring(cursor);
      final tailText = _stripHtml(tail);
      if (tailText.trim().isNotEmpty) {
        widgets.add(
          SelectableText(
            tailText,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: _articleFontSize,
                  height: 1.6,
                ),
            textAlign: _getTextAlign(tailText),
            textDirection: _getTextDirection(tailText),
          ),
        );
      }
    }

    // Fallback: if parsing somehow produced nothing, show full text once.
    if (widgets.isEmpty) {
      widgets.add(
        SelectableText(
          _stripHtml(html),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: _articleFontSize,
                height: 1.6,
              ),
          textAlign: _getTextAlign(html),
          textDirection: _getTextDirection(html),
        ),
      );
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final isRtlTitle = _isRTLText(_article.title);

    final actions = <Widget>[
      if (_article.offlineCachePath != null)
        IconButton(
          icon: const Icon(Icons.offline_pin),
          tooltip: 'View offline version',
          onPressed: _openOfflineCopy,
        ),
      IconButton(
        icon: Icon(
          _article.isStarred ? Icons.star : Icons.star_border,
          color: _article.isStarred ? Colors.amber : null,
        ),
        onPressed: _isLoading ? null : _toggleStarred,
      ),
    ];
    
    return Scaffold(
      appBar: PlatformAppBar(
        title: _article.title,
        actions: actions,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_article.imageUrl != null)
              SizedBox(
                height: 220,
                width: double.infinity,
                child: _ArticleHeroImage(imageUrl: _article.imageUrl!),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _article.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: _getTextAlign(_article.title),
                        textDirection: _getTextDirection(_article.title),
                      ),
                      const SizedBox(height: 8),
                      if (_article.author != null)
                        Align(
                          alignment: isRtlTitle
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Text(
                            _article.author!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: isRtlTitle
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Text(
                          _formatDate(_article.publishedDate),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._buildInlineBody(context),
                      if (_article.link != null) ...[
                        const SizedBox(height: 20),
                        _buildFooterActions(context),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterActions(BuildContext context) {
    final children = <Widget>[];

    // Open original in browser
    children.add(_buildGlassIconButton(
      context: context,
      icon: Icons.open_in_browser,
      tooltip: 'Open original article',
      onTap: _isLoading ? null : _openInBrowser,
    ));

    // Re-pull full text with Chrome UA
    children.add(const SizedBox(width: 12));
    children.add(_buildGlassIconButton(
      context: context,
      icon: Icons.article,
      tooltip: 'Re-pull full text',
      onTap: _isLoading ? null : _repullFullText,
      showBusy: _isLoading,
    ));

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: children,
    );
  }

  Widget _buildGlassIconButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool showBusy = false,
  }) {
    if (!isIOS) {
      return IconButton(
        tooltip: tooltip,
        icon: showBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        onPressed: onTap,
      );
    }

    final content = showBusy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 18);

    return Tooltip(
      message: tooltip,
      child: LiquidGlassLayer(
        settings: const LiquidGlassSettings(
          thickness: 16,
          blur: 18,
          glassColor: Color(0x33FFFFFF),
        ),
        child: LiquidGlass(
          shape: LiquidRoundedSuperellipse(borderRadius: 18),
          glassContainsChild: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArticleHeroImage extends StatefulWidget {
  final String imageUrl;

  const _ArticleHeroImage({required this.imageUrl});

  @override
  State<_ArticleHeroImage> createState() => _ArticleHeroImageState();
}

class _ArticleHeroImageState extends State<_ArticleHeroImage> {
  Future<RemoteImageFormat>? _formatFuture;

  @override
  void initState() {
    super.initState();
    _prepareFormatFuture();
  }

  @override
  void didUpdateWidget(covariant _ArticleHeroImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _prepareFormatFuture();
    }
  }

  void _prepareFormatFuture() {
    final url = widget.imageUrl;
    if (!ImageUtils.isDataUri(url) && !ImageUtils.looksLikeSvgUrl(url)) {
      _formatFuture = ImageUtils.detectRemoteFormat(url);
    } else {
      _formatFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: const Center(
        child: Icon(Icons.image_not_supported, size: 40),
      ),
    );

    final border = const BorderRadius.only(
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(16),
    );

    final url = widget.imageUrl;
    debugPrint('Hero image candidate: $url');

    if (ImageUtils.isDataUri(url)) {
      if (ImageUtils.isSvgDataUri(url)) {
        final svgString = ImageUtils.decodeSvgDataUri(url);
        if (svgString == null) return placeholder;
        return ClipRRect(
          borderRadius: border,
          child: SvgPicture.string(svgString, fit: BoxFit.cover),
        );
      } else {
        final bytes = ImageUtils.decodeBitmapDataUri(url);
        if (bytes == null) return placeholder;
        return ClipRRect(
          borderRadius: border,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          ),
        );
      }
    }

    if (ImageUtils.looksLikeSvgUrl(url)) {
      return ClipRRect(
        borderRadius: border,
        child: SvgPicture.network(url,
            fit: BoxFit.cover,
            placeholderBuilder: (_) => const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            // ignore: deprecated_member_use
            colorFilter: null),
      );
    }

    if (_formatFuture != null) {
      return FutureBuilder<RemoteImageFormat>(
        future: _formatFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ClipRRect(
              borderRadius: border,
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          final format = snapshot.data ?? RemoteImageFormat.unknown;
          if (format == RemoteImageFormat.svg) {
            return ClipRRect(
              borderRadius: border,
              child: SvgPicture.network(
                url,
                fit: BoxFit.cover,
                placeholderBuilder: (_) => const Center(child: CircularProgressIndicator()),
              ),
            );
          }
          if (format == RemoteImageFormat.bitmap) {
            debugPrint('Hero bitmap confirmed via header for $url');
            return _buildBitmapFromCache(url, border, placeholder);
          }
          if (format == RemoteImageFormat.unsupported) {
            debugPrint('Hero image uses unsupported MIME. Skipping $url');
            return placeholder;
          }
          debugPrint('Hero bitmap assumed after unknown HEAD result for $url');
          return _buildBitmapFromCache(url, border, placeholder);
        },
      );
    }

    debugPrint('Hero bitmap assumed (no header probe) for $url');
    return _buildBitmapFromCache(url, border, placeholder);
  }

  Widget _buildBitmapFromCache(String url, BorderRadius border, Widget placeholder) {
    return FutureBuilder<Uint8List?>(
      future: ImageUtils.decodedBitmapBytes(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ClipRRect(
            borderRadius: border,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          debugPrint('Hero decoded bytes unavailable for $url');
          return placeholder;
        }
        return ClipRRect(
          borderRadius: border,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        );
      },
    );
  }
}

class _ArticleContentImage extends StatelessWidget {
  final String url;

  const _ArticleContentImage({required this.url});

  @override
  Widget build(BuildContext context) {
    // Handle data: URIs (inline SVG / bitmap) separately.
    if (ImageUtils.isDataUri(url)) {
      if (ImageUtils.isSvgDataUri(url)) {
        final svg = ImageUtils.decodeSvgDataUri(url);
        if (svg == null) {
          debugPrint('Article content SVG data URI could not be decoded: $url');
          return const SizedBox.shrink();
        }
        debugPrint('Rendering article content SVG data URI, length=${svg.length}');
        return SvgPicture.string(
          svg,
          width: double.infinity,
          fit: BoxFit.contain,
        );
      } else {
        final bytes = ImageUtils.decodeBitmapDataUri(url);
        if (bytes == null) {
          debugPrint('Article content bitmap data URI could not be decoded: $url');
          return const SizedBox.shrink();
        }
        debugPrint('Rendering article content bitmap data URI, bytes=${bytes.length}');
        return Image.memory(
          bytes,
          width: double.infinity,
          fit: BoxFit.cover,
        );
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        debugPrint('Rendering article content image at width=$width, url=$url');

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: url,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: double.infinity,
              height: width * 0.56, // ~16:9
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (_, __, error) {
              debugPrint('Article content image failed to load: $url, error=$error');
              return Container(
                width: double.infinity,
                height: width * 0.56,
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: const Center(child: Icon(Icons.broken_image)),
              );
            },
          ),
        );
      },
    );
  }
}

