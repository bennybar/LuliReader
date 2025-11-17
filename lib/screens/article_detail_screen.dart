import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/article.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
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

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _initializePreferences();
  }

  Future<void> _initializePreferences() async {
    final autoMark = await _storage.getAutoMarkRead();
    if (!mounted) return;
    setState(() => _autoMarkRead = autoMark);
    await _loadLatestArticle();
    if (autoMark) {
      await _markAsRead();
    }
  }

  Future<void> _markAsRead() async {
    if (!_article.isRead) {
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
              CachedNetworkImage(
                imageUrl: _article.imageUrl!,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                placeholder: (context, url) => const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => const SizedBox.shrink(),
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

