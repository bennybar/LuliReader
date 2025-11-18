import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:video_player/video_player.dart';

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
        builder:
            (_) => WebArticleScreen(title: _article.title, url: uri.toString()),
      ),
    );
  }

  Future<void> _repullFullText() async {
    final link = _article.link;
    if (link == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No original link available for this article'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final html = await _offlineCacheService.repullArticleContentWithChromeUA(
        _article,
      );
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
            builder:
                (_) => ReaderArticleScreen(title: _article.title, html: html),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Full text refresh failed: $e')));
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
        const SnackBar(
          content: Text(
            'Offline file missing. Please refresh offline content.',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => OfflineArticleScreen(
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

  TextAlign _getTextAlign(String text) =>
      _isRTLText(text) ? TextAlign.right : TextAlign.left;

  ui.TextDirection _getTextDirection(String text) =>
      _isRTLText(text) ? ui.TextDirection.rtl : ui.TextDirection.ltr;

  String _resolveContentMediaUrl(String rawUrl) {
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
    debugPrint('Article media URL resolved: raw=$trimmed -> final=$finalUrl');
    return finalUrl;
  }

  List<Widget> _buildInlineBody(BuildContext context) {
    final rawHtml = _article.content ?? _article.summary ?? '';
    if (rawHtml.isEmpty) {
      return [_buildTextBlock(context, _stripHtml(rawHtml))];
    }

    final widgets = <Widget>[];
    final seenImages = <String>{};
    final heroUrl = _article.imageUrl;
    final mediaRegex = RegExp(
      r'(<svg[\s\S]*?<\/svg>)|(<video[\s\S]*?<\/video>)|(<audio[\s\S]*?<\/audio>)|(<iframe[\s\S]*?<\/iframe>)|(<img[^>]*>)',
      caseSensitive: false,
    );

    int cursor = 0;
    for (final match in mediaRegex.allMatches(rawHtml)) {
      if (match.start > cursor) {
        _appendTextBlock(
          context,
          widgets,
          rawHtml.substring(cursor, match.start),
        );
      }

      final snippet = match.group(0)!;
      final tagName = _detectTagName(snippet);
      Widget? mediaWidget;

      switch (tagName) {
        case 'img':
          mediaWidget = _buildInlineImageWidget(snippet, seenImages, heroUrl);
          break;
        case 'svg':
          mediaWidget = _ArticleInlineSvg(svg: snippet);
          break;
        case 'video':
          mediaWidget = _buildInlineVideoWidget(snippet);
          break;
        case 'audio':
          mediaWidget = _buildInlineAudioWidget(context, snippet);
          break;
        case 'iframe':
          mediaWidget = _buildInlineIframeWidget(context, snippet);
          break;
      }

      if (mediaWidget != null) {
        widgets.add(mediaWidget);
        widgets.add(const SizedBox(height: 12));
      }

      cursor = match.end;
    }

    if (cursor < rawHtml.length) {
      _appendTextBlock(context, widgets, rawHtml.substring(cursor));
    }

    if (widgets.isEmpty) {
      return [_buildTextBlock(context, _stripHtml(rawHtml))];
    }

    if (widgets.isNotEmpty && widgets.last is SizedBox) {
      widgets.removeLast();
    }

    return widgets;
  }

  void _appendTextBlock(
    BuildContext context,
    List<Widget> widgets,
    String fragment,
  ) {
    final stripped = _stripHtml(fragment);
    if (stripped.trim().isEmpty) return;
    widgets.add(_buildTextBlock(context, stripped));
    widgets.add(const SizedBox(height: 12));
  }

  Widget _buildTextBlock(BuildContext context, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }
    return SelectableText(
      trimmed,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(fontSize: _articleFontSize, height: 1.6),
      textAlign: _getTextAlign(trimmed),
      textDirection: _getTextDirection(trimmed),
    );
  }

  Widget? _buildInlineImageWidget(
    String snippet,
    Set<String> seenImages,
    String? heroUrl,
  ) {
    final rawSrc =
        _extractAttribute(snippet, 'src') ??
        _extractAttribute(snippet, 'data-src');
    if (rawSrc == null || rawSrc.isEmpty) return null;
    final resolved = _resolveContentMediaUrl(rawSrc);
    if (resolved.isEmpty) return null;
    if (heroUrl != null && resolved == heroUrl) {
      debugPrint(
        'Skipping inline image equal to hero image: resolved=$resolved',
      );
      return null;
    }
    if (!seenImages.add(resolved)) {
      debugPrint(
        'Skipping duplicate inline image already seen: resolved=$resolved',
      );
      return null;
    }
    debugPrint('Article content image candidate (inline): resolved=$resolved');
    return _ArticleContentImage(url: resolved);
  }

  Widget? _buildInlineVideoWidget(String snippet) {
    final rawSrc =
        _extractAttribute(snippet, 'src') ??
        _extractSourceFromChild(snippet, 'source');
    if (rawSrc == null || rawSrc.isEmpty) return null;
    final resolved = _resolveContentMediaUrl(rawSrc);
    if (resolved.isEmpty) return null;
    final poster =
        _extractAttribute(snippet, 'poster') ??
        _extractAttribute(snippet, 'data-poster');
    final posterUrl = poster != null ? _resolveContentMediaUrl(poster) : null;
    final lower = snippet.toLowerCase();
    final autoPlay = lower.contains('autoplay');
    final loop = lower.contains('loop');
    return _ArticleVideoEmbed(
      url: resolved,
      posterUrl: posterUrl,
      autoPlay: autoPlay,
      loop: loop,
    );
  }

  Widget? _buildInlineAudioWidget(BuildContext context, String snippet) {
    final rawSrc =
        _extractAttribute(snippet, 'src') ??
        _extractSourceFromChild(snippet, 'source');
    if (rawSrc == null || rawSrc.isEmpty) return null;
    final resolved = _resolveContentMediaUrl(rawSrc);
    if (resolved.isEmpty) return null;
    return _ArticleMediaLinkCard(
      icon: Icons.audiotrack,
      title: 'Audio attachment',
      url: resolved,
      onOpen: () => _openMediaLink(context, resolved),
    );
  }

  Widget? _buildInlineIframeWidget(BuildContext context, String snippet) {
    final rawSrc = _extractAttribute(snippet, 'src');
    if (rawSrc == null || rawSrc.isEmpty) return null;
    final resolved = _resolveContentMediaUrl(rawSrc);
    if (resolved.isEmpty) return null;
    return _ArticleMediaLinkCard(
      icon: Icons.live_tv,
      title: 'Embedded content',
      url: resolved,
      onOpen: () => _openMediaLink(context, resolved),
    );
  }

  String? _extractAttribute(String source, String attribute) {
    final regex = RegExp(
      '$attribute\\s*=\\s*(["\'])(.*?)\\1',
      caseSensitive: false,
    );
    final quoted = regex.firstMatch(source);
    if (quoted != null) {
      return quoted.group(2);
    }
    final unquoted = RegExp(
      '$attribute\\s*=\\s*([^\\s>]+)',
      caseSensitive: false,
    ).firstMatch(source);
    return unquoted?.group(1);
  }

  String? _extractSourceFromChild(String snippet, String tag) {
    final regex = RegExp(
      '<$tag[^>]+src\\s*=\\s*(["\'])(.*?)\\1',
      caseSensitive: false,
    );
    final match = regex.firstMatch(snippet);
    return match?.group(2);
  }

  String? _detectTagName(String snippet) {
    final match = RegExp(
      r'^<\s*([a-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(snippet.trim());
    return match?.group(1)?.toLowerCase();
  }

  Future<void> _openMediaLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open media (invalid URL).')),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => WebArticleScreen(title: _article.title, url: uri.toString()),
      ),
    );
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
      appBar: PlatformAppBar(title: _article.title, actions: actions),
      body: SingleChildScrollView(
        physics:
            isIOS
                ? const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                )
                : const ClampingScrollPhysics(),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 18.0,
                vertical: 16.0,
              ),
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
                          alignment:
                              isRtlTitle
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                          child: Text(
                            _article.author!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Align(
                        alignment:
                            isRtlTitle
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                        child: Text(
                          _formatDate(_article.publishedDate),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
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
    children.add(
      _buildGlassIconButton(
        context: context,
        icon: Icons.open_in_browser,
        tooltip: 'Open original article',
        onTap: _isLoading ? null : _openInBrowser,
      ),
    );

    // Re-pull full text with Chrome UA
    children.add(const SizedBox(width: 12));
    children.add(
      _buildGlassIconButton(
        context: context,
        icon: Icons.article,
        tooltip: 'Re-pull full text',
        onTap: _isLoading ? null : _repullFullText,
        showBusy: _isLoading,
      ),
    );

    return Row(mainAxisAlignment: MainAxisAlignment.end, children: children);
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
        icon:
            showBusy
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Icon(icon),
        onPressed: onTap,
      );
    }

    final content =
        showBusy
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
      child: const Center(child: Icon(Icons.image_not_supported, size: 40)),
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
        child: SvgPicture.network(
          url,
          fit: BoxFit.cover,
          placeholderBuilder:
              (_) => const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          // ignore: deprecated_member_use
          colorFilter: null,
        ),
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
                placeholderBuilder:
                    (_) => const Center(child: CircularProgressIndicator()),
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

  Widget _buildBitmapFromCache(
    String url,
    BorderRadius border,
    Widget placeholder,
  ) {
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
        debugPrint(
          'Rendering article content SVG data URI, length=${svg.length}',
        );
        return SvgPicture.string(
          svg,
          width: double.infinity,
          fit: BoxFit.contain,
        );
      } else {
        final bytes = ImageUtils.decodeBitmapDataUri(url);
        if (bytes == null) {
          debugPrint(
            'Article content bitmap data URI could not be decoded: $url',
          );
          return const SizedBox.shrink();
        }
        debugPrint(
          'Rendering article content bitmap data URI, bytes=${bytes.length}',
        );
        return Image.memory(bytes, width: double.infinity, fit: BoxFit.cover);
      }
    }

    if (ImageUtils.looksLikeSvgUrl(url)) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SvgPicture.network(
              url,
              width: width,
              fit: BoxFit.contain,
              placeholderBuilder:
                  (_) => Container(
                    width: double.infinity,
                    height: width * 0.56,
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
            ),
          );
        },
      );
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
            placeholder:
                (_, __) => Container(
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
              debugPrint(
                'Article content image failed to load: $url, error=$error',
              );
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

class _ArticleInlineSvg extends StatelessWidget {
  final String svg;

  const _ArticleInlineSvg({required this.svg});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SvgPicture.string(
        svg,
        width: double.infinity,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _ArticleVideoEmbed extends StatefulWidget {
  final String url;
  final String? posterUrl;
  final bool autoPlay;
  final bool loop;

  const _ArticleVideoEmbed({
    required this.url,
    this.posterUrl,
    this.autoPlay = false,
    this.loop = false,
  });

  @override
  State<_ArticleVideoEmbed> createState() => _ArticleVideoEmbedState();
}

class _ArticleVideoEmbedState extends State<_ArticleVideoEmbed> {
  late final VideoPlayerController _controller;
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.setLooping(widget.loop);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() {
        _initializing = false;
      });
      if (widget.autoPlay) {
        _controller.play();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_initializing) {
      return _VideoPlaceholder(posterUrl: widget.posterUrl);
    }

    if (_error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Video failed to load. ${_error ?? ''}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final aspectRatio =
        (_controller.value.aspectRatio.isFinite &&
                _controller.value.aspectRatio > 0)
            ? _controller.value.aspectRatio
            : 16 / 9;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: aspectRatio,
                child: VideoPlayer(_controller),
              ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _togglePlayback,
                    child: AnimatedOpacity(
                      opacity: _controller.value.isPlaying ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        color: Colors.black38,
                        child: const Icon(
                          Icons.play_circle_fill,
                          color: Colors.white,
                          size: 64,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        VideoProgressIndicator(
          _controller,
          allowScrubbing: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ],
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  final String? posterUrl;

  const _VideoPlaceholder({this.posterUrl});

  @override
  Widget build(BuildContext context) {
    final height = 220.0;
    final borderRadius = BorderRadius.circular(12);
    final placeholder = Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: borderRadius,
      ),
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );

    if (posterUrl == null || posterUrl!.isEmpty) {
      return placeholder;
    }

    if (ImageUtils.isDataUri(posterUrl!)) {
      if (ImageUtils.isSvgDataUri(posterUrl!)) {
        final svg = ImageUtils.decodeSvgDataUri(posterUrl!);
        if (svg == null) {
          return placeholder;
        }
        return ClipRRect(
          borderRadius: borderRadius,
          child: SvgPicture.string(
            svg,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        );
      } else {
        final bytes = ImageUtils.decodeBitmapDataUri(posterUrl!);
        if (bytes == null) {
          return placeholder;
        }
        return ClipRRect(
          borderRadius: borderRadius,
          child: Image.memory(
            bytes,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        );
      }
    }

    if (ImageUtils.looksLikeSvgUrl(posterUrl!)) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: SvgPicture.network(
          posterUrl!,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholderBuilder: (_) => placeholder,
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: CachedNetworkImage(
        imageUrl: posterUrl!,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _ArticleMediaLinkCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String url;
  final VoidCallback? onOpen;

  const _ArticleMediaLinkCard({
    required this.icon,
    required this.title,
    required this.url,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            url,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open'),
            ),
          ),
        ],
      ),
    );
  }
}
