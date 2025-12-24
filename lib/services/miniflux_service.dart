import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/group.dart';

/// Service for syncing with Miniflux using Google Reader API
class MinifluxService {
  final http.Client _client;

  MinifluxService(this._client);

  /// Normalize URL and ensure API endpoint is present
  static String normalizeApiEndpoint(String url) {
    var normalizedUrl = url.trim();
    if (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
      normalizedUrl = 'https://$normalizedUrl';
    }
    
    // Remove trailing slash
    normalizedUrl = normalizedUrl.replaceAll(RegExp(r'/$'), '');
    
    // Check if API endpoint is already present
    if (normalizedUrl.contains('/reader/api/0') || 
        normalizedUrl.contains('/api/greader.php') || 
        normalizedUrl.contains('/api/greader') ||
        normalizedUrl.contains('/v1/')) {
      // If it already has an endpoint, return as-is
      return normalizedUrl;
    }
    
    // Miniflux uses /reader/api/0 for API calls
    // But ClientLogin is at base URL /accounts/ClientLogin
    // So we normalize to /reader/api/0 for API endpoint
    return '$normalizedUrl/reader/api/0';
  }

  /// Helper to check if token is Basic Auth (base64 encoded credentials)
  bool _isBasicAuth(String token) {
    // Miniflux uses GoogleLogin tokens (format: username/hash like "benny/abc123...")
    // Basic Auth tokens would be base64 encoded "username:password"
    // GoogleLogin tokens contain a slash, Basic Auth base64 never contains a slash
    return !token.contains('/') && token.length > 30;
  }

  /// Helper to get the correct API path based on endpoint format
  String _getApiPath(String apiEndpoint, String path) {
    if (apiEndpoint.contains('/api/greader.php')) {
      // FreshRSS format: /api/greader.php/reader/api/0/path
      return '$apiEndpoint/reader/api/0$path';
    } else {
      // Miniflux format: /reader/api/0/path
      return '$apiEndpoint$path';
    }
  }

  /// Helper to get authorization header based on auth type
  Map<String, String> _getAuthHeaders(String authToken) {
    if (_isBasicAuth(authToken)) {
      // Token is base64 encoded credentials for Basic Auth
      return {'Authorization': 'Basic $authToken'};
    } else {
      // Token is GoogleLogin auth token
      return {'Authorization': 'GoogleLogin auth=$authToken'};
    }
  }

