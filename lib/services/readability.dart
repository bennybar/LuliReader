import 'dart:math';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// A beefed‑up Readability-style parser (inspired by ReadYou's readability4j setup).
/// Keeps our existing API but scores elements for the best article body and
/// cleans the output without breaking current usage.
class Readability {
  static String parseToText(String? htmlContent, String? uri) {
    final element = parseToElement(htmlContent, uri);
    return element?.text.trim() ?? '';
  }

  static Element? parseToElement(String? htmlContent, String? uri) {
    if (htmlContent == null || htmlContent.isEmpty) return null;

    try {
      final doc = html_parser.parse(htmlContent);

      // Remove noisy nodes early
      doc.querySelectorAll('script, style, noscript, iframe, embed, object').forEach((e) => e.remove());

      // Score and extract the best candidate
      final best = _extractBestCandidate(doc);
      final content = best ?? doc.body ?? doc.documentElement;
      if (content == null) return null;

      // Work on a cloned node so original doc stays intact
      final cleaned = content.clone(true);
      _pruneInvisible(cleaned);
      _removeUnwanted(cleaned);
      _cleanAttributes(cleaned);
      _convertLonelyDivs(cleaned);
      _collapseExtraBreaks(cleaned);
      _limitConsecutiveEmptyBlocks(cleaned);
      _pruneLowQuality(cleaned);
      _normalizeTextNodes(cleaned);
      _dedupeImages(cleaned);

      return cleaned;
    } catch (_) {
      // Fallback to previous minimal parse
      try {
        final doc = html_parser.parse(htmlContent);
        return doc.body ?? doc.documentElement;
      } catch (_) {
        return null;
      }
    }
  }

  /// Find the element with the best readability score.
  static Element? _extractBestCandidate(Document doc) {
    final candidates = <Element, double>{};

    void maybeAdd(Element el) {
      final tag = el.localName ?? '';
      if (!_isCandidateTag(tag)) return;
      final score = _initialScore(el);
      if (score <= 0) return;
      candidates[el] = score;
    }

    for (final el in doc.querySelectorAll('article, section, div, main, body')) {
      maybeAdd(el);
    }

    // If nothing scored, try body
    if (candidates.isEmpty && doc.body != null) return doc.body!;

    // Adjust scores by text stats and link density
    candidates.updateAll((el, score) {
      final text = el.text.trim();
      final textLen = text.length;
      final commaBonus = RegExp(',').allMatches(text).length * 1.0;
      final density = _linkDensity(el);
      // Heavier penalty for link-dense nodes; reward substantive text.
      return score + min(textLen / 500.0, 20) + commaBonus - density * 20;
    });

    // Pick best
    final best = candidates.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    // If body is chosen, try to pick its best child to avoid pulling nav/footer.
    if (best == doc.body) {
      final childCandidates = <Element, double>{};
      for (final child in doc.body!.children) {
        if (!_isCandidateTag(child.localName ?? '')) continue;
        final score = _initialScore(child);
        if (score <= 0) continue;
        final text = child.text.trim();
        final textLen = text.length;
        final density = _linkDensity(child);
        final finalScore = score + min(textLen / 500.0, 20) - density * 20;
        childCandidates[child] = finalScore;
      }
      if (childCandidates.isNotEmpty) {
        return childCandidates.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }
    }

    return best;
  }

  static bool _isCandidateTag(String tag) {
    return const {
      'article',
      'section',
      'div',
      'main',
      'body',
      'td',
      'p',
    }.contains(tag);
  }

  static double _initialScore(Element el) {
    double score = 0;
    final classId = '${el.className} ${el.id}'.toLowerCase();

    if (_positiveHints.any(classId.contains)) score += 25;
    if (_negativeHints.any(classId.contains)) score -= 25;

    final textLen = el.text.trim().length;
    score += min(textLen / 100.0, 30);
    return score;
  }

  static double _linkDensity(Element el) {
    final text = el.text.trim();
    if (text.isEmpty) return 0;
    final linkTextLen = el.querySelectorAll('a').fold<int>(
      0,
      (sum, a) => sum + a.text.length,
    );
    return linkTextLen / text.length;
  }

  static void _pruneInvisible(Element root) {
    root.querySelectorAll('[hidden], script, style, noscript').forEach((e) => e.remove());
  }

  static void _removeUnwanted(Element root) {
    root.querySelectorAll('''
      nav, header, footer, aside,
      .ad, .ads, .advertisement, .sponsor, .sponsored,
      .sidebar, .comment, .comments, .comment-section,
      .related, .related-posts, .social, .share
    ''').forEach((e) => e.remove());
  }

  static void _cleanAttributes(Element element) {
    final attrsToKeep = {'src', 'href', 'alt', 'title'};
    final keys = element.attributes.keys.toList();
    for (final key in keys) {
      if (!attrsToKeep.contains(key)) {
        element.attributes.remove(key);
      }
    }

    if (element.attributes.containsKey('style')) {
      element.attributes.remove('style');
    }

    for (final child in element.children) {
      _cleanAttributes(child);
    }
  }

  static void _convertLonelyDivs(Element root) {
    for (final div in root.querySelectorAll('div')) {
      final children = div.children;
      if (children.length == 1 && children.first.localName == 'p') {
        div.replaceWith(children.first);
      } else if (children.isEmpty && div.text.trim().isNotEmpty) {
        final p = html_parser.parseFragment('<p>${div.text}</p>').firstChild;
        if (p != null) {
          div.replaceWith(p);
        }
      }
    }
  }

