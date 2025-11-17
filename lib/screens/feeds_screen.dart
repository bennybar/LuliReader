import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/database_service.dart';
import '../models/feed.dart';
import '../utils/image_utils.dart';

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
                          ? _FeedIcon(url: feed.iconUrl!)
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

class _FeedIcon extends StatefulWidget {
  final String url;

  const _FeedIcon({required this.url});

  @override
  State<_FeedIcon> createState() => _FeedIconState();
}

class _FeedIconState extends State<_FeedIcon> {
  Future<RemoteImageFormat>? _formatFuture;

  @override
  void initState() {
    super.initState();
    _prepareFormatFuture();
  }

  @override
  void didUpdateWidget(covariant _FeedIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _prepareFormatFuture();
    }
  }

  void _prepareFormatFuture() {
    final url = widget.url;
    if (!ImageUtils.isDataUri(url) && !ImageUtils.looksLikeSvgUrl(url)) {
      _formatFuture = ImageUtils.detectRemoteFormat(url);
    } else {
      _formatFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      child: Icon(
        Icons.rss_feed,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
      ),
    );

    final url = widget.url;
    if (url.isEmpty) return placeholder;

    if (ImageUtils.isDataUri(url)) {
      if (ImageUtils.isSvgDataUri(url)) {
        final svg = ImageUtils.decodeSvgDataUri(url);
        if (svg == null) return placeholder;
        return ClipOval(
          child: SvgPicture.string(
            svg,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        );
      }
      final bytes = ImageUtils.decodeBitmapDataUri(url);
      if (bytes == null) return placeholder;
      return _buildBitmap(bytes);
    }

    if (ImageUtils.looksLikeSvgUrl(url)) {
      return ClipOval(
        child: SvgPicture.network(
          url,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholderBuilder: (_) => const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_formatFuture != null) {
      return FutureBuilder<RemoteImageFormat>(
        future: _formatFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final format = snapshot.data ?? RemoteImageFormat.unknown;
          if (format == RemoteImageFormat.svg) {
            return ClipOval(
              child: SvgPicture.network(
                url,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                placeholderBuilder: (_) => const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (format == RemoteImageFormat.bitmap || format == RemoteImageFormat.unknown) {
            return _buildBitmapFuture(url, placeholder);
          }
          return placeholder;
        },
      );
    }

    return _buildBitmapFuture(url, placeholder);
  }

  Widget _buildBitmap(Uint8List bytes) => ClipOval(
        child: Image.memory(
          bytes,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      );

  Widget _buildBitmapFuture(String url, Widget placeholder) => FutureBuilder<Uint8List?>(
        future: ImageUtils.decodedBitmapBytes(url),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) return placeholder;
          return _buildBitmap(bytes);
        },
      );
}


