import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'package:html/parser.dart' as html_parser;
import '../models/article.dart';
import '../models/feed.dart';
import 'readability.dart';
import 'shared_preferences_service.dart';

class RssHelper {
  final http.Client _client;
  final SharedPreferencesService _prefs = SharedPreferencesService();

  RssHelper(this._client);

  Future<RssFeed> searchFeed(String feedLink) async {
    final response = await _client.get(Uri.parse(feedLink));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch feed: ${response.statusCode}');
    }

    final contentType = response.headers['content-type'] ?? '';
    final charset = _extractCharset(contentType) ?? 'utf-8';
    final body = _decodeResponse(response.bodyBytes, charset);

    return _parseRssFeed(body);
  }

  Future<List<Article>> queryRssXml(
    Feed feed,
    int accountId,
    String? latestLink,
    DateTime preDate,
  ) async {
    try {
      await _prefs.init();
      final timeoutSeconds = await _prefs.getInt('feedTimeoutSeconds') ?? 10;
      
      final response = await _client
          .get(Uri.parse(feed.url))
          .timeout(Duration(seconds: timeoutSeconds));
      
      if (response.statusCode != 200) {
        return [];
      }

      final contentType = response.headers['content-type'] ?? '';
      final charset = _extractCharset(contentType) ?? 'utf-8';
      final body = _decodeResponse(response.bodyBytes, charset);

      final rssFeed = _parseRssFeed(body);
      final articles = <Article>[];

      for (final item in rssFeed.items) {
        if (latestLink != null && item.link == latestLink) {
          break;
        }

        final article = _buildArticleFromItem(feed, accountId, item, preDate);
        articles.add(article);
      }

      return articles;
    } catch (e) {
      print('Error querying RSS: $e');
      // Re-throw timeout errors so they can be handled by the sync service
      if (e.toString().contains('TimeoutException') || e.toString().contains('timeout')) {
        rethrow;
      }
      return [];
    }
  }

  RssFeed _parseRssFeed(String xmlString) {
    try {
      final document = xml.XmlDocument.parse(xmlString);
      
      // Try RSS format first
      var channel = document.findElements('channel').firstOrNull;
      var feedTitle = 'Untitled Feed';
      var items = <RssItem>[];
      
      if (channel != null) {
        // RSS 2.0 format
        feedTitle = channel.findElements('title').firstOrNull?.innerText ?? 
                   document.findElements('title').firstOrNull?.innerText ?? 
                   'Untitled Feed';
        items = channel.findElements('item').map((item) {
          return RssItem(
            title: item.findElements('title').firstOrNull?.innerText,
            link: item.findElements('link').firstOrNull?.innerText,
            description: item.findElements('description').firstOrNull?.innerText,
            pubDate: _parseDate(item.findElements('pubDate').firstOrNull?.innerText),
            guid: item.findElements('guid').firstOrNull?.innerText,
            author: item.findElements('author').firstOrNull?.innerText ??
                    item.findElements('dc:creator').firstOrNull?.innerText,
            content: item.findElements('content:encoded').firstOrNull?.innerText,
          );
        }).toList();
      } else {
        // Try Atom format
        final feed = document.findElements('feed').firstOrNull;
        if (feed != null) {
          feedTitle = feed.findElements('title').firstOrNull?.innerText ?? 'Untitled Feed';
          items = feed.findElements('entry').map((entry) {
            final link = entry.findElements('link').firstOrNull?.getAttribute('href') ??
                        entry.findElements('link').firstOrNull?.innerText;
            return RssItem(
              title: entry.findElements('title').firstOrNull?.innerText,
              link: link,
              description: entry.findElements('summary').firstOrNull?.innerText ??
                          entry.findElements('content').firstOrNull?.innerText,
              pubDate: _parseDate(entry.findElements('published').firstOrNull?.innerText ??
                                 entry.findElements('updated').firstOrNull?.innerText),
              guid: entry.findElements('id').firstOrNull?.innerText,
              author: entry.findElements('author').firstOrNull
                      ?.findElements('name').firstOrNull?.innerText,
              content: entry.findElements('content').firstOrNull?.innerText,
            );
          }).toList();
        } else {
          // Try to find any feed-like structure
          final allTitles = document.findAllElements('title');
          if (allTitles.isNotEmpty) {
            feedTitle = allTitles.first.innerText;
          }
          
          // Try to find items/entries in any format
          final allItems = document.findAllElements('item');
          if (allItems.isEmpty) {
            final allEntries = document.findAllElements('entry');
            items = allEntries.map((entry) {
              final link = entry.findElements('link').firstOrNull?.getAttribute('href') ??
                          entry.findElements('link').firstOrNull?.innerText;
              return RssItem(
                title: entry.findElements('title').firstOrNull?.innerText,
                link: link,
                description: entry.findElements('summary').firstOrNull?.innerText ??
                            entry.findElements('content').firstOrNull?.innerText,
                pubDate: _parseDate(entry.findElements('published').firstOrNull?.innerText ??
                                   entry.findElements('updated').firstOrNull?.innerText),
                guid: entry.findElements('id').firstOrNull?.innerText,
                author: entry.findElements('author').firstOrNull
                        ?.findElements('name').firstOrNull?.innerText,
                content: entry.findElements('content').firstOrNull?.innerText,
              );
            }).toList();
          } else {
            items = allItems.map((item) {
              return RssItem(
                title: item.findElements('title').firstOrNull?.innerText,
                link: item.findElements('link').firstOrNull?.innerText,
                description: item.findElements('description').firstOrNull?.innerText,
                pubDate: _parseDate(item.findElements('pubDate').firstOrNull?.innerText),
                guid: item.findElements('guid').firstOrNull?.innerText,
                author: item.findElements('author').firstOrNull?.innerText ??
                        item.findElements('dc:creator').firstOrNull?.innerText,
                content: item.findElements('content:encoded').firstOrNull?.innerText,
              );
            }).toList();
          }
        }
      }
      
      return RssFeed(title: feedTitle, items: items);
    } catch (e) {
      print('Error parsing RSS feed: $e');
      // Return empty feed instead of throwing
      return RssFeed(title: 'Error parsing feed', items: []);
    }
  }

  DateTime? _parseDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      // Try parsing common date formats
      return DateTime.parse(dateString);
    } catch (e) {
      // Try parsing RFC 822 format
      try {
        final months = {
          'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
          'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
        };
        final parts = dateString.split(' ');
        if (parts.length >= 5) {
          final day = int.parse(parts[1]);
          final month = months[parts[2]] ?? 1;
          final year = int.parse(parts[3]);
          final time = parts[4].split(':');
          final hour = int.parse(time[0]);
          final minute = int.parse(time[1]);
          final second = time.length > 2 ? int.parse(time[2]) : 0;
          return DateTime(year, month, day, hour, minute, second);
        }
      } catch (e2) {
        // Ignore
      }
      return null;
    }
  }

  Article _buildArticleFromItem(
    Feed feed,
    int accountId,
    RssItem item,
    DateTime preDate,
  ) {
    final desc = item.description ?? '';
    final content = item.content ?? desc;
    
    // Extract short description using readability
    final textToParse = desc.isEmpty ? content : desc;
    final shortDescText = Readability.parseToText(textToParse, item.link ?? '');
    final shortDesc = shortDescText.length > 280 
        ? '${shortDescText.substring(0, 280)}...' 
        : shortDescText;

    // Find thumbnail
    final img = _findThumbnail(item, content);

    // Parse date
    DateTime articleDate = preDate;
    if (item.pubDate != null) {
      articleDate = item.pubDate!;
      if (articleDate.isAfter(preDate)) {
        articleDate = preDate;
      }
    }

    // Generate syncHash: base64 of title + feed.url
    final articleTitle = _decodeHtml(item.title ?? feed.name);
    final syncHash = _generateSyncHash(articleTitle, feed.url);

    return Article(
      id: '$accountId\$${item.guid ?? item.link ?? DateTime.now().millisecondsSinceEpoch}',
      accountId: accountId,
      feedId: feed.id,
      date: articleDate,
      title: articleTitle,
      author: item.author,
      rawDescription: content,
      shortDescription: shortDesc,
      img: img,
      link: item.link ?? '',
      updateAt: preDate,
      syncHash: syncHash,
    );
  }

  /// Generate a base64 hash from title + feed URL for duplicate detection
  String _generateSyncHash(String title, String feedUrl) {
    final combined = '$title|$feedUrl';
    final bytes = utf8.encode(combined);
    return base64Encode(bytes);
  }

  String? _findThumbnail(RssItem item, String content) {
    // Check content for images
    if (content.isNotEmpty) {
      final doc = html_parser.parse(content);
      final img = doc.querySelector('img');
      if (img != null) {
        final src = img.attributes['src'];
        if (src != null && !src.startsWith('data:')) {
          return src;
        }
      }
    }

    return null;
  }

  String _decodeHtml(String html) {
    final doc = html_parser.parse(html);
    return doc.body?.text ?? html;
  }

  String? _extractCharset(String contentType) {
    final match = RegExp(r'charset=([^;]+)').firstMatch(contentType.toLowerCase());
    return match?.group(1)?.trim();
  }

  String _decodeResponse(List<int> bytes, String charset) {
    try {
      return utf8.decode(bytes);
    } catch (e) {
      // Fallback to latin1 if utf8 fails
      return latin1.decode(bytes);
    }
  }

  Future<String?> queryRssIconLink(String? feedLink) async {
    if (feedLink == null || feedLink.isEmpty) return null;
    
    try {
      final uri = Uri.parse(feedLink);
      final domain = '${uri.scheme}://${uri.host}';
      
      // Try common favicon locations
      final faviconPaths = [
        '/favicon.ico',
        '/apple-touch-icon.png',
        '/favicon.png',
      ];

      for (final path in faviconPaths) {
        try {
          final response = await _client.head(Uri.parse('$domain$path'));
          if (response.statusCode == 200) {
            return '$domain$path';
          }
        } catch (e) {
          continue;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}

class RssFeed {
  final String title;
  final List<RssItem> items;

  RssFeed({required this.title, required this.items});
}

class RssItem {
  final String? title;
  final String? link;
  final String? description;
  final DateTime? pubDate;
  final String? guid;
  final String? author;
  final String? content;

  RssItem({
    this.title,
    this.link,
    this.description,
    this.pubDate,
    this.guid,
    this.author,
    this.content,
  });
}
