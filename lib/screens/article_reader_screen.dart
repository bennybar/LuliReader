import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../providers/app_provider.dart';
import '../services/rss_service.dart';
import '../utils/rtl_helper.dart';
import '../utils/reading_time.dart';
import '../services/shared_preferences_service.dart';
import '../theme/app_symbols.dart';

class ArticleReaderScreen extends ConsumerStatefulWidget {
  final Article article;

  const ArticleReaderScreen({super.key, required this.article});

  @override
  ConsumerState<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

enum _ReaderMenuAction {
  toggleRead,
  toggleMode,
  appearance,
  openOriginal,
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
  double _titleFontScale = 1.0;
  double _contentPadding = 16.0;
  bool _openLinksExternally = false; // false = in-app browser (default), true = external browser
  String _readingTime = '';
  html_dom.Element? _parsedFullContentBody;
  bool _heroImageInFullContent = false;
  final SharedPreferencesService _prefs = SharedPreferencesService();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollProgress = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _isStarred = widget.article.isStarred;
    _isUnread = widget.article.isUnread;
    _readingTime = _calculateReadingTime(
      widget.article.fullContent ?? widget.article.rawDescription,
    );
    _loadReadingPrefs();
    _loadFeed();
    _markAsRead();
    _scrollController.addListener(_updateScrollProgress);
  }

