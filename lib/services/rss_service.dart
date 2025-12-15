import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../models/article.dart';
import '../models/feed.dart';
import 'readability.dart';

/// Service for downloading and parsing full article content
class RssService {
  final http.Client _client;

  RssService(this._client);

  /// Downloads and parses full article content from the article URL
  /// This is the phenomenal full article download feature!
  Future<String?> parseFullContent(String link, String title) async {
    try {
      final response = await _client.get(Uri.parse(link));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch article: ${response.statusCode}');
      }

      // Detect charset
      final contentType = response.headers['content-type'] ?? '';
      String charset = 'utf-8';
      
      if (contentType.contains('charset=')) {
        final match = RegExp(r'charset=([^;]+)').firstMatch(contentType.toLowerCase());
        charset = match?.group(1)?.trim() ?? 'utf-8';
      }

      // Decode response
      String htmlContent;
      try {
        htmlContent = utf8.decode(response.bodyBytes);
      } catch (e) {
        htmlContent = latin1.decode(response.bodyBytes);
      }

      // Try to extract charset from HTML meta tag
      final doc = html_parser.parse(htmlContent);
      final metaCharset = doc.querySelector('meta[http-equiv="content-type"]');
      if (metaCharset != null) {
        final content = metaCharset.attributes['content'] ?? '';
        final match = RegExp(r'charset=([^;]+)').firstMatch(content.toLowerCase());
        if (match != null) {
          charset = match.group(1)!.trim();
          try {
            htmlContent = _decodeWithCharset(response.bodyBytes, charset);
          } catch (e) {
            // Keep original if charset decode fails
          }
        }
      }

      // Parse with Readability
      final articleContent = Readability.parseToElement(htmlContent, link);
      
      if (articleContent != null) {
        // Remove title if it matches the article title
        final h1 = articleContent.querySelector('h1');
        if (h1 != null && h1.text.trim() == title.trim()) {
          h1.remove();
        }

        return articleContent.outerHtml;
      }

      throw Exception('Failed to parse article content');
    } catch (e) {
      print('Error parsing full content: $e');
      return null;
    }
  }

  String _decodeWithCharset(List<int> bytes, String charset) {
    switch (charset.toLowerCase()) {
      case 'utf-8':
        return utf8.decode(bytes);
      case 'latin1':
      case 'iso-8859-1':
        return latin1.decode(bytes);
      case 'windows-1252':
        return latin1.decode(bytes); // Close enough
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }
}

