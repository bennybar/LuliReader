import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/database_service.dart';
import '../models/feed.dart';

class FeedsScreen extends StatefulWidget {
  const FeedsScreen({super.key});

  @override
  State<FeedsScreen> createState() => _FeedsScreenState();
}

class _FeedsScreenState extends State<FeedsScreen> {
  final DatabaseService _db = DatabaseService();
  List<Feed> _feeds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFeeds();
  }

  Future<void> _loadFeeds() async {
    setState(() => _isLoading = true);
    final feeds = await _db.getAllFeeds();
    setState(() {
      _feeds = feeds;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feeds'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _feeds.isEmpty
              ? const Center(child: Text('No feeds found'))
              : ListView.builder(
                  itemCount: _feeds.length,
                  itemBuilder: (context, index) {
                    final feed = _feeds[index];
                    return ListTile(
                      leading: feed.iconUrl != null
                          ? CachedNetworkImage(
                              imageUrl: feed.iconUrl!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const CircularProgressIndicator(),
                              errorWidget: (context, url, error) => const Icon(Icons.rss_feed),
                            )
                          : const Icon(Icons.rss_feed),
                      title: Text(feed.title),
                      subtitle: Text(feed.description ?? ''),
                      trailing: feed.unreadCount > 0
                          ? Chip(
                              label: Text('${feed.unreadCount}'),
                              backgroundColor: Colors.blue,
                            )
                          : null,
                      onTap: () {
                        // Navigate to feed articles
                      },
                    );
                  },
                ),
    );
  }
}