  /// Authenticate with Miniflux and get auth token
  /// Returns a map with 'token' and optionally 'correctedEndpoint' if endpoint format was changed
  /// Miniflux uses ClientLogin at base URL, not under /reader/api/0
  Future<Map<String, String>> authenticateWithEndpoint(String apiEndpoint, String username, String password) async {
    // Miniflux ClientLogin is at the base URL, not under /reader/api/0
    // Extract base URL from apiEndpoint
    String baseUrl = apiEndpoint;
    if (baseUrl.contains('/reader/api/0')) {
      baseUrl = baseUrl.replaceAll(RegExp(r'/reader/api/0/?$'), '');
    } else if (baseUrl.contains('/api/greader.php')) {
      baseUrl = baseUrl.replaceAll(RegExp(r'/api/greader\.php/?$'), '');
    }
    
    // Remove trailing slash
    baseUrl = baseUrl.replaceAll(RegExp(r'/$'), '');
    
    // ClientLogin endpoint is at base URL
    final loginUri = Uri.parse('$baseUrl/accounts/ClientLogin');
    
    // URL encode the body parameters properly
    final body = Uri(queryParameters: {
      'Email': username,
      'Passwd': password,
    }).query;
    
    final response = await _client.post(
      loginUri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    
    if (response.statusCode == 200) {
      // Parse response to get Auth token
      final lines = response.body.split('\n');
      for (final line in lines) {
        if (line.startsWith('Auth=')) {
          final token = line.substring(5);
          // Return the token and ensure apiEndpoint points to /reader/api/0 for API calls
          final correctedEndpoint = '$baseUrl/reader/api/0';
          return {
            'token': token,
            'correctedEndpoint': correctedEndpoint,
          };
        }
      }
      throw Exception('No Auth token in response');
    }

    // If authentication failed, throw error with helpful message
    if (response.statusCode == 401) {
      throw Exception('Authentication failed (401 Unauthorized). Please verify:\n'
          '1. Google Reader API username and password are correct (these are separate from your account login)\n'
          '2. Google Reader API is enabled: Settings → Integration → Google Reader → Activate Google Reader API\n'
          '3. The Google Reader username and password are set in Miniflux integration settings\n'
          'Response: ${response.body}');
    }
    throw Exception('Authentication failed: ${response.statusCode} - ${response.body}');
  }

  /// Authenticate with Miniflux and get auth token (backward compatibility)
  Future<String> authenticate(String apiEndpoint, String username, String password) async {
    final result = await authenticateWithEndpoint(apiEndpoint, username, password);
    return result['token']!;
  }

  /// Get list of subscriptions (feeds and categories)
  Future<Map<String, dynamic>> getSubscriptions(String apiEndpoint, String authToken) async {
    final uri = Uri.parse(_getApiPath(apiEndpoint, '/subscription/list')).replace(
      queryParameters: {'output': 'json'},
    );

    final response = await _client.get(
      uri,
      headers: _getAuthHeaders(authToken),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get subscriptions: ${response.statusCode}');
    }

    final decoded = json.decode(response.body);
    // Handle both Map and List responses (some servers might return just a list)
    if (decoded is List) {
      print('[MINIFLUX] getSubscriptions returned List, wrapping in Map');
      return {'subscriptions': decoded};
    } else if (decoded is Map<String, dynamic>) {
      print('[MINIFLUX] getSubscriptions returned Map');
      // Ensure it has 'subscriptions' key
      if (!decoded.containsKey('subscriptions')) {
        print('[MINIFLUX] Map missing subscriptions key, adding it');
        return {'subscriptions': []};
      }
      return decoded;
    } else {
      print('[MINIFLUX] getSubscriptions unexpected type: ${decoded.runtimeType}');
      throw Exception('Unexpected response format from subscriptions endpoint: ${decoded.runtimeType}');
    }
  }

  /// Get articles from a stream
  Future<Map<String, dynamic>> getStreamContents(
    String apiEndpoint,
    String authToken, {
    String? streamId,
    List<String>? itemIds, // Fetch specific items by ID (using 'i' parameter)
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
    if (itemIds != null && itemIds.isNotEmpty) {
      // Add item IDs using 'i' parameter (can be repeated)
      // Format: i=tag:google.com,2005:reader/item/ITEM_ID
      for (final id in itemIds) {
        // Normalize ID format - if it's already in long format, use it; otherwise convert
        final itemId = id.contains('tag:google.com') 
            ? id 
            : 'tag:google.com,2005:reader/item/${id.padLeft(16, '0')}';
        queryParams['i'] = itemId; // This will add multiple 'i' parameters
      }
    }
    if (continuation != null) {
      queryParams['c'] = continuation;
    }
    if (xt != null) {
      queryParams['xt'] = xt;
    }

    // Handle multiple 'i' parameters - Uri.replace doesn't support multiple values
    // So we need to build the query string manually
    final baseUri = Uri.parse(_getApiPath(apiEndpoint, '/stream/contents'));
    final queryParts = <String>[];
    queryParts.add('output=json');
    queryParts.add('n=${n.toString()}');
    
    if (streamId != null) {
      queryParts.add('streamId=${Uri.encodeComponent(streamId)}');
    }
    if (itemIds != null && itemIds.isNotEmpty) {
      // Add each item ID as a separate 'i' parameter
      // Miniflux accepts numeric IDs directly (e.g., "160") or full format
      for (final id in itemIds) {
        // Use the ID as-is - Miniflux should accept numeric IDs directly
        queryParts.add('i=${Uri.encodeComponent(id)}');
      }
    }
    if (continuation != null) {
      queryParts.add('c=${Uri.encodeComponent(continuation)}');
    }
    if (xt != null) {
      queryParts.add('xt=${Uri.encodeComponent(xt)}');
    }
    
    final uri = Uri.parse('${baseUri}?${queryParts.join('&')}');

    final response = await _client.get(
      uri,
      headers: _getAuthHeaders(authToken),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get stream contents: ${response.statusCode}');
    }

    final decoded = json.decode(response.body);
    print('[MINIFLUX] getStreamContents response type: ${decoded.runtimeType}');
    if (decoded is List) {
      print('[MINIFLUX] getStreamContents returned List with ${decoded.length} items');
      // If it's a list, wrap it in a Map structure that matches the expected format
      // The parseArticlesWithMetadata expects a Map with 'items' key
      return {
        'items': decoded,
        'direction': 'ltr',
        'id': streamId ?? '',
        'title': '',
        'updated': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };
    } else if (decoded is Map<String, dynamic>) {
      print('[MINIFLUX] getStreamContents returned Map with keys: ${decoded.keys}');
      final items = decoded['items'] as List<dynamic>?;
      print('[MINIFLUX] Map contains ${items?.length ?? 0} items');
      return decoded;
    } else {
      throw Exception('Unexpected response format from stream contents endpoint: expected Map or List, got ${decoded.runtimeType}');
    }
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

    final uri = Uri.parse(_getApiPath(apiEndpoint, '/stream/items/ids')).replace(
      queryParameters: queryParams,
    );

    final response = await _client.get(
      uri,
      headers: _getAuthHeaders(authToken),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get stream item IDs: ${response.statusCode}');
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response format from stream items/ids endpoint: expected Map, got ${decoded.runtimeType}');
    }
    final data = decoded;
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

  /// Mark articles as read (using native API for Miniflux)
  Future<void> markAsRead(String apiEndpoint, String authToken, List<String> articleIds, {String? username, String? password}) async {
    if (articleIds.isEmpty) return;
    
    // Extract base URL
    String base = apiEndpoint.replaceAll(RegExp(r'/reader/api/0/?$'), '');
    base = base.replaceAll(RegExp(r'/$'), '');
    
    // Extract native IDs from article IDs
    // IDs can be: miniflux_NATIVE_ID, or just the numeric ID, or Google Reader format
    final nativeIds = <int>[];
    for (final id in articleIds) {
      print('[MINIFLUX] Processing article ID: $id');
      if (id.startsWith('miniflux_')) {
        final nativeId = int.tryParse(id.substring(9));
        if (nativeId != null) {
          nativeIds.add(nativeId);
          print('[MINIFLUX] Extracted native ID from miniflux_ prefix: $nativeId');
        }
      } else if (RegExp(r'^\d+$').hasMatch(id)) {
        // Try parsing as direct numeric ID (in case prefix was removed)
        final nativeId = int.tryParse(id);
        if (nativeId != null && nativeId > 0) {
          nativeIds.add(nativeId);
          print('[MINIFLUX] Extracted native ID as direct number: $nativeId');
        }
      } else {
        // Try extracting from Google Reader format: tag:google.com,2005:reader/item/NATIVE_ID
        final match = RegExp(r'/item/(\d+)').firstMatch(id);
        if (match != null) {
          final nativeId = int.tryParse(match.group(1)!);
          if (nativeId != null) {
            nativeIds.add(nativeId);
            print('[MINIFLUX] Extracted native ID from Google Reader format: $nativeId');
          }
        }
      }
    }
    
    if (nativeIds.isEmpty) {
      print('[MINIFLUX] No valid native IDs found for marking as read. Article IDs: $articleIds');
      return;
    }
    print('[MINIFLUX] Successfully extracted ${nativeIds.length} native IDs: $nativeIds');
    
    // Use native API - need username/password for Basic Auth
    if (username == null || password == null) {
      print('[MINIFLUX] Username/password required for native API');
      return;
    }
    
    final credentials = base64Encode(utf8.encode('$username:$password'));
    
    // Miniflux native API: PUT /v1/entries with {"entry_ids": [...], "status": "read"}
    // Use batch endpoint for better performance
    final uri = Uri.parse('$base/v1/entries');
    final response = await _client.put(
      uri,
      headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'entry_ids': nativeIds,
        'status': 'read',
      }),
    );
    
    if (response.statusCode != 204 && response.statusCode != 200 && response.statusCode != 201) {
      print('[MINIFLUX] Failed to mark entries as read: ${response.statusCode} - ${response.body}');
    } else {
      print('[MINIFLUX] Successfully marked ${nativeIds.length} entries as read (status: ${response.statusCode})');
    }
  }

  /// Mark articles as unread (using native API for Miniflux)
  Future<void> markAsUnread(String apiEndpoint, String authToken, List<String> articleIds, {String? username, String? password}) async {
    if (articleIds.isEmpty) return;
    
    // Extract base URL
    String base = apiEndpoint.replaceAll(RegExp(r'/reader/api/0/?$'), '');
    base = base.replaceAll(RegExp(r'/$'), '');
    
    // Extract native IDs from article IDs
    // IDs can be: miniflux_NATIVE_ID, or just the numeric ID, or Google Reader format
    final nativeIds = <int>[];
    for (final id in articleIds) {
      print('[MINIFLUX] Processing article ID: $id');
      if (id.startsWith('miniflux_')) {
        final nativeId = int.tryParse(id.substring(9));
        if (nativeId != null) {
          nativeIds.add(nativeId);
          print('[MINIFLUX] Extracted native ID from miniflux_ prefix: $nativeId');
        }
      } else if (RegExp(r'^\d+$').hasMatch(id)) {
        // Try parsing as direct numeric ID (in case prefix was removed)
        final nativeId = int.tryParse(id);
        if (nativeId != null && nativeId > 0) {
          nativeIds.add(nativeId);
          print('[MINIFLUX] Extracted native ID as direct number: $nativeId');
        }
      } else {
        // Try extracting from Google Reader format: tag:google.com,2005:reader/item/NATIVE_ID
        final match = RegExp(r'/item/(\d+)').firstMatch(id);
        if (match != null) {
          final nativeId = int.tryParse(match.group(1)!);
          if (nativeId != null) {
            nativeIds.add(nativeId);
            print('[MINIFLUX] Extracted native ID from Google Reader format: $nativeId');
          }
        }
      }
    }
    
    if (nativeIds.isEmpty) {
      print('[MINIFLUX] No valid native IDs found for marking as unread. Article IDs: $articleIds');
      return;
    }
    print('[MINIFLUX] Successfully extracted ${nativeIds.length} native IDs: $nativeIds');
    
    // Use native API - need username/password for Basic Auth
    if (username == null || password == null) {
      print('[MINIFLUX] Username/password required for native API');
      return;
    }
    
    final credentials = base64Encode(utf8.encode('$username:$password'));
    
    // Miniflux native API: PUT /v1/entries with {"entry_ids": [...], "status": "unread"}
    // Use batch endpoint for better performance
    final uri = Uri.parse('$base/v1/entries');
    final response = await _client.put(
      uri,
      headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'entry_ids': nativeIds,
        'status': 'unread',
      }),
    );
    
