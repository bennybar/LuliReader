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
  bool _isLoadingMore = false;
  bool _hasMoreArticles = true;
  Map<String, String> _feedTitles = {};
  int _previewLines = 3;
  double _listPadding = 16.0;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _previewLines = _previewNotifier.lines;
    _listPadding = _listPaddingNotifier.padding;
    _scrollController.addListener(_onScroll);
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
    _loadArticles(reset: true);
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

  Future<void> _loadArticles({bool reset = false}) async {
    if (!mounted) return;

    if (reset) {
      setState(() {
        _articles = [];
        _isLoading = true;
        _hasMoreArticles = true;
      });
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final articles = await _db.getArticles(
        isStarred: true,
        limit: _pageSize,
        offset: reset ? 0 : _articles.length,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _articles = articles;
        } else {
          _articles.addAll(articles);
        }
        _hasMoreArticles = articles.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading articles: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreArticles() async {
    if (_isLoadingMore || !_hasMoreArticles || !mounted) return;

    setState(() => _isLoadingMore = true);
    try {
      final articles = await _db.getArticles(
        isStarred: true,
        limit: _pageSize,
        offset: _articles.length,
      );
      if (mounted) {
        setState(() {
          _articles.addAll(articles);
          _hasMoreArticles = articles.length == _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      print('Error loading more articles: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreArticles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PlatformAppBar(title: 'Starred'),
      body: RefreshIndicator(
        onRefresh: () => _loadArticles(reset: true),
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
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: _listViewPadding(),
                  itemCount: _articles.length + (_hasMoreArticles ? 1 : 0),
                  separatorBuilder: (_, __) => SizedBox(height: _cardSpacing),
                  itemBuilder: (context, index) {
                    if (index >= _articles.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
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
                        ).then((_) => _loadArticles(reset: true));
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
