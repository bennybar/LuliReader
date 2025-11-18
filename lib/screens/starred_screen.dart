import 'package:flutter/material.dart';

import '../models/article.dart';
import '../notifiers/article_list_padding_notifier.dart';
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
  final StarredRefreshNotifier _starredNotifier =
      StarredRefreshNotifier.instance;
  final PreviewLinesNotifier _previewNotifier = PreviewLinesNotifier.instance;
  final ArticleListPaddingNotifier _listPaddingNotifier =
      ArticleListPaddingNotifier.instance;
  final StorageService _storage = StorageService();
  List<Article> _articles = [];
  bool _isLoading = true;
  Map<String, String> _feedTitles = {};
  int _previewLines = 3;
  double _listPadding = 16.0;

  @override
  void initState() {
    super.initState();
    _previewLines = _previewNotifier.lines;
    _listPadding = _listPaddingNotifier.padding;
    _loadInitialData();
    _starredNotifier.addListener(_handleRefreshNotification);
    _previewNotifier.addListener(_handlePreviewLinesChanged);
    _listPaddingNotifier.addListener(_handleListPaddingChanged);
  }

  @override
  void dispose() {
    _starredNotifier.removeListener(_handleRefreshNotification);
    _previewNotifier.removeListener(_handlePreviewLinesChanged);
    _listPaddingNotifier.removeListener(_handleListPaddingChanged);
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadFeedTitles(),
      _loadPreviewLines(),
      _loadListPadding(),
      _loadArticles(),
    ]);
  }

  Future<void> _loadFeedTitles() async {
    final feeds = await _db.getAllFeeds();
    if (!mounted) return;
    setState(() {
      _feedTitles = {for (final feed in feeds) feed.id: feed.title};
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

  void _handleListPaddingChanged() {
    final padding = _listPaddingNotifier.padding;
    if (!mounted || (_listPadding - padding).abs() < 0.5) return;
    setState(() => _listPadding = padding);
  }

  Future<void> _loadPreviewLines() async {
    final lines = await _storage.getPreviewLines();
    if (!mounted) return;
    setState(() => _previewLines = lines);
    _previewNotifier.setLines(lines);
  }

  Future<void> _loadListPadding() async {
    final padding = await _storage.getArticleListPadding();
    if (!mounted) return;
    setState(() => _listPadding = padding);
    _listPaddingNotifier.setPadding(padding);
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
      appBar: const PlatformAppBar(title: 'Starred'),
      body: RefreshIndicator(
        onRefresh: _loadArticles,
        child:
            _isLoading
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
                  padding: _listViewPadding(),
                  itemCount: _articles.length,
                  separatorBuilder: (_, __) => SizedBox(height: _cardSpacing),
                  itemBuilder: (context, index) {
                    final article = _articles[index];
                    return ArticleCard(
                      article: article,
                      summary: stripHtml(
                        article.summary ?? article.content ?? '',
                      ),
                      sourceName:
                          _feedTitles[article.feedId] ?? 'Unknown source',
                      summaryLines: _previewLines,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => ArticleDetailScreen(article: article),
                          ),
                        ).then((_) => _loadArticles());
                      },
                    );
                  },
                ),
      ),
    );
  }

  EdgeInsets _listViewPadding() {
    final horizontal = _listPadding;
    final top = _listPadding * 0.75;
    final bottom = 64 + _listPadding;
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  double get _cardSpacing {
    final spacing = (_listPadding / 16.0) * 12.0;
    return spacing.clamp(8.0, 28.0).toDouble();
  }
}