    if (response.statusCode != 204 && response.statusCode != 200 && response.statusCode != 201) {
      print('[MINIFLUX] Failed to mark entries as unread: ${response.statusCode} - ${response.body}');
    } else {
      print('[MINIFLUX] Successfully marked ${nativeIds.length} entries as unread (status: ${response.statusCode})');
    }
  }

  /// Star/unstar articles (using native API for Miniflux)
  Future<void> starArticles(String apiEndpoint, String authToken, List<String> articleIds, bool star, {String? username, String? password}) async {
    if (articleIds.isEmpty) return;
    
    // Extract base URL
    String base = apiEndpoint.replaceAll(RegExp(r'/reader/api/0/?$'), '');
    base = base.replaceAll(RegExp(r'/$'), '');
    
    // Extract native IDs from article IDs
    // IDs can be: miniflux_NATIVE_ID, or just the numeric ID, or Google Reader format
    final nativeIds = <int>[];
    for (final id in articleIds) {
      print('[MINIFLUX] Processing article ID: $id');
      if (id.startsWith('miniflux_')) {
        final nativeId = int.tryParse(id.substring(9));
        if (nativeId != null) {
          nativeIds.add(nativeId);
          print('[MINIFLUX] Extracted native ID from miniflux_ prefix: $nativeId');
        }
      } else if (RegExp(r'^\d+$').hasMatch(id)) {
        // Try parsing as direct numeric ID (in case prefix was removed)
        final nativeId = int.tryParse(id);
        if (nativeId != null && nativeId > 0) {
          nativeIds.add(nativeId);
          print('[MINIFLUX] Extracted native ID as direct number: $nativeId');
        }
      } else {
        // Try extracting from Google Reader format: tag:google.com,2005:reader/item/NATIVE_ID
        final match = RegExp(r'/item/(\d+)').firstMatch(id);
        if (match != null) {
          final nativeId = int.tryParse(match.group(1)!);
          if (nativeId != null) {
            nativeIds.add(nativeId);
            print('[MINIFLUX] Extracted native ID from Google Reader format: $nativeId');
          }
        }
      }
    }
    
    if (nativeIds.isEmpty) {
      print('[MINIFLUX] No valid native IDs found for starring/unstarring. Article IDs: $articleIds');
      return;
    }
    print('[MINIFLUX] Successfully extracted ${nativeIds.length} native IDs: $nativeIds');
    
    // Use native API - need username/password for Basic Auth
    if (username == null || password == null) {
      print('[MINIFLUX] Username/password required for native API');
      return;
    }
    
    final credentials = base64Encode(utf8.encode('$username:$password'));
    
    // Miniflux native API: PUT /v1/entries/{entryID}/bookmark with {"starred": true/false}
    for (final entryId in nativeIds) {
      final uri = Uri.parse('$base/v1/entries/$entryId/bookmark');
      final response = await _client.put(
        uri,
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/json',
        },
        body: json.encode({'starred': star}),
      );
      
      if (response.statusCode != 204 && response.statusCode != 200 && response.statusCode != 201) {
        print('[MINIFLUX] Failed to ${star ? 'star' : 'unstar'} entry $entryId: ${response.statusCode} - ${response.body}');
      } else {
        print('[MINIFLUX] Successfully ${star ? 'starred' : 'unstarred'} entry $entryId (status: ${response.statusCode})');
      }
    }
  }

  /// Subscribe to a feed via Miniflux API
  Future<void> subscribeToFeed(
    String apiEndpoint,
    String authToken,
    String feedUrl, {
    String? title,
    String? categoryLabel,
  }) async {
    final uri = Uri.parse(_getApiPath(apiEndpoint, '/subscription/edit'));
    
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
    
    final headers = {
      ..._getAuthHeaders(authToken),
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    final response = await _client.post(
      uri,
      headers: headers,
      body: bodyParts.join('&'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to subscribe to feed: ${response.statusCode} - ${response.body}');
    }
  }

  /// Convert Miniflux subscription list to Groups and Feeds
  Future<Map<String, List<dynamic>>> parseSubscriptions(
    Map<String, dynamic> subscriptions,
    int accountId,
  ) async {
    print('[MINIFLUX] parseSubscriptions called with type: ${subscriptions.runtimeType}');
    print('[MINIFLUX] parseSubscriptions keys: ${subscriptions.keys}');
    
    final groups = <Group>[];
    final feeds = <Feed>[];
    final groupMap = <String, Group>{};

    // Safely get subscriptions list
    dynamic subscriptionsValue = subscriptions['subscriptions'];
    print('[MINIFLUX] subscriptions value type: ${subscriptionsValue?.runtimeType}');
    
    List<dynamic>? subscriptionsList;
    if (subscriptionsValue is List) {
      subscriptionsList = subscriptionsValue;
    } else if (subscriptionsValue == null) {
      subscriptionsList = null;
    } else {
      print('[MINIFLUX] WARNING: subscriptions value is not a List, it is: ${subscriptionsValue.runtimeType}');
      subscriptionsList = null;
    }
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

  /// Convert Miniflux articles to Article models
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
      // For native API, also check _status field directly (more reliable)
      final nativeStatus = itemMap['_status'] as String?;
      final isRead = nativeStatus == 'read' || categories.any((cat) {
        final catStr = cat.toString();
        return catStr == 'user/-/state/com.google/read' || catStr.contains('/state/com.google/read');
      });
      // Unread status: article is UNREAD if "user/-/state/com.google/unread" is in categories
      final isUnreadTag = categories.any((cat) {
        final catStr = cat.toString();
        return catStr == 'user/-/state/com.google/unread' || catStr.contains('/state/com.google/unread');
      });
      // Starred status: article is STARRED if "user/-/state/com.google/starred" is in categories
      // For native API, also check _starred field directly (more reliable)
      final nativeStarred = itemMap['_starred'] as bool?;
      final isStarred = nativeStarred == true || categories.any((cat) {
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

      // Extract native ID if available (from native API)
      final nativeId = itemMap['_nativeId'] as int?;
      
      // Use native ID if available, otherwise use normalized Google Reader ID
      final articleId = nativeId != null ? 'miniflux_$nativeId' : id;
      
      final article = Article(
        id: articleId,
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
        // Miniflux doesn't use explicit unread tags, just absence of read tag means unread
        isUnread: !isRead,
        isStarred: isStarred,
      );
      
      // Store native ID in a way we can retrieve it later for API calls
      // We'll encode it in the article ID format: miniflux_NATIVE_ID

      articles.add(article);
    }

    return {'articles': articles, 'timestampMap': timestampMap};
  }

  /// Convert Miniflux articles to Article models (backward compatibility)
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

  /// Fetch articles using Miniflux native REST API (v1) as fallback
  /// This is used when Google Reader API doesn't return articles
  Future<Map<String, dynamic>> getEntriesViaNativeApi(
    String baseUrl,
    String username,
    String password,
    int accountId,
    int maxPastDays,
  ) async {
    // Extract base URL from apiEndpoint (remove /reader/api/0)
    String base = baseUrl.replaceAll(RegExp(r'/reader/api/0/?$'), '');
    base = base.replaceAll(RegExp(r'/$'), '');
    
    final minDate = DateTime.now().subtract(Duration(days: maxPastDays));
    final since = minDate.millisecondsSinceEpoch ~/ 1000; // Unix timestamp in seconds
    
    // Fetch all entries (both read and unread) to get accurate read status
    final uri = Uri.parse('$base/v1/entries').replace(
      queryParameters: {
        'limit': '100',
        'order': 'published_at',
        'direction': 'desc',
        'after': since.toString(),
        // Don't filter by status - we want both read and unread
      },
    );
    
    // Use Basic Auth for native API (username:password)
    final credentials = base64Encode(utf8.encode('$username:$password'));
    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Basic $credentials',
      },
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to get entries via native API: ${response.statusCode}');
    }
    
    final decoded = json.decode(response.body);
    // Native API returns: {"total": N, "entries": [...]}
    final entries = decoded['entries'] as List<dynamic>? ?? [];
    
    // Convert to Google Reader format for compatibility
    final items = <Map<String, dynamic>>[];
    for (final entry in entries) {
      final entryMap = entry as Map<String, dynamic>;
      // Convert Miniflux entry format to Google Reader item format
      items.add({
        'id': 'tag:google.com,2005:reader/item/${entryMap['id']}',
        'title': entryMap['title'] ?? '',
        'published': entryMap['published_at'] != null 
            ? (DateTime.parse(entryMap['published_at'] as String).millisecondsSinceEpoch ~/ 1000)
            : null,
        'updated': entryMap['updated_at'] != null
            ? (DateTime.parse(entryMap['updated_at'] as String).millisecondsSinceEpoch ~/ 1000)
            : null,
        'author': entryMap['author'] ?? '',
        'summary': {
          'content': entryMap['content'] ?? entryMap['summary'] ?? '',
          'direction': 'ltr',
        },
        'content': {
          'content': entryMap['content'] ?? entryMap['summary'] ?? '',
          'direction': 'ltr',
        },
        'alternate': [
          {
            'href': entryMap['url'] ?? '',
            'type': 'text/html',
          }
        ],
        'origin': {
          'streamId': 'feed/${entryMap['feed_id']}',
          'title': entryMap['feed']?['title'] ?? '',
          'htmlUrl': entryMap['feed']?['site_url'] ?? '',
        },
        'categories': [
          // Only add read tag if status is 'read', otherwise article is unread
          // Miniflux: status can be 'read' or 'unread'
          if (entryMap['status'] == 'read') 'user/-/state/com.google/read',
          if (entryMap['starred'] == true) 'user/-/state/com.google/starred',
        ],
        // Store the native entry ID for later use in API calls
        '_nativeId': entryMap['id'],
        // Store status directly for easier parsing
        '_status': entryMap['status'],
        // Store starred status directly for easier parsing
        '_starred': entryMap['starred'],
        'timestampUsec': entryMap['published_at'] != null
            ? '${DateTime.parse(entryMap['published_at'] as String).microsecondsSinceEpoch}'
            : null,
      });
    }
    
    return {
      'items': items,
      'direction': 'ltr',
      'id': '',
      'title': '',
      'updated': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };
  }
}

