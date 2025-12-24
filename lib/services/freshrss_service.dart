import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/group.dart';

/// Service for syncing with FreshRSS using Google Reader API
class FreshRssService {
  final http.Client _client;

  FreshRssService(this._client);

  /// Normalize URL and ensure API endpoint is present
  static String normalizeApiEndpoint(String url) {
    var normalizedUrl = url.trim();
    if (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
      normalizedUrl = 'https://$normalizedUrl';
    }
    
    // Remove trailing slash
    normalizedUrl = normalizedUrl.replaceAll(RegExp(r'/$'), '');
    
    // Check if API endpoint is already present
    if (normalizedUrl.contains('/api/greader.php') || normalizedUrl.contains('/api/greader')) {
      return normalizedUrl;
    }
    
    // Add API endpoint
    return '$normalizedUrl/api/greader.php';
  }

  /// Authenticate with FreshRSS and get auth token
  Future<String> authenticate(String apiEndpoint, String username, String password) async {
    final uri = Uri.parse('$apiEndpoint/accounts/ClientLogin');
    
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'Email': username,
        'Passwd': password,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Authentication failed: ${response.statusCode} - ${response.body}');
    }

    // Parse response to get Auth token
    final lines = response.body.split('\n');
    for (final line in lines) {
      if (line.startsWith('Auth=')) {
        return line.substring(5);
      }
    }

