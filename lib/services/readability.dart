import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

/// Simplified Readability implementation for extracting clean article content
class Readability {
  static String parseToText(String? htmlContent, String? uri) {
    if (htmlContent == null || htmlContent.isEmpty) return '';
    
    try {
      final doc = html_parser.parse(htmlContent);
      
      // Remove script and style elements
      doc.querySelectorAll('script, style, noscript').forEach((e) => e.remove());
      
      // Try to find main content area
      var content = _findMainContent(doc);
      
      if (content == null) {
        // Fallback to body
        content = doc.body ?? doc.documentElement!;
      }
      
      // Clean up the content
      _cleanContent(content);
      
      return content.text.trim();
    } catch (e) {
      print('Error parsing HTML: $e');
      return '';
    }
  }

  static Element? parseToElement(String? htmlContent, String? uri) {
    if (htmlContent == null || htmlContent.isEmpty) return null;
    
    try {
      final doc = html_parser.parse(htmlContent);
      
      // Remove script and style elements
      doc.querySelectorAll('script, style, noscript, iframe, embed, object').forEach((e) => e.remove());
      
      // Try to find main content area
      var content = _findMainContent(doc);
      
      if (content == null) {
        // Fallback to body
        content = doc.body ?? doc.documentElement!;
      }
      
      // Clean up the content
      _cleanContent(content);
      
      // Remove title if it matches the article title
      final h1 = content.querySelector('h1');
      if (h1 != null) {
        h1.remove();
      }
      
      return content;
    } catch (e) {
      print('Error parsing HTML to element: $e');
      return null;
    }
  }

  static Element? _findMainContent(Document doc) {
    // Common content selectors
    final contentSelectors = [
      'article',
      '[role="main"]',
      '.content',
      '.post-content',
      '.entry-content',
      '.article-content',
      '.article-body',
      '#content',
      '#main-content',
      'main',
    ];

    for (final selector in contentSelectors) {
      final element = doc.querySelector(selector);
      if (element != null && _hasSubstantialText(element)) {
        return element;
      }
    }

    // Try to find the element with most text
    final allElements = doc.querySelectorAll('div, section, article');
    Element? bestElement;
    int maxTextLength = 0;

    for (final element in allElements) {
      final textLength = element.text.trim().length;
      if (textLength > maxTextLength && textLength > 200) {
        maxTextLength = textLength;
        bestElement = element;
      }
    }

    return bestElement;
  }

  static bool _hasSubstantialText(Element element) {
    final text = element.text.trim();
    return text.length > 200;
  }

  static void _cleanContent(Element content) {
    // Remove unwanted elements
    content.querySelectorAll('''
      script, style, noscript, iframe, embed, object,
      .ad, .advertisement, .ads, .sidebar, .social-share,
      .comments, .comment-section, .related-posts,
      nav, header, footer, aside
    ''').forEach((e) => e.remove());

    // Clean up attributes but keep important ones
    _cleanAttributes(content);

    // Convert divs with single paragraph to paragraphs
    content.querySelectorAll('div').forEach((div) {
      final children = div.children;
      if (children.length == 1 && children.first.localName == 'p') {
        div.replaceWith(children.first);
      } else if (children.isEmpty && div.text.trim().isNotEmpty) {
        // Convert empty divs with text to paragraphs
        final p = html_parser.parse('<p>${div.text}</p>').body!.firstChild!;
        div.replaceWith(p);
      }
    });
  }

  static void _cleanAttributes(Element element) {
    // Remove most attributes but keep essential ones
    final attrsToKeep = ['src', 'href', 'alt', 'title'];
    final attrs = element.attributes.keys.map((k) => k.toString()).toList();
    
    for (final attr in attrs) {
      if (!attrsToKeep.contains(attr)) {
        element.attributes.remove(attr);
      }
    }

    // Clean style attributes
    if (element.attributes.containsKey('style')) {
      element.attributes.remove('style');
    }

    // Recursively clean children
    for (final child in element.children) {
      _cleanAttributes(child);
    }
  }
}