  /// Collapse repeated <br> and empty paragraphs into at most 2 lines.
  static void _collapseExtraBreaks(Element root) {
    for (final br in root.querySelectorAll('br + br + br')) {
      br.remove();
    }
    for (final p in root.querySelectorAll('p')) {
      final normalized = p.text
          .trim()
          .replaceAll(RegExp(r'\n{2,}'), '\n\n');
      if (normalized != p.text) {
        p.text = normalized;
      }
    }
  }

  /// Remove more than two consecutive empty/spacing blocks.
  static void _limitConsecutiveEmptyBlocks(Element root) {
    final children = root.nodes.toList();
    int consecutive = 0;
    for (final node in children) {
      if (node is Element && _isEmptyBlock(node)) {
        consecutive++;
        if (consecutive > 2) {
          node.remove();
        }
      } else if (node is Text && node.text.trim().isEmpty) {
        // leave whitespace but count as spacing
        consecutive++;
        if (consecutive > 2) {
          node.remove();
        }
      } else {
        consecutive = 0;
      }
    }

    // Recurse into nested elements
    for (final child in root.children) {
      _limitConsecutiveEmptyBlocks(child);
    }
  }

  static bool _isEmptyBlock(Element el) {
    final tag = el.localName;
    final isBlock = const {'p', 'div', 'section', 'article', 'br', 'hr'}.contains(tag);
    return isBlock && el.text.trim().isEmpty && el.children.isEmpty;
  }

  /// Remove low-quality nodes similar to ReadYou’s extended grabber:
  /// - Highly link-dense and short
  /// - Metadata wrappers / bylines
  /// - Empty structural containers
  static void _pruneLowQuality(Element root) {
    final toRemove = <Element>[];

    bool shouldDrop(Element el) {
      final tag = el.localName ?? '';
      if (const {'nav', 'header', 'footer', 'aside', 'form'}.contains(tag)) return true;

      final classId = '${el.className} ${el.id}'.toLowerCase();
      if (_negativeHints.any(classId.contains)) return true;

      final text = el.text.trim();
      final textLen = text.length;
      final density = _linkDensity(el);
      final linkHeavy = _isLinkHeavy(el);
      // Drop short + link-dense or empty containers or link-heavy menus
      if ((textLen < 120 && density > 0.35) || (textLen < 30 && el.children.isEmpty) || linkHeavy) {
        return true;
      }
      return false;
    }

    for (final el in root.querySelectorAll('div, section, article, aside, header, footer, nav, form, ul, ol, li, p')) {
      if (shouldDrop(el)) {
        toRemove.add(el);
      }
    }

    for (final el in toRemove) {
      el.remove();
    }
  }

  /// Detects blocks that are mostly links (like menus / category lists).
  static bool _isLinkHeavy(Element el) {
    final links = el.querySelectorAll('a');
    if (links.isEmpty) return false;

    final linkTextLen = links.fold<int>(0, (sum, a) => sum + a.text.trim().length);
    final totalTextLen = el.text.trim().length;
    if (totalTextLen == 0) return true;

    final ratio = linkTextLen / totalTextLen;
    if (ratio > 0.7) return true;

    // If a list where most items are single links, treat as link-heavy
    if (el.localName == 'ul' || el.localName == 'ol') {
      final items = el.children.where((c) => c.localName == 'li').toList();
      if (items.isNotEmpty) {
        final linkItems = items.where((li) => li.querySelectorAll('a').length == li.children.length || li.text.trim().length <= 6).length;
        if (linkItems / items.length > 0.6) return true;
      }
    }
    return false;
  }

  /// Normalize text nodes to collapse excessive newlines and spaces; remove empty <p>.
  static void _normalizeTextNodes(Element root) {
    void normalize(Node node) {
      if (node is Text) {
        final normalized = node.text
            .replaceAll('\r', '\n')
            .replaceAll(RegExp(r'\n{2,}'), '\n\n')
            .replaceAll(RegExp('[ \t]{2,}'), ' ')
            .trim();
        node.text = normalized;
      } else if (node is Element) {
        final children = node.nodes.toList();
        for (final child in children) {
          normalize(child);
        }
        if (node.localName == 'p' && node.text.trim().isEmpty) {
          node.remove();
        }
      }
    }

    normalize(root);
  }

  /// Remove duplicate consecutive images (same src).
  static void _dedupeImages(Element root) {
    final seen = <String>{};
    for (final img in root.querySelectorAll('img')) {
      final src = img.attributes['src']?.trim() ?? '';
      if (src.isEmpty) continue;
      if (seen.contains(src)) {
        img.remove();
      } else {
        seen.add(src);
      }
    }
  }
}

const _positiveHints = [
  'article',
  'post',
  'entry',
  'body',
  'content',
  'main',
  'page',
  'text',
];

const _negativeHints = [
  'comment',
  'combx',
  'disqus',
  'foot',
  'footer',
  'header',
  'menu',
  'meta',
  'nav',
  'promo',
  'related',
  'remark',
  'rss',
  'shoutbox',
  'sidebar',
  'sponsor',
  'ad-',
  'ads',
  'social',
];

