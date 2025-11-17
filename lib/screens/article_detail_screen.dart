import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/article.dart';
import '../services/sync_service.dart';
import '../services/database_service.dart';

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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _markAsRead();
  }

  Future<void> _markAsRead() async {
    if (!_article.isRead) {
      await _syncService.markArticleAsRead(_article.id, true);
      setState(() {
        _article = _article.copyWith(isRead: true);
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

