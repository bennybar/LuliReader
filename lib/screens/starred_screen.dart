import 'package:flutter/material.dart';
import '../models/article.dart';
import '../notifiers/starred_refresh_notifier.dart';
import '../services/database_service.dart';

class StarredScreen extends StatefulWidget {
  const StarredScreen({super.key});

  @override
  State<StarredScreen> createState() => _StarredScreenState();
}

class _StarredScreenState extends State<StarredScreen> {
  final DatabaseService _db = DatabaseService();
  final StarredRefreshNotifier _notifier = StarredRefreshNotifier.instance;
  List<Article> _articles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArticles();
    _notifier.addListener(_handleRefreshNotification);
  }

  @override
  void dispose() {
    _notifier.removeListener(_handleRefreshNotification);
    super.dispose();
  }

  void _handleRefreshNotification() {
    _loadArticles();
  }

  Future<void> _loadArticles() async {
    setState(() => _isLoading = true);
    final articles = await _db.getArticles(isStarred: true, limit: 100);
    setState(() {
      _articles = articles;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Starred'),
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
                : ListView.builder(
                    itemCount: _articles.length,
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      return ListTile(
                        leading: const Icon(Icons.star, color: Colors.amber),
                        title: Text(article.title),
                        subtitle: Text(
                          article.summary ?? article.content ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          // TODO: navigate to detail if needed
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