  @override
  void dispose() {
    _scrollProgress.dispose();
    _scrollController
      ..removeListener(_updateScrollProgress)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadReadingPrefs() async {
    await _prefs.init();
    final font = await _prefs.getDouble('articleFontScale') ?? 1.0;
    final titleFont = await _prefs.getDouble('titleFontScale') ?? 1.0;
    final pad = await _prefs.getDouble('articlePadding') ?? 16.0;
    final openLinksExternally = await _prefs.getBool('openLinksExternally') ?? false;
    if (mounted) {
      setState(() {
        _fontScale = font;
        _titleFontScale = titleFont;
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
          _feed = feed;
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
      setState(() {
        _cacheFullContent(widget.article.fullContent);
      });
      // Prefetch images even if content already exists
      RssService.prefetchImages(widget.article.fullContent!);
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
        
        // Prefetch images for caching
        RssService.prefetchImages(content);
      }
      
      setState(() {
        _cacheFullContent(content);
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
    await _setReaderMode(!_useFullContent);
  }

  String _calculateReadingTime(String? content) {
    return ReadingTime.calculateAndFormat(content);
  }

  void _cacheFullContent(String? content) {
    _fullContent = content;
    _parsedFullContentBody = null;
    _heroImageInFullContent = false;
    _readingTime = _calculateReadingTime(
      content ?? widget.article.fullContent ?? widget.article.rawDescription,
    );

    if (content == null || content.isEmpty) {
      return;
    }

    final document = html_parser.parse(content);
    final body = document.body ?? document.documentElement;
    if (body == null) {
      return;
    }

    _parsedFullContentBody = body;
    _heroImageInFullContent = _bodyContainsHeroImage(body);
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

  Future<void> _showReaderAppearanceSheet(BuildContext context) async {
    final baseTitleSize = Theme.of(context).textTheme.headlineSmall?.fontSize ?? 24.0;
    final baseArticleSize = Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16.0;

    double tempTitleFontSize = baseTitleSize * _titleFontScale;
    double tempArticleFontSize = baseArticleSize * _fontScale;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> updateTitleSize(double newSize) async {
            setSheetState(() {
              tempTitleFontSize = newSize.clamp(12.0, 48.0);
            });
            final newScale = tempTitleFontSize / baseTitleSize;
            await _saveReadingDouble('titleFontScale', newScale);
            if (mounted) {
              setState(() {
                _titleFontScale = newScale;
              });
            }
          }
          
          Future<void> updateArticleSize(double newSize) async {
            setSheetState(() {
              tempArticleFontSize = newSize.clamp(10.0, 32.0);
            });
            final newScale = tempArticleFontSize / baseArticleSize;
            await _saveReadingDouble('articleFontScale', newScale);
            if (mounted) {
              setState(() {
                _fontScale = newScale;
              });
            }
          }

          Future<void> updatePadding(double newPadding) async {
            final clamped = newPadding.clamp(8.0, 32.0);
            await _saveReadingDouble('articlePadding', clamped);
            if (mounted) {
              setState(() {
                _contentPadding = clamped;
              });
            }
            setSheetState(() {});
          }
          
          Future<void> resetFontSizes() async {
            await updateTitleSize(baseTitleSize);
            await updateArticleSize(baseArticleSize);
            await updatePadding(16.0);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: ListView(
                shrinkWrap: true,
              children: [
                Text(
                  'Reading appearance',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Adjust the reader live while you browse this article.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                _buildAppearanceSlider(
                  context: context,
                  title: 'Title size',
                  valueLabel: '${tempTitleFontSize.toStringAsFixed(0)} px',
                  value: tempTitleFontSize,
                  min: 18,
                  max: 42,
                  divisions: 24,
                  onChanged: updateTitleSize,
                ),
                const SizedBox(height: 8),
                _buildAppearanceSlider(
                  context: context,
                  title: 'Article text size',
                  valueLabel: '${tempArticleFontSize.toStringAsFixed(0)} px',
                  value: tempArticleFontSize,
                  min: 13,
                  max: 28,
                  divisions: 15,
                  onChanged: updateArticleSize,
                ),
                const SizedBox(height: 8),
                _buildAppearanceSlider(
                  context: context,
                  title: 'Reading padding',
                  valueLabel: '${_contentPadding.toStringAsFixed(0)} px',
                  value: _contentPadding,
                  min: 8,
                  max: 32,
                  divisions: 24,
                  onChanged: updatePadding,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: resetFontSizes,
                      icon: const Icon(AppSymbols.refresh),
                      label: const Text('Reset'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveReadingDouble(String key, double value) async {
    await _prefs.init();
    await _prefs.setDouble(key, value);
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

  void _updateScrollProgress() {
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final nextProgress = maxExtent <= 0
        ? 0.0
        : (_scrollController.offset / maxExtent).clamp(0.0, 1.0);
    if ((nextProgress - _scrollProgress.value).abs() < 0.01) return;
    _scrollProgress.value = nextProgress;
  }

  Future<void> _setReaderMode(bool useFullContent) async {
    if (_useFullContent == useFullContent) return;
    setState(() {
      _useFullContent = useFullContent;
    });
    if (useFullContent) {
      await _loadFullContent();
    }
  }

  bool get _hasFullArticleContent {
    final content = _fullContent ?? widget.article.fullContent;
    return content != null && content.trim().isNotEmpty;
  }

  bool get _shouldShowHeroImage {
    final image = widget.article.img;
    if (image == null || image.isEmpty) {
      return false;
    }
    if (_useFullContent && _heroImageInFullContent) {
      return false;
    }
    return true;
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
        body: Builder(
          builder: (context) {
            final finalTextDir = _getTextDirection();
            
            return Directionality(
              textDirection: finalTextDir,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    surfaceTintColor: Colors.transparent,
                    title: Text(
                      widget.article.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    actions: [
                      IconButton(
                        icon: Icon(_isStarred ? AppSymbols.star : AppSymbols.star_border),
                        tooltip: _isStarred ? 'Remove star' : 'Star article',
                        onPressed: _toggleStarred,
                      ),
                      IconButton(
                        icon: const Icon(AppSymbols.share),
                        tooltip: 'Share',
                        onPressed: _shareArticle,
                      ),
                      _buildReaderOverflowMenu(),
                    ],
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(2),
                      child: ValueListenableBuilder<double>(
                        valueListenable: _scrollProgress,
                        builder: (context, progress, child) {
                          return Opacity(
                            opacity: progress <= 0 || progress >= 1 ? 0 : 1,
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 2,
                              backgroundColor: Colors.transparent,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(_contentPadding, 16, _contentPadding, 0),
                      child: _buildReaderHeader(context, finalTextDir),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(_contentPadding, 24, _contentPadding, 32),
                      child: _buildBodyContent(context, finalTextDir),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  bool _bodyContainsHeroImage(html_dom.Element body) {
    if (widget.article.img == null || widget.article.img!.isEmpty) {
      return false;
    }

    final imgElements = body.querySelectorAll('img');

    for (final img in imgElements) {
      String? src = img.attributes['src'] ??
          img.attributes['data-src'] ??
          img.attributes['data-lazy-src'] ??
          img.attributes['data-original'] ??
          img.attributes['data-url'];

      final srcset = img.attributes['srcset'];
      if (srcset != null && srcset.isNotEmpty) {
        final srcsetUrls = srcset
            .split(',')
            .map((s) => s.trim().split(RegExp(r'\s+')).first)
            .where((url) => url.isNotEmpty);
        if (srcsetUrls.isNotEmpty) {
          src = srcsetUrls.first;
        }
      }

      if (src != null && src.isNotEmpty) {
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

        if (_isSameImage(imageUrl, widget.article.img!)) {
          return true;
        }
      }
    }

    return false;
  }

  Widget _buildReaderHeader(BuildContext context, TextDirection textDirection) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSourceRow(context, textDirection),
              const SizedBox(height: 18),
              Directionality(
                textDirection: textDirection,
                child: Text(
                  widget.article.title,
                  textAlign: TextAlign.start,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        fontSize:
                            (Theme.of(context).textTheme.headlineMedium?.fontSize ?? 28) *
                                _titleFontScale,
                      ),
                ),
              ),
              const SizedBox(height: 14),
              _buildMetadataRow(context, textDirection),
              const SizedBox(height: 18),
              _buildReaderModeToggle(context, textDirection),
              const SizedBox(height: 14),
              _buildReaderQuickActions(context, textDirection),
            ],
          ),
        ),
        if (_shouldShowHeroImage) ...[
          const SizedBox(height: 16),
          _buildHeroImage(context),
        ],
      ],
    );
  }

  Widget _buildSourceRow(BuildContext context, TextDirection textDirection) {
    final scheme = Theme.of(context).colorScheme;
    final sourceDomain = Uri.tryParse(widget.article.link)?.host.replaceFirst('www.', '') ?? '';
    return Directionality(
      textDirection: textDirection,
      child: Row(
        children: [
          _buildFeedAvatar(context),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _feed?.name ?? 'Source',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (sourceDomain.isNotEmpty)
                  Text(
                    sourceDomain,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedAvatar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconUrl = _feed?.icon;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: iconUrl != null && iconUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CachedNetworkImage(
                imageUrl: iconUrl,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (_, __, ___) => Icon(
                  AppSymbols.rss_feed,
                  color: scheme.onSecondaryContainer,
                  size: 18,
                ),
                placeholder: (_, __) => Icon(
                  AppSymbols.rss_feed,
                  color: scheme.onSecondaryContainer,
                  size: 18,
                ),
              ),
            )
          : Icon(
              AppSymbols.rss_feed,
              color: scheme.onSecondaryContainer,
              size: 18,
            ),
    );
  }

  Widget _buildMetadataRow(BuildContext context, TextDirection textDirection) {
    final items = <Widget>[
      _buildMetadataChip(
        context,
        icon: _isUnread ? AppSymbols.mark_email_unread : AppSymbols.mark_email_read,
        label: _isUnread ? 'Unread' : 'Read',
      ),
      if (widget.article.author != null && widget.article.author!.trim().isNotEmpty)
        _buildMetadataChip(
          context,
          icon: AppSymbols.account_circle,
          label: widget.article.author!.trim(),
        ),
      _buildMetadataChip(
        context,
        icon: AppSymbols.calendar_today,
        label: _formatFriendlyDate(widget.article.date),
      ),
      if (_readingTime.isNotEmpty)
        _buildMetadataChip(
          context,
          icon: AppSymbols.timer_outlined,
          label: _readingTime,
        ),
    ];

    return Align(
      alignment:
          textDirection == TextDirection.rtl ? Alignment.centerRight : Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items,
      ),
    );
  }

  Widget _buildMetadataChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReaderModeToggle(BuildContext context, TextDirection textDirection) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: textDirection,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Full article',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 8),
                if (_isLoadingFullContent)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                else
                  Switch.adaptive(
                    value: _useFullContent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: _setReaderMode,
                  ),
              ],
            ),
          ),
          const Spacer(),
          _buildQuickActionIcon(
            context,
            icon: AppSymbols.text_fields,
            tooltip: 'Reading appearance',
            onPressed: () => _showReaderAppearanceSheet(context),
          ),
          const SizedBox(width: 8),
          _buildQuickActionIcon(
            context,
            icon: AppSymbols.open_in_browser,
            tooltip: 'Open original',
            onPressed: _openInBrowser,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionIcon(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }

  Widget _buildReaderQuickActions(BuildContext context, TextDirection textDirection) {
    return const SizedBox.shrink();
  }

  Widget _buildHeroImage(BuildContext context) {
    final imageUrl = widget.article.img!;
    return GestureDetector(
      onTap: () => _showFullscreenImage(imageUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: double.infinity,
          height: 240,
          fit: BoxFit.cover,
          memCacheWidth: _targetImageCacheWidth(
            MediaQuery.of(context).size.width - (_contentPadding * 2),
          ),
          maxWidthDiskCache: _targetImageCacheWidth(
            MediaQuery.of(context).size.width - (_contentPadding * 2),
          ),
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          errorWidget: (context, url, error) => const SizedBox.shrink(),
          placeholder: (context, url) => _buildImagePlaceholder(240),
        ),
      ),
    );
  }

  Widget _buildBodyContent(BuildContext context, TextDirection textDirection) {
    if (_useFullContent) {
      if (_isLoadingFullContent) {
        return _buildLoadingState(context);
      }

      if (_hasFullArticleContent) {
        return _buildHtmlContent(_parsedFullContentBody);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFallbackNotice(context, textDirection),
          const SizedBox(height: 20),
          _buildSummaryContent(context, textDirection),
        ],
      );
    }

    return _buildSummaryContent(context, textDirection);
  }

  Widget _buildLoadingState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 14),
          Text(
            'Loading full article',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Fetching a cleaner reading view from the original page.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryContent(BuildContext context, TextDirection textDirection) {
    return Directionality(
      textDirection: textDirection,
      child: SizedBox(
        width: double.infinity,
        child: Text(
          widget.article.shortDescription,
          textAlign: TextAlign.start,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.62,
              ),
        ),
      ),
    );
  }

  Widget _buildFallbackNotice(BuildContext context, TextDirection textDirection) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Directionality(
        textDirection: textDirection,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    AppSymbols.article_outlined,
                    color: scheme.onPrimaryContainer,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Full article not loaded yet',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You are viewing the feed summary. Load the full article for a cleaner reading view, or open the original page.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment:
                  textDirection == TextDirection.rtl ? WrapAlignment.end : WrapAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: () => _setReaderMode(true),
                  icon: const Icon(AppSymbols.download),
                  label: const Text('Load full article'),
                ),
                OutlinedButton.icon(
                  onPressed: _openInBrowser,
                  icon: const Icon(AppSymbols.open_in_browser),
                  label: const Text('Open original article'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReaderOverflowMenu() {
    return PopupMenuButton<_ReaderMenuAction>(
      tooltip: 'More',
      onSelected: _handleReaderMenuAction,
      itemBuilder: (context) => [
        PopupMenuItem<_ReaderMenuAction>(
          value: _ReaderMenuAction.toggleRead,
          child: _buildMenuItem(
            context,
            icon: _isUnread ? AppSymbols.mark_email_unread : AppSymbols.mark_email_read,
            label: _isUnread ? 'Mark as read' : 'Mark as unread',
          ),
        ),
        PopupMenuItem<_ReaderMenuAction>(
          value: _ReaderMenuAction.toggleMode,
          enabled: !_isLoadingFullContent,
          child: _buildMenuItem(
            context,
            icon: _useFullContent ? AppSymbols.article_outlined : AppSymbols.article,
            label: _useFullContent
                ? 'Show summary'
                : (_hasFullArticleContent ? 'Show full article' : 'Load full article'),
          ),
        ),
        PopupMenuItem<_ReaderMenuAction>(
          value: _ReaderMenuAction.appearance,
          child: _buildMenuItem(
            context,
            icon: AppSymbols.text_fields,
            label: 'Reading appearance',
          ),
        ),
        PopupMenuItem<_ReaderMenuAction>(
          value: _ReaderMenuAction.openOriginal,
          child: _buildMenuItem(
            context,
            icon: AppSymbols.open_in_browser,
            label: 'Open original article',
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    );
  }

  Future<void> _handleReaderMenuAction(_ReaderMenuAction action) async {
    switch (action) {
      case _ReaderMenuAction.toggleRead:
        await _toggleRead();
        break;
      case _ReaderMenuAction.toggleMode:
        await _toggleFullContent();
        break;
      case _ReaderMenuAction.appearance:
        await _showReaderAppearanceSheet(context);
        break;
      case _ReaderMenuAction.openOriginal:
        await _openInBrowser();
        break;
    }
  }

  Widget _buildAppearanceSlider({
    required BuildContext context,
    required String title,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                valueLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildHtmlContent(html_dom.Element? body) {
    if (body == null) {
      return const SizedBox.shrink();
    }
    _seenContentImages = {};

    final widget = _buildHtmlElement(body);
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
    final baseStyle = Theme.of(context).textTheme.bodyLarge;
    final scaledStyle = baseStyle?.copyWith(
      fontSize: (baseStyle.fontSize ?? 16) * _fontScale,
    );
    final spans = _buildTextSpansFromNodes(
      element.nodes ?? [],
      scaledStyle ?? baseStyle!,
    );
    
    return SizedBox(
      width: double.infinity,
      child: RichText(
        textAlign: TextAlign.start,
        text: TextSpan(
          children: spans,
          style: scaledStyle,
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
        final nodeText = node.text;
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
            final prevText = (nodes[i - 1] as html_dom.Text).text;
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
          final linkText = node.text;
          final href = node.attributes['href']?.toString();
          final linkSpans = _buildTextSpansFromNodes(node.nodes, baseStyle?.copyWith(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
            decoration: TextDecoration.underline,
            decorationColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.65),
          ));
          if (linkSpans.isEmpty && linkText.isNotEmpty) {
            linkSpans.add(TextSpan(text: linkText));
          }
          spans.add(TextSpan(
            children: linkSpans,
            recognizer: href != null && href.isNotEmpty
                ? (TapGestureRecognizer()
                  ..onTap = () async {
                    final resolvedHref = _resolveUrl(href);
                    final uri = Uri.parse(resolvedHref);
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
          final strongSpans = _buildTextSpansFromNodes(node.nodes, baseStyle?.copyWith(
            fontWeight: FontWeight.bold,
          ));
          spans.addAll(strongSpans);
        } else if (node.localName == 'code') {
          final codeSpans = _buildTextSpansFromNodes(
            node.nodes,
            baseStyle?.copyWith(
              fontFamily: 'monospace',
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              letterSpacing: 0.15,
            ),
          );
          if (codeSpans.isEmpty && node.text.isNotEmpty) {
            codeSpans.add(
              TextSpan(
                text: node.text,
                style: baseStyle?.copyWith(
                  fontFamily: 'monospace',
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            );
          }
          spans.addAll(codeSpans);
        } else if (node.localName == 'em' || node.localName == 'i') {
          final emSpans = _buildTextSpansFromNodes(node.nodes, baseStyle?.copyWith(
            fontStyle: FontStyle.italic,
          ));
          spans.addAll(emSpans);
        } else {
          // For other inline elements, just process their text content
          final otherSpans = _buildTextSpansFromNodes(node.nodes, baseStyle);
          spans.addAll(otherSpans);
        }
        
        // Check if we need to add space after this element
        bool needsSpaceAfter = false;
        if (i < nodes.length - 1) {
          if (nodes[i + 1] is html_dom.Text) {
            final nextText = (nodes[i + 1] as html_dom.Text).text;
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
    final textDir = _getTextDirection();
    
    if (element.nodes != null) {
      for (final node in element.nodes) {
        if (node is html_dom.Text && node.text.trim().isNotEmpty) {
          final nodeText = node.text
              .replaceAll(RegExp(r'^[ \t]+', multiLine: true), '');
          final nodeTextDir = RtlHelper.getTextDirectionFromContent(nodeText, feedRtl: _feed?.isRtl);
          children.add(Directionality(
            textDirection: nodeTextDir,
            child: Text(
              nodeText,
              textAlign: TextAlign.start,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16) * _fontScale,
              ),
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
        final text = element.text;
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        // Skip empty paragraphs (they create unwanted spacing)
        if (text.trim().isEmpty && children.isEmpty) {
          return const SizedBox.shrink();
        }
        // If paragraph has children (like links), build them using RichText; otherwise use text
        if (children.isNotEmpty || element.nodes.any((n) => n is html_dom.Element && n.localName == 'a')) {
          // Build TextSpan list from nodes for RichText
          final baseStyle = Theme.of(context).textTheme.bodyLarge;
          final scaledStyle = baseStyle?.copyWith(
            fontSize: (baseStyle.fontSize ?? 16) * _fontScale,
          );
          final spans = _buildTextSpansFromNodes(
            element.nodes ?? [],
            scaledStyle ?? baseStyle!,
          );
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Directionality(
              textDirection: textDir,
              child: SizedBox(
                width: double.infinity,
                child: RichText(
                  textAlign: TextAlign.start,
                  text: TextSpan(
                    children: spans,
                    style: scaledStyle,
                  ),
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Directionality(
            textDirection: textDir,
            child: SizedBox(
              width: double.infinity,
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16) * _fontScale,
                ),
                textAlign: TextAlign.start,
              ),
            ),
          ),
        );
      case 'h1':
      case 'h2':
        final text = element.text;
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        return Padding(
          padding: const EdgeInsets.only(top: 28, bottom: 12),
          child: Directionality(
            textDirection: textDir,
            child: SizedBox(
              width: double.infinity,
              child: Text(
                text,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: (Theme.of(context).textTheme.headlineSmall?.fontSize ?? 24) * _fontScale,
                    ),
                textAlign: TextAlign.start,
              ),
            ),
          ),
        );
      case 'h3':
      case 'h4':
        final text = element.text;
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        return Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 10),
          child: Directionality(
            textDirection: textDir,
            child: SizedBox(
              width: double.infinity,
              child: Text(
                text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: (Theme.of(context).textTheme.titleMedium?.fontSize ?? 20) * _fontScale,
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
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: GestureDetector(
              onTap: () => _showFullscreenImage(imageUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: _targetImageCacheWidth(
                    MediaQuery.of(context).size.width - (_contentPadding * 2),
                  ),
                  maxWidthDiskCache: _targetImageCacheWidth(
                    MediaQuery.of(context).size.width - (_contentPadding * 2),
                  ),
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                  placeholder: (context, url) => _buildImagePlaceholder(220),
                ),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      case 'a':
        final text = element.text;
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
              final resolvedHref = _resolveUrl(href);
              final uri = Uri.parse(resolvedHref);
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
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
              decoration: TextDecoration.underline,
              decorationColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.65),
            ),
            child: linkWidget,
          ),
        );
      case 'ul':
      case 'ol':
        final text = element.text;
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        return Padding(
          padding: EdgeInsetsDirectional.only(
            start: 18,
            bottom: 20,
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
        final text = element.text;
        final textDir = RtlHelper.getTextDirectionFromContent(text, feedRtl: _feed?.isRtl);
        
        // Check if list item has mixed content (text + links/bold)
        final hasMixedContent =
            element.nodes.any((n) => n is html_dom.Element && (n.localName == 'a' || n.localName == 'strong' || n.localName == 'b'));
        
        // Build the content widget
        final contentWidget = hasMixedContent
            ? _buildListItemWithMixedContent(element, textDir)
            : Directionality(
                textDirection: textDir,
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontSize: (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16) * _fontScale,
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
              );
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
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
      case 'blockquote':
        final quoteText = element.text.trim();
        final quoteChildren = children.isNotEmpty
            ? _processChildrenForSpacing(children)
            : [
                Text(
                  quoteText,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize:
                            (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16) *
                                _fontScale,
                        height: 1.55,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Directionality(
                      textDirection: textDir,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: quoteChildren,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case 'pre':
        final codeText = element.text.trimRight();
        if (codeText.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                codeText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
              ),
            ),
          ),
        );
      case 'code':
        if (element.parent?.localName == 'pre') {
          return const SizedBox.shrink();
        }
        final codeText = element.text.trim();
        if (codeText.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            codeText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
          ),
        );
      case 'hr':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55),
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

  Widget _buildImagePlaceholder(double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Icon(
              AppSymbols.photo_outlined,
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  int _targetImageCacheWidth(double logicalWidth) {
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    return (logicalWidth * devicePixelRatio).round();
  }

  String _formatFriendlyDate(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    if (DateUtils.isSameDay(localDate, now)) {
      return 'Today';
    }
    if (DateUtils.isSameDay(localDate, yesterday)) {
      return 'Yesterday';
    }

    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${localDate.day} ${monthNames[localDate.month - 1]} ${localDate.year}';
  }

  String _resolveUrl(String value) {
    if (value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('data:')) {
      return value;
    }

    try {
      final baseUri = Uri.parse(widget.article.link);
      if (value.startsWith('/')) {
        return '${baseUri.scheme}://${baseUri.host}$value';
      }
      return baseUri.resolve(value).toString();
    } catch (_) {
      return value;
    }
  }

  Future<void> _showFullscreenImage(String imageUrl) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    placeholder: (_, __) => _buildImagePlaceholder(220),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 16,
                end: 16,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(AppSymbols.close),
                ),
              ),
            ],
          ),
        );
      },
    );
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

