import 'package:flutter/material.dart';

import '../models/article.dart';
import '../notifiers/preview_lines_notifier.dart';
import '../notifiers/starred_refresh_notifier.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';
import '../utils/article_text_utils.dart';
import '../widgets/article_card.dart';
import '../widgets/platform_app_bar.dart';
import 'article_detail_screen.dart';

class StarredScreen extends StatefulWidget {
  const StarredScreen({super.key});

  @override
  State<StarredScreen> createState() => _StarredScreenState();
}

class _StarredScreenState extends State<StarredScreen> {
  final DatabaseService _db = DatabaseService();
  final StarredRefreshNotifier _starredNotifier = StarredRefreshNotifier.instance;
  final PreviewLinesNotifier _previewNotifier = PreviewLinesNotifier.instance;
  final StorageService _storage = StorageService();
  List<Article> _articles = [];
  bool _isLoading = true;
  Map<String, String> _feedTitles = {};
  int _previewLines = 3;

  @override
  void initState() {
    super.initState();
    _previewLines = _previewNotifier.lines;
    _loadInitialData();
    _starredNotifier.addListener(_handleRefreshNotification);
    _previewNotifier.addListener(_handlePreviewLinesChanged);
  }

  @override
  void dispose() {
    _starredNotifier.removeListener(_handleRefreshNotification);
    _previewNotifier.removeListener(_handlePreviewLinesChanged);
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadFeedTitles(),
      _loadPreviewLines(),
      _loadArticles(),
    ]);
  }

  Future<void> _loadFeedTitles() async {
    final feeds = await _db.getAllFeeds();
    if (!mounted) return;
    setState(() {
      _feedTitles = {
        for (final feed in feeds) feed.id: feed.title,
      };
    });
  }

  void _handleRefreshNotification() {
    _loadArticles();
  }

  void _handlePreviewLinesChanged() {
    final lines = _previewNotifier.lines;
    if (!mounted || _previewLines == lines) return;
    setState(() => _previewLines = lines);
  }

  Future<void> _loadPreviewLines() async {
    final lines = await _storage.getPreviewLines();
    if (!mounted) return;
    setState(() => _previewLines = lines);
    _previewNotifier.setLines(lines);
  }

  Future<void> _loadArticles() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final articles = await _db.getArticles(isStarred: true, limit: 100);
    if (!mounted) return;
    setState(() {
      _articles = articles;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PlatformAppBar(
        title: 'Starred',
      ),
      body: RefreshIndicator(
        onRefresh: _loadArticles,
        child: _isLoading
            ? ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _articles.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No starred articles')),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _articles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      return ArticleCard(
                        article: article,
                        summary: stripHtml(article.summary ?? article.content ?? ''),
                        sourceName: _feedTitles[article.feedId] ?? 'Unknown source',
                        summaryLines: _previewLines,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ArticleDetailScreen(article: article),
                            ),
                          ).then((_) => _loadArticles());
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

