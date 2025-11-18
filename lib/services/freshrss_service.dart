import 'package:dio/dio.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../models/user_config.dart';

class FreshRSSService {
  final Dio _dio = Dio();
  UserConfig? _config;

  void setConfig(UserConfig config) {
    _config = config;
    _dio.options.baseUrl = config.apiUrl;
    _dio.options.headers['Authorization'] = 'GoogleLogin auth=${config.token ?? ''}';
  }

  UserConfig? getConfig() => _config;
  
  String? getToken() => _config?.token;

  Future<bool> authenticate(String serverUrl, String username, String password) async {
    try {
      String apiUrl = serverUrl.contains('api/greader.php')
          ? serverUrl
          : '$serverUrl/api/greader.php';

      // Use FormData for proper form encoding
      final formData = FormData.fromMap({
        'Email': username,
        'Passwd': password,
      });

      final response = await _dio.post(
        '$apiUrl/accounts/ClientLogin',
        data: formData,
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      if (response.statusCode == 200) {
        final body = response.data.toString();
        final tokenMatch = RegExp(r'Auth=([^\s\n]+)').firstMatch(body);
        if (tokenMatch != null) {
          final token = tokenMatch.group(1);
          _config = UserConfig(
            serverUrl: serverUrl,
            username: username,
            password: password,
            token: token,
          );
          _dio.options.baseUrl = apiUrl;
          _dio.options.headers['Authorization'] = 'GoogleLogin auth=$token';
          return true;
        } else {
          print('Auth token not found in response: $body');
        }
      } else {
        print('Auth failed with status: ${response.statusCode}, body: ${response.data}');
      }
      return false;
    } catch (e) {
      print('Authentication error: $e');
      if (e is DioException) {
        print('Dio error: ${e.response?.data}');
        print('Status: ${e.response?.statusCode}');
      }
      return false;
    }
  }

  Future<List<Feed>> getSubscriptions() async {
    if (_config == null) throw Exception('Not authenticated');

    try {
      final response = await _dio.get(
        '/reader/api/0/subscription/list',
        queryParameters: {'output': 'json'},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['subscriptions'] != null) {
          final feeds = (data['subscriptions'] as List)
              .map((sub) => Feed(
                    id: sub['id'] as String,
                    title: sub['title'] as String,
                    websiteUrl: sub['htmlUrl'] as String?,
                    iconUrl: sub['iconUrl'] as String?,
                  ))
              .toList();
          print('Fetched ${feeds.length} feeds');
          return feeds;
        }
      }
      print('No subscriptions found in response');
      return [];
    } catch (e) {
      print('Error fetching subscriptions: $e');
      if (e is DioException) {
        print('Dio error: ${e.response?.data}');
      }
      return [];
    }
  }

