import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/article.dart';
import '../utils/article_text_utils.dart';
import '../utils/image_utils.dart';

class ArticleCard extends StatelessWidget {
  final Article article;
  final String summary;
  final String sourceName;
  final VoidCallback onTap;
  final int summaryLines;

  const ArticleCard({
    super.key,
    required this.article,
    required this.summary,
    required this.sourceName,
    required this.onTap,
    this.summaryLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    final isTitleRTL = isRTLText(article.title);
    final isSummaryRTL = isRTLText(summary);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ArticleThumbnail(imageUrl: article.imageUrl),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                article.title,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                textAlign: isTitleRTL ? TextAlign.right : TextAlign.left,
                                textDirection: isTitleRTL ? TextDirection.rtl : TextDirection.ltr,
                              ),
                            ),
                            if (!article.isRead)
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sourceName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                          textAlign: isTitleRTL ? TextAlign.right : TextAlign.left,
                          textDirection: isTitleRTL ? TextDirection.rtl : TextDirection.ltr,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          summary.isEmpty ? 'No summary available.' : summary,
                          maxLines: summaryLines,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                          textAlign: isSummaryRTL ? TextAlign.right : TextAlign.left,
                          textDirection: isSummaryRTL ? TextDirection.rtl : TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    formatArticleDate(article.publishedDate),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleThumbnail extends StatefulWidget {
  final String? imageUrl;

  const _ArticleThumbnail({required this.imageUrl});

  @override
  State<_ArticleThumbnail> createState() => _ArticleThumbnailState();
}

class _ArticleThumbnailState extends State<_ArticleThumbnail> {
  Future<RemoteImageFormat>? _formatFuture;

  @override
  void initState() {
    super.initState();
    _prepareFormatFuture();
  }

  @override
  void didUpdateWidget(covariant _ArticleThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _prepareFormatFuture();
    }
  }

  void _prepareFormatFuture() {
    final url = widget.imageUrl;
    if (url != null && !ImageUtils.isDataUri(url) && !ImageUtils.looksLikeSvgUrl(url)) {
      _formatFuture = ImageUtils.detectRemoteFormat(url);
    } else {
      _formatFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.image_not_supported,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
      ),
    );

    final url = widget.imageUrl;
    if (url == null || url.isEmpty) {
      return placeholder;
    }

    if (ImageUtils.isDataUri(url)) {
      if (ImageUtils.isSvgDataUri(url)) {
        final svgString = ImageUtils.decodeSvgDataUri(url);
        if (svgString == null) return placeholder;
        return _buildSvgContainer(
          SvgPicture.string(svgString, fit: BoxFit.cover),
        );
      } else {
        final bytes = ImageUtils.decodeBitmapDataUri(url);
        if (bytes == null) return placeholder;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            bytes,
            width: 90,
            height: 90,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          ),
        );
      }
    }

    if (ImageUtils.looksLikeSvgUrl(url)) {
      return _buildSvgContainer(
        SvgPicture.network(
          url,
          fit: BoxFit.cover,
          placeholderBuilder: (_) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (_formatFuture != null) {
      return FutureBuilder<RemoteImageFormat>(
        future: _formatFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingContainer();
          }
          final format = snapshot.data ?? RemoteImageFormat.unknown;
          switch (format) {
            case RemoteImageFormat.svg:
              debugPrint('Bitmap request redirected to SVG renderer for $url');
              return _buildSvgContainer(
                SvgPicture.network(
                  url,
                  fit: BoxFit.cover,
                  placeholderBuilder: (_) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              );
            case RemoteImageFormat.bitmap:
              debugPrint('Bitmap image confirmed via header for $url');
              return _buildBitmapFromCache(url, placeholder);
            case RemoteImageFormat.unsupported:
              debugPrint('Unsupported remote image format for $url. Showing placeholder.');
              return placeholder;
            case RemoteImageFormat.unknown:
            default:
              debugPrint('Unknown remote image format for $url, defaulting to bitmap decode');
              return _buildBitmapFromCache(url, placeholder);
          }
        },
      );
    }

    debugPrint('Bitmap image assumed (no header probe) for $url');
    return _buildBitmapFromCache(url, placeholder);
  }

  Widget _buildLoadingContainer() => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: const SizedBox(
          width: 90,
          height: 90,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );

  Widget _buildBitmapFromCache(String url, Widget placeholder) {
    return FutureBuilder<Uint8List?>(
      future: ImageUtils.decodedBitmapBytes(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingContainer();
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          debugPrint('Bitmap decode failed for $url; showing placeholder.');
          return placeholder;
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            bytes,
            width: 90,
            height: 90,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        );
      },
    );
  }

  Widget _buildSvgContainer(Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 90, height: 90, child: child),
      );
}


