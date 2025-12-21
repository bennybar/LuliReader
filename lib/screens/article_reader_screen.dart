import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../database/article_dao.dart';
import '../database/feed_dao.dart';
import '../providers/app_provider.dart';
import '../services/local_rss_service.dart';
import '../services/rss_service.dart';
import '../services/account_service.dart';
import '../utils/rtl_helper.dart';
import '../utils/reading_time.dart';
import '../services/shared_preferences_service.dart';

class ArticleReaderScreen extends ConsumerStatefulWidget {
  final Article article;

  const ArticleReaderScreen({super.key, required this.article});

  @override
  ConsumerState<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends ConsumerState<ArticleReaderScreen> {
  String? _fullContent;
  bool _isLoadingFullContent = false;
  bool _isMarkedAsRead = false;
  bool _useFullContent = false;
  Feed? _feed;
  late bool _isStarred;
  late bool _isUnread;
  Set<String> _seenContentImages = {};
  double _fontScale = 1.0;
  double _contentPadding = 16.0;
  bool _openLinksExternally = false; // false = in-app browser (default), true = external browser

  @override
  void initState() {
    super.initState();
    _isStarred = widget.article.isStarred;
    _isUnread = widget.article.isUnread;
    _loadReadingPrefs();
    _loadFeed();
    _markAsRead();
  }

  Future<void> _loadReadingPrefs() async {
    final prefs = SharedPreferencesService();
    await prefs.init();
    final font = await prefs.getDouble('articleFontScale') ?? 1.0;
    final pad = await prefs.getDouble('articlePadding') ?? 16.0;
    final openLinksExternally = await prefs.getBool('openLinksExternally') ?? false;
    if (mounted) {
      setState(() {
        _fontScale = font;
        _contentPadding = pad;
        _openLinksExternally = openLinksExternally;
      });
    }
  }

  Future<void> _loadFeed() async {
    try {
      final feedDao = ref.read(feedDaoProvider);
      final accountService = ref.read(accountServiceProvider);
      final feed = await feedDao.getById(widget.article.feedId);
      final account = await accountService.getCurrentAccount();
      
      if (feed != null) {
        // Check both feed-level and account-level full content setting
        final shouldUseFullContent = feed.isFullContent || (account?.isFullContent ?? false);
        setState(() {
          _feed = feed as Feed;
          _useFullContent = shouldUseFullContent;
        });
        if (_useFullContent) {
          _loadFullContent();
        }
      }
    } catch (e) {
      // Error loading feed
    }
  }

  Future<void> _loadFullContent() async {
    // Check if we already have full content
    if (widget.article.fullContent != null && widget.article.fullContent!.isNotEmpty) {
      setState(() => _fullContent = widget.article.fullContent);
      return;
    }

    setState(() => _isLoadingFullContent = true);
    try {
      // Use RssService directly (works for both local and FreshRSS accounts)
      final rssService = ref.read(rssServiceProvider);
      final content = await rssService.parseFullContent(widget.article.link, widget.article.title);
      
      // Update article in database with full content if successfully downloaded
      if (content != null) {
        final articleDao = ref.read(articleDaoProvider);
        final updatedArticle = widget.article.copyWith(fullContent: content);
        await articleDao.update(updatedArticle);
      }
      
      setState(() {
        _fullContent = content;
        _isLoadingFullContent = false;
      });
    } catch (e) {
      setState(() => _isLoadingFullContent = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading full content: $e')),
        );
      }
    }
  }

  Future<void> _toggleFullContent() async {
    setState(() {
      _useFullContent = !_useFullContent;
    });
    
    if (_useFullContent) {
      _loadFullContent();
    }
  }