  Future<List<Article>> getStreamContents({
    String? streamId,
    int count = 20,
    String? continuation,
    bool excludeRead = false,
  }) async {
    if (_config == null) throw Exception('Not authenticated');

    try {
      final queryParams = {
        'output': 'json',
        'n': count.toString(),
        'xt': excludeRead ? 'user/-/state/com.google/read' : null,
      };

      if (streamId != null) {
        queryParams['s'] = streamId;
      } else {
        queryParams['s'] = 'user/-/state/com.google/reading-list';
      }

      if (continuation != null) {
        queryParams['c'] = continuation;
      }

      queryParams.removeWhere((key, value) => value == null);

      final response = await _dio.get(
        '/reader/api/0/stream/contents',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['items'] != null) {
          final items = (data['items'] as List);
          print('Fetched ${items.length} articles from stream: $streamId');
          return items.map((item) {
            final published = item['published'] != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    int.parse(item['published'].toString()) * 1000)
                : DateTime.now();

            final updated = item['updated'] != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    int.parse(item['updated'].toString()) * 1000)
                : null;

            // Extract feed ID from origin streamId
            String feedId = 'unknown';
            if (item['origin'] != null && item['origin']['streamId'] != null) {
              final streamId = item['origin']['streamId'] as String;
              final match = RegExp(r'feed/(.+)').firstMatch(streamId);
              if (match != null) {
                feedId = match.group(1)!;
              }
            }

            // Check if article is read
            bool isRead = false;
            bool isStarred = false;
            if (item['categories'] != null) {
              final categories = item['categories'] as List;
              isRead = _hasStateCategory(categories, 'read');
              isStarred = _hasStateCategory(categories, 'starred');
              print(
                'Article ${item['id']}: categories=${categories.map((c) => c.toString()).join(', ')}, '
                'isRead=$isRead, isStarred=$isStarred',
              );
            }

            // Extract content
            String? content;
            if (item['content'] != null && item['content']['content'] != null) {
              content = item['content']['content'] as String;
            } else if (item['summary'] != null && item['summary']['content'] != null) {
              content = item['summary']['content'] as String;
            }

            // Extract image URL from content / enclosure fallback
            String? imageUrl;
            if (content != null) {
              // Try to find img tag with src attribute (with double quotes)
              final imgMatch1 = RegExp(r'<img[^>]+src="([^"]+)"').firstMatch(content);
              if (imgMatch1 != null) {
                imageUrl = imgMatch1.group(1);
              } else {
                // Try with single quotes
                final imgMatch2 = RegExp(r"<img[^>]+src='([^']+)'").firstMatch(content);
                if (imgMatch2 != null) {
                  imageUrl = imgMatch2.group(1);
                } else {
                  // Try without quotes
                  final imgMatch3 = RegExp(r'<img[^>]+src=([^\s>]+)').firstMatch(content);
                  if (imgMatch3 != null) {
                    imageUrl = imgMatch3.group(1);
                  }
                }
              }
            }
            if ((imageUrl == null || imageUrl.isEmpty) && item['enclosure'] != null) {
              imageUrl = _extractImageFromEnclosure(item['enclosure']);
            }
            if ((imageUrl == null || imageUrl.isEmpty) && item['visual'] != null) {
              final visual = item['visual'];
              if (visual is Map && visual['url'] != null) {
                imageUrl = visual['url'].toString();
              } else if (visual is String && visual.isNotEmpty) {
                imageUrl = visual;
              }
            }

            return Article(
              id: item['id'] as String,
              feedId: feedId,
              title: item['title'] as String? ?? 'Untitled',
              content: content,
              summary: item['summary'] != null && item['summary']['content'] != null
                  ? item['summary']['content'] as String
                  : null,
              author: item['author'] as String?,
              publishedDate: published,
              updatedDate: updated,
              link: item['alternate'] != null && (item['alternate'] as List).isNotEmpty
                  ? (item['alternate'] as List).first['href'] as String?
                  : null,
              imageUrl: imageUrl,
              isRead: isRead,
              isStarred: isStarred,
              lastSyncedAt: DateTime.now(),
            );
          }).toList();
        } else {
          print('No items in response for stream: $streamId');
        }
      } else {
        print('Failed to fetch articles, status: ${response.statusCode}');
      }
      return [];
    } catch (e) {
      print('Error fetching stream contents: $e');
      if (e is DioException) {
        print('Dio error: ${e.response?.data}');
        print('Status: ${e.response?.statusCode}');
      }
      return [];
    }
  }

  Future<Article?> getArticleContent(String articleId) async {
    if (_config == null) throw Exception('Not authenticated');

    try {
      final response = await _dio.get(
        '/reader/api/0/stream/contents',
        queryParameters: {
          'output': 'json',
          'i': articleId,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['items'] != null && (data['items'] as List).isNotEmpty) {
          // Similar parsing as in getStreamContents
          // Return full article content - for now return null
          // This can be implemented later if needed
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> markAsRead(List<String> articleIds, {bool read = true}) async {
    if (_config == null) throw Exception('Not authenticated');

    try {
      final response = await _dio.post(
        '/reader/api/0/edit-tag',
        data: {
          'i': articleIds.join(','),
          'a': read ? 'user/-/state/com.google/read' : null,
          'r': read ? null : 'user/-/state/com.google/read',
        },
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> markAsStarred(List<String> articleIds, {bool starred = true}) async {
    if (_config == null) throw Exception('Not authenticated');

    try {
      final response = await _dio.post(
        '/reader/api/0/edit-tag',
        data: {
          'i': articleIds.join(','),
          'a': starred ? 'user/-/state/com.google/starred' : null,
          'r': starred ? null : 'user/-/state/com.google/starred',
        },
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<String>> getUnreadArticleIds({String? feedId, int limit = 1000}) async {
    if (_config == null) throw Exception('Not authenticated');

    try {
      final streamId = feedId != null ? 'feed/$feedId' : 'user/-/state/com.google/reading-list';
      final unreadArticles = await getStreamContents(
        streamId: streamId,
        count: limit,
        excludeRead: true,
      );
      return unreadArticles.map((article) => article.id).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> getStarredArticleIds({int limit = 1000}) async {
    if (_config == null) throw Exception('Not authenticated');

    try {
      final starredArticles = await getStreamContents(
        streamId: 'user/-/state/com.google/starred',
        count: limit,
        excludeRead: false,
      );
      return starredArticles.map((article) => article.id).toList();
    } catch (e) {
      return [];
    }
  }

  bool _hasStateCategory(List categories, String stateSuffix) {
    const stateMarker = '/state/com.google/';
    return categories.any((category) {
      final id = _categoryId(category);
      final index = id.indexOf(stateMarker);
      if (index == -1) return false;
      final suffix = id.substring(index + stateMarker.length);
      return suffix == stateSuffix;
    });
  }

  String _categoryId(dynamic category) {
    if (category is String) return category;
    if (category is Map && category['id'] != null) {
      return category['id'].toString();
    }
    return category == null ? '' : category.toString();
  }

  String? _extractImageFromEnclosure(dynamic enclosure) {
    if (enclosure is List) {
      for (final entry in enclosure) {
        if (entry is Map) {
          final href = entry['href']?.toString();
          if (href == null || href.isEmpty) continue;
          final type = entry['type']?.toString().toLowerCase();
          if (type != null && type.contains('image')) {
            return href;
          }
          if (type == null && _looksLikeImageUrl(href)) {
            return href;
          }
        }
      }
    }
    return null;
  }

  bool _looksLikeImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.webp') ||
        lower.contains('image');
  }
}