    throw Exception('No auth token in response');
  }

  /// Get list of subscriptions (feeds and categories)
  Future<Map<String, dynamic>> getSubscriptions(String apiEndpoint, String authToken) async {
    final uri = Uri.parse('$apiEndpoint/reader/api/0/subscription/list').replace(
      queryParameters: {'output': 'json'},
    );

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'GoogleLogin auth=$authToken',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get subscriptions: ${response.statusCode}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Get articles from a stream
  Future<Map<String, dynamic>> getStreamContents(
    String apiEndpoint,
    String authToken, {
    String? streamId,
    int? n = 100,
    String? continuation,
    String? xt, // If null, fetch all items (both read and unread)
  }) async {
    final queryParams = <String, String>{
      'output': 'json',
      'n': n.toString(),
    };
    
    if (streamId != null) {
      queryParams['streamId'] = streamId;
    }
    if (continuation != null) {
      queryParams['c'] = continuation;
    }
    if (xt != null) {
      queryParams['xt'] = xt;
    }

    final uri = Uri.parse('$apiEndpoint/reader/api/0/stream/contents').replace(
      queryParameters: queryParams,
    );

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'GoogleLogin auth=$authToken',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get stream contents: ${response.statusCode}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Get item IDs from a stream (lighter than full contents)
  /// Returns a map with 'ids' (Set of timestampUsec strings) and 'continuation' (String?)
  Future<Map<String, dynamic>> getStreamItemIds(
    String apiEndpoint,
    String authToken, {
    String? streamId,
    String? xt,
    int? n = 1000,
    String? continuation,
  }) async {
    final queryParams = <String, String>{
      'output': 'json',
      'n': n.toString(),
    };
    
    if (streamId != null) {
      queryParams['s'] = streamId;
    }
    if (xt != null) {
      queryParams['xt'] = xt;
    }
    if (continuation != null) {
      queryParams['c'] = continuation;
    }

    final uri = Uri.parse('$apiEndpoint/reader/api/0/stream/items/ids').replace(
      queryParameters: queryParams,
    );

    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'GoogleLogin auth=$authToken',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get stream item IDs: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final itemRefs = data['itemRefs'] as List<dynamic>? ?? [];
    final ids = <String>{};
    
    for (final ref in itemRefs) {
      final refMap = ref as Map<String, dynamic>;
      final timestampUsec = refMap['id'] as String?;
      if (timestampUsec != null) {
        // The items/ids endpoint returns timestampUsec values
        ids.add(timestampUsec);
      }
    }
    
    return {
      'ids': ids,
      'continuation': data['continuation'] as String?,
    };
  }

  /// Mark articles as read
  Future<void> markAsRead(String apiEndpoint, String authToken, List<String> articleIds) async {
    if (articleIds.isEmpty) return;

    final uri = Uri.parse('$apiEndpoint/reader/api/0/edit-tag');
    
    // Format article IDs - Google Reader API uses format: stream/item/ITEM_ID
    // But we need to send each ID separately
    final bodyParts = <String>[];
    for (final id in articleIds) {
      bodyParts.add('i=stream/item/$id');
    }
    bodyParts.add('a=user/-/state/com.google/read');
    
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'GoogleLogin auth=$authToken',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: bodyParts.join('&'),
    );
    _ensureSuccess(response, 'mark as read');
  }

  /// Mark articles as unread
  Future<void> markAsUnread(String apiEndpoint, String authToken, List<String> articleIds) async {
    if (articleIds.isEmpty) return;

    final uri = Uri.parse('$apiEndpoint/reader/api/0/edit-tag');
    
    // Format article IDs - Google Reader API uses format: stream/item/ITEM_ID
    final bodyParts = <String>[];
    for (final id in articleIds) {
      bodyParts.add('i=stream/item/$id');
    }
    bodyParts.add('r=user/-/state/com.google/read'); // Remove read tag
    
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'GoogleLogin auth=$authToken',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: bodyParts.join('&'),
    );
    _ensureSuccess(response, 'mark as unread');
  }

  /// Star/unstar articles
  Future<void> starArticles(String apiEndpoint, String authToken, List<String> articleIds, bool star) async {
    if (articleIds.isEmpty) return;

    final uri = Uri.parse('$apiEndpoint/reader/api/0/edit-tag');
    
    // Format article IDs - Google Reader API uses format: stream/item/ITEM_ID
    final bodyParts = <String>[];
    for (final id in articleIds) {
      bodyParts.add('i=stream/item/$id');
    }
    final action = star ? 'a=user/-/state/com.google/starred' : 'r=user/-/state/com.google/starred';
    bodyParts.add(action);
    
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'GoogleLogin auth=$authToken',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: bodyParts.join('&'),
    );
    _ensureSuccess(response, star ? 'star' : 'unstar');
  }

  /// Subscribe to a feed via FreshRSS API
  Future<void> subscribeToFeed(
    String apiEndpoint,
    String authToken,
    String feedUrl, {
    String? title,
    String? categoryLabel,
  }) async {
    final uri = Uri.parse('$apiEndpoint/reader/api/0/subscription/edit');
    
    // Build body parameters
    final bodyParts = <String>[
      'ac=subscribe',
      's=feed/$feedUrl',
    ];
    
    if (title != null && title.isNotEmpty) {
      bodyParts.add('t=${Uri.encodeComponent(title)}');
    }
    
    if (categoryLabel != null && categoryLabel.isNotEmpty) {
      // Category format: user/-/label/CATEGORY_NAME
      bodyParts.add('a=user/-/label/${Uri.encodeComponent(categoryLabel)}');
    }
    
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'GoogleLogin auth=$authToken',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: bodyParts.join('&'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to subscribe to feed: ${response.statusCode} - ${response.body}');
    }
  }

  /// Convert FreshRSS subscription list to Groups and Feeds
  Future<Map<String, List<dynamic>>> parseSubscriptions(
    Map<String, dynamic> subscriptions,
    int accountId,
  ) async {
    final groups = <Group>[];
    final feeds = <Feed>[];
    final groupMap = <String, Group>{};

    final subscriptionsList = subscriptions['subscriptions'] as List<dynamic>?;
    if (subscriptionsList == null) {
      return {'groups': groups, 'feeds': feeds};
    }

    // Create groups from categories
    for (final sub in subscriptionsList) {
      final subMap = sub as Map<String, dynamic>;
      final categories = subMap['categories'] as List<dynamic>? ?? [];
      
      for (final cat in categories) {
        final catMap = cat as Map<String, dynamic>;
        final catId = catMap['id'] as String?;
        final catLabel = catMap['label'] as String?;
        
        if (catId != null && catLabel != null && !groupMap.containsKey(catId)) {
          final group = Group(
            id: catId,
            name: catLabel,
            accountId: accountId,
          );
          groups.add(group);
          groupMap[catId] = group;
        }
      }

      // Create feed
      final feedId = subMap['id'] as String?;
      final feedTitle = subMap['title'] as String?;
      final feedUrl = subMap['htmlUrl'] as String?;
      String firstCategoryId = '';
      final categoriesList = subMap['categories'] as List<dynamic>?;
      if (categoriesList != null && categoriesList.isNotEmpty) {
        final firstCat = categoriesList.first as Map<String, dynamic>?;
        if (firstCat != null) {
          firstCategoryId = firstCat['id'] as String? ?? '';
        }
      }

      if (feedId != null && feedTitle != null && feedUrl != null) {
        final feed = Feed(
          id: feedId,
          name: feedTitle,
          url: feedUrl,
          groupId: firstCategoryId.isNotEmpty ? firstCategoryId : 'uncategorized',
          accountId: accountId,
        );
        feeds.add(feed);
      }
    }

    // Ensure uncategorized group exists if needed
    if (feeds.any((f) => f.groupId == 'uncategorized') && !groupMap.containsKey('uncategorized')) {
      final uncategorizedGroup = Group(
        id: 'uncategorized',
        name: 'Uncategorized',
        accountId: accountId,
      );
      groups.insert(0, uncategorizedGroup);
    }

    return {'groups': groups, 'feeds': feeds};
  }

  /// Convert FreshRSS articles to Article models
  /// Returns a map with articles and a map of article ID to timestampUsec for matching
  Map<String, dynamic> parseArticlesWithMetadata(Map<String, dynamic> streamContents, int accountId) {
    final articles = <Article>[];
    final timestampMap = <String, String>{}; // article ID -> timestampUsec
    final items = streamContents['items'] as List<dynamic>?;
    
    if (items == null) return {'articles': articles, 'timestampMap': timestampMap};

    for (final item in items) {
      final itemMap = item as Map<String, dynamic>;
      final rawId = itemMap['id'] as String?;
      final id = rawId != null ? _normalizeItemId(rawId) : null;
      final timestampUsec = itemMap['timestampUsec'] as String?;
      final title = itemMap['title'] as String? ?? '';
      final published = itemMap['published'] as int?;
      final updated = itemMap['updated'] as int?;
      final author = itemMap['author'] as String?;
      final summary = itemMap['summary'] as Map<String, dynamic>?;
      final content = itemMap['content'] as Map<String, dynamic>?;
      final alternate = itemMap['alternate'] as List<dynamic>?;
      final origin = itemMap['origin'] as Map<String, dynamic>?;
      final categories = itemMap['categories'] as List<dynamic>? ?? [];

      if (id == null) continue;
      
      // Store timestampUsec for matching with items/ids endpoint
      if (timestampUsec != null) {
        timestampMap[id] = timestampUsec;
      }

      // Extract content
      final contentText = content?['content'] as String? ?? summary?['content'] as String? ?? '';
      String link = '';
      if (alternate != null && alternate.isNotEmpty) {
        final firstAlt = alternate.first as Map<String, dynamic>?;
        if (firstAlt != null) {
          link = firstAlt['href'] as String? ?? '';
        }
      }
      
      // Extract feed info
      final feedId = origin?['streamId'] as String? ?? '';
      final feedTitle = origin?['title'] as String? ?? '';

      // Parse dates
      // Prefer published/updated time; convert to local to match "ago" calculations
      DateTime publishedDate;
      if (published != null) {
        publishedDate = DateTime.fromMillisecondsSinceEpoch(published * 1000, isUtc: true).toLocal();
      } else if (updated != null) {
        publishedDate = DateTime.fromMillisecondsSinceEpoch(updated * 1000, isUtc: true).toLocal();
      } else {
        publishedDate = DateTime.now();
      }

      // Check states from server categories
      // Read status: article is READ if "user/-/state/com.google/read" is in categories
      final isRead = categories.any((cat) {
        final catStr = cat.toString();
        return catStr == 'user/-/state/com.google/read' || catStr.contains('/state/com.google/read');
      });
      // Unread status: article is UNREAD if "user/-/state/com.google/unread" is in categories
      final isUnreadTag = categories.any((cat) {
        final catStr = cat.toString();
        return catStr == 'user/-/state/com.google/unread' || catStr.contains('/state/com.google/unread');
      });
      // Starred status: article is STARRED if "user/-/state/com.google/starred" is in categories
      final isStarred = categories.any((cat) {
        final catStr = cat.toString();
        return catStr == 'user/-/state/com.google/starred' || catStr.contains('/state/com.google/starred');
      });

      // Extract image from content (simple regex)
      String? imageUrl;
      // Match img tags with src attribute (handles both single and double quotes)
      final imgRegexDouble = RegExp(r'<img[^>]+src="([^"]+)"');
      final imgRegexSingle = RegExp(r"<img[^>]+src='([^']+)'");
      var imgMatch = imgRegexDouble.firstMatch(contentText);
      if (imgMatch == null) {
        imgMatch = imgRegexSingle.firstMatch(contentText);
      }
      if (imgMatch != null) {
        imageUrl = imgMatch.group(1);
      }

      // Extract short description (first paragraph or summary)
      String shortDescription = '';
      if (summary != null && summary['content'] != null) {
        final summaryText = summary['content'] as String;
        shortDescription = _stripHtml(summaryText).trim();
        if (shortDescription.length > 200) {
          shortDescription = '${shortDescription.substring(0, 200)}...';
        }
      }

      final article = Article(
        id: id,
        date: publishedDate,
        title: title,
        author: author,
        rawDescription: contentText,
        shortDescription: shortDescription.isNotEmpty 
            ? shortDescription 
            : _stripHtml(contentText).length > 200 
                ? '${_stripHtml(contentText).substring(0, 200)}...'
                : _stripHtml(contentText),
        img: imageUrl,
        link: link.isNotEmpty ? link : id,
        feedId: feedId.isNotEmpty ? feedId : 'unknown',
        accountId: accountId,
        // Article is unread if it doesn't have the read tag
        // FreshRSS doesn't use explicit unread tags, just absence of read tag means unread
        isUnread: !isRead,
        isStarred: isStarred,
      );

      articles.add(article);
    }

    return {'articles': articles, 'timestampMap': timestampMap};
  }

  /// Convert FreshRSS articles to Article models (backward compatibility)
  List<Article> parseArticles(Map<String, dynamic> streamContents, int accountId) {
    final result = parseArticlesWithMetadata(streamContents, accountId);
    return result['articles'] as List<Article>;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }

  void _ensureSuccess(http.Response response, String action) {
    if (response.statusCode != 200) {
      throw Exception('Failed to $action: ${response.statusCode} - ${response.body}');
    }
  }

  /// Normalize item IDs to the short form used by edit-tag endpoints.
  String _normalizeItemId(String id) {
    final idx = id.lastIndexOf('item/');
    if (idx != -1) {
      return id.substring(idx + 5);
    }
    return id;
  }
}

