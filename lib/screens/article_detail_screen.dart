import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/article.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../utils/image_utils.dart';
import 'offline_article_screen.dart';

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
  bool _isLoading = false;
  bool _autoMarkRead = true;
  bool _hasSyncConfig = false;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _initializePreferences();
  }

  Future<void> _initializePreferences() async {
    final autoMark = await _storage.getAutoMarkRead();
    final config = await _storage.getUserConfig();
    if (config != null) {
      _syncService.setUserConfig(config);
      _hasSyncConfig = true;
    }
    if (!mounted) return;
    setState(() => _autoMarkRead = autoMark);
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
    setState(() {
      _article = _article.copyWith(isStarred: newStarred);
      _isLoading = false;
    });
    await _loadLatestArticle();
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
    // Remove HTML tags
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }

  bool _isRTLText(String text) {
    final rtlRegex = RegExp(r'[\u0590-\u08FF]');
    return rtlRegex.hasMatch(text);
  }

  TextAlign _getTextAlign(String text) => _isRTLText(text) ? TextAlign.right : TextAlign.left;

  ui.TextDirection _getTextDirection(String text) =>
      _isRTLText(text) ? ui.TextDirection.rtl : ui.TextDirection.ltr;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_article.title),
        actions: [
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
          if (_article.link != null)
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              onPressed: () {
                // Could open in browser
              },
            ),
        ],
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
              padding: const EdgeInsets.all(16.0),
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
                    Text(
                      _article.author!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(_article.publishedDate),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _stripHtml(_article.content ?? _article.summary ?? ''),
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: _getTextAlign(_article.content ?? _article.summary ?? ''),
                    textDirection: _getTextDirection(_article.content ?? _article.summary ?? ''),
                  ),
                  if (_article.link != null) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Open in browser
                      },
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('Open Original Article'),
                    ),
                  ],
                ],
              ),
            ),
          ],
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
        child: SvgPicture.network(
          url,
          fit: BoxFit.cover,
          placeholderBuilder: (_) => const Center(child: CircularProgressIndicator()),
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

