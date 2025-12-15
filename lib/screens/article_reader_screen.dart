import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import '../models/article.dart';
import '../models/feed.dart';
import '../database/article_dao.dart';
import '../database/feed_dao.dart';
import '../providers/app_provider.dart';
import '../services/local_rss_service.dart';
import '../services/account_service.dart';
import '../utils/rtl_helper.dart';

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

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _markAsRead();
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
      print('Error loading feed: $e');
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
      final rssService = ref.read(localRssServiceProvider);
      final content = await rssService.downloadFullContent(widget.article);
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
        final articleDao = ref.read(articleDaoProvider);
        await articleDao.markAsRead(widget.article.id);
      } catch (e) {
        print('Error marking as read: $e');
      }
    }
  }

  Future<void> _toggleStarred() async {
    try {
      final articleDao = ref.read(articleDaoProvider);
      await articleDao.toggleStarred(widget.article.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.article.isStarred ? 'Removed from starred' : 'Added to starred',
            ),
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
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareArticle() async {
    await Clipboard.setData(ClipboardData(text: widget.article.link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied to clipboard')),
      );
    }
  }

  bool _isRtl() {
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
    return Scaffold(
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
            icon: Icon(widget.article.isStarred ? Icons.star : Icons.star_border),
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
          // Detect RTL from article content (Hebrew/Arabic detection)
          // Feed setting can force RTL, otherwise analyze content
          final finalIsRtl = _isRtl();
          final finalTextDir = _getTextDirection();
          
          return Directionality(
            textDirection: finalTextDir,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Show hero image if available
                  if (widget.article.img != null && widget.article.img!.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        widget.article.img!,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Title - use textAlign for RTL
                  Text(
                    widget.article.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: finalIsRtl ? TextAlign.right : TextAlign.left,
                    textDirection: finalTextDir,
                  ),
                  const SizedBox(height: 8),
                  // Author and date
                  Row(
                    mainAxisAlignment: finalIsRtl ? MainAxisAlignment.end : MainAxisAlignment.start,
                    textDirection: finalTextDir,
                    children: [
                      if (widget.article.author != null) ...[
                        Text(
                          widget.article.author!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _formatDate(widget.article.date),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  // Content
                  if (_useFullContent)
                    if (_isLoadingFullContent)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_fullContent != null)
                      _buildHtmlContent(_fullContent!)
                    else
                      _buildFallbackContent()
                  else
                    _buildFallbackContent(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHtmlContent(String html) {
    final document = html_parser.parse(html);
    final body = document.body ?? document.documentElement!;

    return _buildHtmlElement(body);
  }

  Widget _buildHtmlElement(dynamic element) {
    final children = <Widget>[];
    
    if (element.nodes != null) {
      for (final node in element.nodes!) {
        if (node is html_dom.Text && node.text?.trim().isNotEmpty == true) {
          children.add(Text(node.text!));
        } else if (node is html_dom.Element) {
          children.add(_buildHtmlElement(node));
        }
      }
    }

    switch (element.localName) {
      case 'p':
        final text = element.text ?? '';
        final isRtl = RtlHelper.isRtlContent(text) || _isRtl();
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
            textDirection: textDir,
          ),
        );
      case 'h1':
      case 'h2':
        final text = element.text ?? '';
        final isRtl = RtlHelper.isRtlContent(text) || _isRtl();
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        return Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Text(
            text,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
            textDirection: textDir,
          ),
        );
      case 'h3':
      case 'h4':
        final text = element.text ?? '';
        final isRtl = RtlHelper.isRtlContent(text) || _isRtl();
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
            textDirection: textDir,
          ),
        );
      case 'img':
        final src = element.attributes['src']?.toString();
        if (src != null && src.isNotEmpty) {
          // Skip if this is the same image as the hero image
          // Normalize URLs for comparison (remove protocol, www, trailing slashes)
          if (widget.article.img != null && _isSameImage(src, widget.article.img!)) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                src,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      case 'a':
        final text = element.text ?? '';
        final isRtl = RtlHelper.isRtlContent(text) || _isRtl();
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        return InkWell(
          onTap: () async {
            final href = element.attributes['href']?.toString();
            if (href != null && href.isNotEmpty) {
              final uri = Uri.parse(href);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            }
          },
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
            textDirection: textDir,
          ),
        );
      case 'ul':
      case 'ol':
        final isRtl = _isRtl();
        return Padding(
          padding: EdgeInsets.only(
            left: isRtl ? 0 : 16,
            right: isRtl ? 16 : 0,
            bottom: 16,
          ),
          child: Column(
            crossAxisAlignment: isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: children,
          ),
        );
      case 'li':
        final isRtl = _isRtl();
        final textDir = _getTextDirection();
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            textDirection: textDir,
            children: [
              Text(isRtl ? ' •' : '• '),
              Expanded(
                child: Column(
                  crossAxisAlignment: isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ],
          ),
        );
      default:
        return Column(children: children);
    }
  }

  Widget _buildFallbackContent() {
    final isRtl = _isRtl();
    final textDir = _getTextDirection();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.article.shortDescription,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: isRtl ? TextAlign.right : TextAlign.left,
          textDirection: textDir,
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
  /// Handles variations in protocol (http/https), www, trailing slashes, etc.
  bool _isSameImage(String url1, String url2) {
    if (url1 == url2) return true;
    
    // Normalize URLs by removing protocol and www
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
    
    // Check if one contains the other (for relative URLs)
    if (normalized1.contains(normalized2) || normalized2.contains(normalized1)) {
      return true;
    }
    
    // Check if the base paths match (same domain and path)
    final path1 = normalized1.split('/').last;
    final path2 = normalized2.split('/').last;
    if (path1 == path2 && path1.isNotEmpty) {
      return true;
    }
    
    return false;
  }
}