  Future<void> _markAsRead() async {
    if (widget.article.isUnread && !_isMarkedAsRead) {
      _isMarkedAsRead = true;
      try {
        final actions = ref.read(articleActionServiceProvider);
        await actions.markAsRead(widget.article);
        setState(() {
          _isUnread = false;
        });
        // Notify that article was marked as read so parent can refresh
        // The parent screen (FlowPage) will reload articles when returning
      } catch (e) {
        // Error marking as read - reset flag so we can try again
        _isMarkedAsRead = false;
      }
    }
  }

  Future<void> _toggleRead() async {
    try {
      if (_isUnread) {
        await ref.read(articleActionServiceProvider).markAsRead(widget.article);
      } else {
        await ref.read(articleActionServiceProvider).markAsUnread(widget.article);
      }
      setState(() {
        _isUnread = !_isUnread;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _toggleStarred() async {
    try {
      await ref.read(articleActionServiceProvider).toggleStar(widget.article);
      setState(() {
        _isStarred = !_isStarred;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isStarred ? 'Added to starred' : 'Removed from starred'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.article.link);
    if (await canLaunchUrl(uri)) {
      try {
        final mode = _openLinksExternally 
            ? LaunchMode.externalApplication 
            : LaunchMode.inAppWebView;
        await launchUrl(uri, mode: mode);
      } catch (e) {
        // Fallback to external if in-app fails
        if (!_openLinksExternally) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (e2) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not open link: $e2')),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open link: $e')),
            );
          }
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open this link')),
        );
      }
    }
  }

  Future<void> _shareArticle() async {
    try {
      await Share.share('${widget.article.title}\n${widget.article.link}');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: widget.article.link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied to clipboard')),
        );
      }
    }
  }

  bool _isRtl() {
    // Feed RTL setting takes precedence
    if (_feed?.isRtl == true) {
      return true;
    }
    // Analyze article content to determine RTL
    // Check title first, then description, then full content
    final title = widget.article.title;
    final description = widget.article.shortDescription;
    final content = _fullContent ?? widget.article.fullContent ?? '';
    
    // Combine all text for analysis
    final allText = '$title $description $content';
    return RtlHelper.isRtlContent(allText);
  }

  TextDirection _getTextDirection() {
    // Analyze article content to determine RTL
    final title = widget.article.title;
    final description = widget.article.shortDescription;
    final content = _fullContent ?? widget.article.fullContent ?? '';
    
    // Combine all text for analysis
    final allText = '$title $description $content';
    return RtlHelper.getTextDirectionFromContent(allText, feedRtl: _feed?.isRtl);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scaledMedia = media.copyWith(
      textScaler: TextScaler.linear(_fontScale),
    );
    return MediaQuery(
      data: scaledMedia,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.article.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              icon: Icon(
                _useFullContent ? Icons.article : Icons.article_outlined,
                color: _useFullContent 
                    ? Theme.of(context).colorScheme.primary 
                    : null,
              ),
              tooltip: 'Parse Full Content',
              onPressed: _toggleFullContent,
            ),
            IconButton(
              icon: Icon(_isUnread ? Icons.mark_email_unread : Icons.mark_email_read),
              tooltip: _isUnread ? 'Mark as read' : 'Mark as unread',
              onPressed: _toggleRead,
            ),
            IconButton(
              icon: Icon(_isStarred ? Icons.star : Icons.star_border),
              onPressed: _toggleStarred,
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _shareArticle,
            ),
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              onPressed: _openInBrowser,
            ),
          ],
        ),
        body: Builder(
          builder: (context) {
            final finalIsRtl = _isRtl();
            final finalTextDir = _getTextDirection();
            
            return Directionality(
              textDirection: finalTextDir,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.all(_contentPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Directionality(
                      textDirection: finalTextDir,
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          widget.article.title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                          textAlign: TextAlign.start,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                        if (widget.article.author != null) ...[
                          Text(
                            widget.article.author!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            '•',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        Text(
                          _formatDate(widget.article.date),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Builder(
                          builder: (context) {
                            final readingTime = ReadingTime.calculateAndFormat(
                              _fullContent ?? widget.article.fullContent ?? widget.article.rawDescription,
                            );
                            if (readingTime.isNotEmpty) {
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '•',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    readingTime,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                      ),
                    ),
                    const Divider(height: 32),
                    if (_useFullContent)
                      if (_isLoadingFullContent)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_fullContent != null)
                        Builder(
                          builder: (context) {
                            // First, check if hero image is in the content
                            final heroInContent = _checkIfHeroImageInContent(_fullContent!);
                            return Column(
                              children: [
                                // Show hero image below divider if it doesn't appear in article content
                                if (widget.article.img != null && 
                                    widget.article.img!.isNotEmpty && 
                                    !heroInContent) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                      imageUrl: widget.article.img!,
                                      width: double.infinity,
                                      height: 200,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) => const SizedBox.shrink(),
                                      placeholder: (context, url) => Container(
                                        height: 200,
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        child: const Center(child: CircularProgressIndicator()),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                _buildHtmlContent(_fullContent!),
                              ],
                            );
                          },
                        )
                      else
                        _buildFallbackContent()
                    else
                      _buildFallbackContent(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Check if hero image appears in the HTML content
  bool _checkIfHeroImageInContent(String html) {
    if (widget.article.img == null || widget.article.img!.isEmpty) {
      return false;
    }
    
    final document = html_parser.parse(html);
    final body = document.body ?? document.documentElement!;
    
    // Find all img elements
    final imgElements = body.querySelectorAll('img');
    
    for (final img in imgElements) {
      // Check multiple possible image source attributes
      String? src = img.attributes['src'] ?? 
                    img.attributes['data-src'] ??
                    img.attributes['data-lazy-src'] ??
                    img.attributes['data-original'] ??
                    img.attributes['data-url'];
      
      // Also check srcset
      final srcset = img.attributes['srcset'];
      if (srcset != null && srcset.isNotEmpty) {
        final srcsetUrls = srcset.split(',').map((s) => s.trim().split(RegExp(r'\s+')).first).where((url) => url.isNotEmpty);
        if (srcsetUrls.isNotEmpty) {
          src = srcsetUrls.first;
        }
      }
      
      if (src != null && src.isNotEmpty) {
        // Resolve relative URLs
        String imageUrl;
        try {
          if (src.startsWith('http://') || src.startsWith('https://') || src.startsWith('data:')) {
            imageUrl = src;
          } else {
            final baseUri = Uri.parse(widget.article.link);
            if (src.startsWith('/')) {
              imageUrl = '${baseUri.scheme}://${baseUri.host}$src';
            } else {
              final resolved = baseUri.resolve(src);
              imageUrl = resolved.toString();
            }
          }
        } catch (e) {
          imageUrl = src;
        }
        
        // Check if this matches the hero image
        if (_isSameImage(imageUrl, widget.article.img!)) {
          return true;
        }
      }
    }
    
    return false;
  }

  Widget _buildHtmlContent(String html) {
    _seenContentImages = {};
    final document = html_parser.parse(html);
    final body = document.body ?? document.documentElement!;

    final widget = _buildHtmlElement(body);
    // Process the widget to limit consecutive spacing
    return _limitConsecutiveSpacing(widget);
  }

  /// Limits consecutive spacing elements to a maximum of 2
  Widget _limitConsecutiveSpacing(Widget widget) {
    if (widget is Column) {
      final processedChildren = _processChildrenForSpacing(
        widget.children.map((child) => _limitConsecutiveSpacing(child)).toList(),
      );
      return Column(
        crossAxisAlignment: widget.crossAxisAlignment,
        mainAxisAlignment: widget.mainAxisAlignment,
        mainAxisSize: widget.mainAxisSize,
        textDirection: widget.textDirection,
        verticalDirection: widget.verticalDirection,
        textBaseline: widget.textBaseline,
        children: processedChildren,
      );
    }
    return widget;
  }

  /// Processes a list of widgets to limit consecutive spacing
  List<Widget> _processChildrenForSpacing(List<Widget> children) {
    if (children.isEmpty) return children;

    final processed = <Widget>[];
    int consecutiveSpacingCount = 0;
    const maxConsecutiveSpacing = 2;

    for (int i = 0; i < children.length; i++) {
      final widget = children[i];
      final isSpacing = _isSpacingWidget(widget);

      if (isSpacing) {
        consecutiveSpacingCount++;
        if (consecutiveSpacingCount <= maxConsecutiveSpacing) {
          processed.add(widget);
        }
        // Skip if we've exceeded max consecutive spacing
      } else {
        consecutiveSpacingCount = 0;
        processed.add(widget);
      }
    }

    return processed;
  }

  /// Checks if a widget is primarily for spacing (empty or minimal content)
  bool _isSpacingWidget(Widget widget) {
    if (widget is SizedBox) {
      // SizedBox with only height >= 16 is spacing
      return widget.width == null && (widget.height == null || widget.height! >= 16);
    }
    if (widget is Padding) {
      final padding = widget.padding;
      // Padding with only bottom padding >= 16 (from paragraphs) is spacing
      if (padding is EdgeInsets) {
        final isBottomOnly = padding.top == 0 &&
            padding.left == 0 &&
            padding.right == 0 &&
            padding.bottom >= 16;
        if (isBottomOnly) {
          // Check if the child is empty or just whitespace
          if (widget.child is Text) {
            final text = (widget.child as Text).data ?? '';
            return text.trim().isEmpty;
          }
          if (widget.child is SizedBox || widget.child is Align) {
            // Check nested widgets
            if (widget.child != null) {
              return _isSpacingWidget(widget.child!);
            }
          }
          return true;
        }
      }
    }
    // Empty Column or other containers
    if (widget is Column && widget.children.isEmpty) {
      return true;
    }
    return false;
  }

  Widget _buildListItemWithMixedContent(dynamic element, TextDirection textDir) {
    final spans = _buildTextSpansFromNodes(
      element.nodes ?? [],
      Theme.of(context).textTheme.bodyLarge,
    );
    
    return SizedBox(
      width: double.infinity,
      child: RichText(
        textAlign: TextAlign.start,
        text: TextSpan(
          children: spans,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }

  List<InlineSpan> _buildTextSpansFromNodes(List<html_dom.Node> nodes, TextStyle? baseStyle) {
    final spans = <InlineSpan>[];
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is html_dom.Text) {
        // Preserve all text including whitespace
        final nodeText = node.text ?? '';
        if (nodeText.isNotEmpty) {
          spans.add(TextSpan(
            text: nodeText,
            style: baseStyle,
          ));
        }
      } else if (node is html_dom.Element) {
        // Check if we need to add space before this element
        bool needsSpaceBefore = false;
        if (i > 0) {
          if (nodes[i - 1] is html_dom.Text) {
            final prevText = (nodes[i - 1] as html_dom.Text).text ?? '';
            // Add space if previous text doesn't end with whitespace
            needsSpaceBefore = prevText.isNotEmpty && 
                !prevText.endsWith(' ') && 
                !prevText.endsWith('\n') && 
                !prevText.endsWith('\t');
          } else if (nodes[i - 1] is html_dom.Element) {
            // Add space between consecutive elements (like </strong><a>)
            needsSpaceBefore = true;
          }
        }
        
        if (needsSpaceBefore) {
          spans.add(const TextSpan(text: ' '));
        }
        
        if (node.localName == 'a') {
          final linkText = node.text ?? '';
          final href = node.attributes['href']?.toString();
          final linkSpans = _buildTextSpansFromNodes(node.nodes ?? [], baseStyle?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ));
          if (linkSpans.isEmpty && linkText.isNotEmpty) {
            linkSpans.add(TextSpan(text: linkText));
          }
          spans.add(TextSpan(
            children: linkSpans,
            recognizer: href != null && href.isNotEmpty
                ? (TapGestureRecognizer()
                  ..onTap = () async {
                    final uri = Uri.parse(href);
                    if (await canLaunchUrl(uri)) {
                      try {
                        final mode = _openLinksExternally 
                            ? LaunchMode.externalApplication 
                            : LaunchMode.inAppWebView;
                        await launchUrl(uri, mode: mode);
                      } catch (e) {
                        if (!_openLinksExternally) {
                          try {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } catch (e2) {
                            // Silently fail
                          }
                        }
                      }
                    }
                  })
                : null,
          ));
        } else if (node.localName == 'strong' || node.localName == 'b') {
          final strongSpans = _buildTextSpansFromNodes(node.nodes ?? [], baseStyle?.copyWith(
            fontWeight: FontWeight.bold,
          ));
          spans.addAll(strongSpans);
        } else if (node.localName == 'em' || node.localName == 'i') {
          final emSpans = _buildTextSpansFromNodes(node.nodes ?? [], baseStyle?.copyWith(
            fontStyle: FontStyle.italic,
          ));
          spans.addAll(emSpans);
        } else {
          // For other inline elements, just process their text content
          final otherSpans = _buildTextSpansFromNodes(node.nodes ?? [], baseStyle);
          spans.addAll(otherSpans);
        }
        
        // Check if we need to add space after this element
        bool needsSpaceAfter = false;
        if (i < nodes.length - 1) {
          if (nodes[i + 1] is html_dom.Text) {
            final nextText = (nodes[i + 1] as html_dom.Text).text ?? '';
            // Add space if next text doesn't start with whitespace
            needsSpaceAfter = nextText.isNotEmpty && 
                !nextText.startsWith(' ') && 
                !nextText.startsWith('\n') && 
                !nextText.startsWith('\t');
          } else if (nodes[i + 1] is html_dom.Element) {
            // Add space between consecutive elements (like </a><strong>)
            needsSpaceAfter = true;
          }
        }
        
        if (needsSpaceAfter) {
          spans.add(const TextSpan(text: ' '));
        }
      }
    }
    return spans;
  }

  Widget _buildHtmlElement(dynamic element) {
    final children = <Widget>[];
    final isRtl = _isRtl();
    final textDir = _getTextDirection();
    
    if (element.nodes != null) {
      for (final node in element.nodes!) {
        if (node is html_dom.Text && node.text?.trim().isNotEmpty == true) {
          final nodeText = node.text!
              .replaceAll(RegExp(r'^[ \t]+', multiLine: true), '');
          final nodeIsRtl = RtlHelper.isRtlContent(nodeText) || isRtl;
          final nodeTextDir = RtlHelper.getTextDirectionFromContent(nodeText, feedRtl: _feed?.isRtl);
          children.add(Directionality(
            textDirection: nodeTextDir,
            child: Text(
              nodeText,
              textAlign: TextAlign.start,
            ),
          ));
        } else if (node is html_dom.Element) {
          final childWidget = _buildHtmlElement(node);
          children.add(childWidget);
        }
      }
    }

    switch (element.localName) {
      case 'p':
        final text = element.text ?? '';
        final isRtl = RtlHelper.isRtlContent(text) || _isRtl();
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        // Skip empty paragraphs (they create unwanted spacing)
        if (text.trim().isEmpty && children.isEmpty) {
          return const SizedBox.shrink();
        }
        // If paragraph has children (like links), build them using RichText; otherwise use text
        if (children.isNotEmpty || (element.nodes != null && element.nodes!.any((n) => n is html_dom.Element && n.localName == 'a'))) {
          // Build TextSpan list from nodes for RichText
          final spans = _buildTextSpansFromNodes(
            element.nodes ?? [],
            Theme.of(context).textTheme.bodyLarge,
          );
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Directionality(
              textDirection: textDir,
              child: SizedBox(
                width: double.infinity,
                child: RichText(
                  textAlign: TextAlign.start,
                  text: TextSpan(
                    children: spans,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Directionality(
            textDirection: textDir,
            child: SizedBox(
              width: double.infinity,
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.start,
              ),
            ),
          ),
        );
      case 'h1':
      case 'h2':
        final text = element.text ?? '';
        final isRtl = RtlHelper.isRtlContent(text) || _isRtl();
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        return Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Directionality(
            textDirection: textDir,
            child: SizedBox(
              width: double.infinity,
              child: Text(
                text,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.start,
              ),
            ),
          ),
        );
      case 'h3':
      case 'h4':
        final text = element.text ?? '';
        final isRtl = RtlHelper.isRtlContent(text) || _isRtl();
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Directionality(
            textDirection: textDir,
            child: SizedBox(
              width: double.infinity,
              child: Text(
                text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.start,
              ),
            ),
          ),
        );
      case 'img':
        // Check multiple possible image source attributes (for lazy loading, etc.)
        String? src = element.attributes['src']?.toString() ?? 
                      element.attributes['data-src']?.toString() ??
                      element.attributes['data-lazy-src']?.toString() ??
                      element.attributes['data-original']?.toString() ??
                      element.attributes['data-url']?.toString();
        
        // Also check srcset for responsive images
        final srcset = element.attributes['srcset']?.toString();
        if (srcset != null && srcset.isNotEmpty) {
          // Extract first URL from srcset (format: "url1 1x, url2 2x" or "url1 100w, url2 200w")
          final srcsetUrls = srcset.split(',').map((s) => s.trim().split(RegExp(r'\s+')).first).where((url) => url.isNotEmpty);
          if (srcsetUrls.isNotEmpty) {
            src = srcsetUrls.first;
          }
        }
        
        if (src != null && src.isNotEmpty) {
          // Skip data URIs that are too small (likely icons/spacers)
          if (src.startsWith('data:image') && src.length < 500) {
            return const SizedBox.shrink();
          }
          
          // Resolve relative URLs to absolute using article link as base
          String imageUrl;
          try {
            if (src.startsWith('http://') || src.startsWith('https://') || src.startsWith('data:')) {
              imageUrl = src;
            } else {
              // Relative URL - resolve using article link as base
              final baseUri = Uri.parse(widget.article.link);
              if (src.startsWith('/')) {
                // Absolute path on same domain
                imageUrl = '${baseUri.scheme}://${baseUri.host}$src';
              } else {
                // Relative path - resolve from article URL
                final resolved = baseUri.resolve(src);
                imageUrl = resolved.toString();
              }
            }
          } catch (e) {
            // If URL resolution fails, try using src as-is
            imageUrl = src;
          }
          
          // Only skip exact duplicates within the article content (same URL)
          if (_seenContentImages.contains(imageUrl)) {
            return const SizedBox.shrink();
          }
          _seenContentImages.add(imageUrl);
          
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => const SizedBox.shrink(),
                placeholder: (context, url) => Container(
                  height: 200,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      case 'a':
        final text = element.text ?? '';
        final isRtl = RtlHelper.isRtlContent(text) || _isRtl();
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        // If link has children (like formatted text), use them; otherwise use plain text
        final linkWidget = children.isNotEmpty
            ? Directionality(
                textDirection: textDir,
                child: Wrap(
                  alignment: WrapAlignment.start,
                  children: children,
                ),
              )
            : Directionality(
                textDirection: textDir,
                child: Text(
                  text,
                  textAlign: TextAlign.start,
                ),
              );
        return InkWell(
          onTap: () async {
            final href = element.attributes['href']?.toString();
            if (href != null && href.isNotEmpty) {
              final uri = Uri.parse(href);
              if (await canLaunchUrl(uri)) {
                try {
                  final mode = _openLinksExternally 
                      ? LaunchMode.externalApplication 
                      : LaunchMode.inAppWebView;
                  await launchUrl(uri, mode: mode);
                } catch (e) {
                  // Fallback to external if in-app fails
                  if (!_openLinksExternally) {
                    try {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } catch (e2) {
                      // Silently fail for inline links
                    }
                  }
                }
              }
            }
          },
          child: DefaultTextStyle(
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            child: linkWidget,
          ),
        );
      case 'ul':
      case 'ol':
        final text = element.text ?? '';
        final isRtl = RtlHelper.isRtlContent(text) || _isRtl();
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        return Padding(
          padding: EdgeInsetsDirectional.only(
            start: 16,
            bottom: 16,
          ),
          child: Directionality(
            textDirection: textDir,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        );
      case 'li':
        final text = element.text ?? '';
        final isRtl = RtlHelper.isRtlContent(text) || _isRtl();
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        
        // Check if list item has mixed content (text + links/bold)
        final hasMixedContent = element.nodes != null && 
            element.nodes!.any((n) => n is html_dom.Element && (n.localName == 'a' || n.localName == 'strong' || n.localName == 'b'));
        
        // Build the content widget
        final contentWidget = hasMixedContent
            ? _buildListItemWithMixedContent(element, textDir)
            : Directionality(
                textDirection: textDir,
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.start,
                  ),
                ),
              );
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Directionality(
            textDirection: textDir,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              textDirection: textDir,
              children: [
                const Text('• '),
                Expanded(
                  child: contentWidget,
                ),
              ],
            ),
          ),
        );
      default:
        if (children.isEmpty) {
          return const SizedBox.shrink();
        }
        final processedChildren = _processChildrenForSpacing(children);
        return Column(children: processedChildren);
    }
  }

  Widget _buildFallbackContent() {
    final isRtl = _isRtl();
    final textDir = _getTextDirection();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Directionality(
          textDirection: textDir,
          child: SizedBox(
            width: double.infinity,
            child: Text(
              widget.article.shortDescription,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.start,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _loadFullContent,
            icon: const Icon(Icons.download),
            label: const Text('Download Full Article'),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  /// Check if two image URLs refer to the same image
  /// Handles variations in protocol (http/https), www, trailing slashes, query params, etc.
  bool _isSameImage(String url1, String url2) {
    if (url1 == url2) return true;
    
    // Normalize URLs for comparison
    String normalize(String url) {
      url = url.toLowerCase().trim();
      // Remove protocol
      url = url.replaceAll(RegExp(r'^https?://'), '');
      // Remove www.
      url = url.replaceAll(RegExp(r'^www\.'), '');
      // Remove trailing slash
      url = url.replaceAll(RegExp(r'/$'), '');
      // Remove query parameters and fragments for comparison
      url = url.split('?')[0].split('#')[0];
      return url;
    }
    
    final normalized1 = normalize(url1);
    final normalized2 = normalize(url2);
    
    // Exact match after normalization
    if (normalized1 == normalized2) {
      return true;
    }
    
    // Extract just the filename/path for comparison
    // This handles cases where URLs might have different query params but same image
    final path1 = normalized1.split('/').last;
    final path2 = normalized2.split('/').last;
    
    // If filenames match and they're from the same domain, likely the same image
    if (path1.isNotEmpty && path2.isNotEmpty && path1 == path2) {
      // Extract domain
      final domain1 = normalized1.split('/').first;
      final domain2 = normalized2.split('/').first;
      
      // If same domain and same filename, it's the same image
      if (domain1 == domain2) {
        return true;
      }
    }
    
    // Check if one URL contains the other (for relative/absolute variations)
    // Only if they're clearly the same path
    if (normalized1.contains(normalized2) || normalized2.contains(normalized1)) {
      // Make sure it's not just a partial match
      // Check if the longer one ends with the shorter one
      final shorter = normalized1.length < normalized2.length ? normalized1 : normalized2;
      final longer = normalized1.length >= normalized2.length ? normalized1 : normalized2;
      
      if (longer.endsWith(shorter) || shorter.startsWith(longer.split('/').last)) {
        return true;
      }
    }
    
    return false;
  }

}

