import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

enum RemoteImageFormat { svg, bitmap, unsupported, unknown }

class ImageUtils {
  static final Map<String, Uint8List> _decodedCache = {};
  static final BaseCacheManager _cacheManager = DefaultCacheManager();
  static const Map<String, String> _fetchHeaders = {
    'User-Agent': 'LuliReader/1.0 (+https://lulireader.app)',
    'Accept': 'image/webp,image/png,image/jpeg,image/*;q=0.8,*/*;q=0.5',
  };

  static bool isDataUri(String value) => value.startsWith('data:image/');

  static bool isSvgDataUri(String value) => value.startsWith('data:image/svg+xml');

  static bool looksLikeSvgUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.svg') ||
        lower.contains('format=svg') ||
        lower.contains('mime=svg') ||
        lower.contains('svg+xml');
  }

  static String? decodeSvgDataUri(String data) {
    try {
      final idx = data.indexOf(',');
      if (idx == -1) return null;
      final payload = data.substring(idx + 1);
      if (data.contains(';base64')) {
        return utf8.decode(base64.decode(payload));
      }
      return Uri.decodeComponent(payload);
    } catch (e) {
      debugPrint('decodeSvgDataUri error: $e');
      return null;
    }
  }

  static Uint8List? decodeBitmapDataUri(String data) {
    try {
      final idx = data.indexOf(',');
      if (idx == -1) return null;
      final payload = data.substring(idx + 1);
      if (data.contains(';base64')) {
        return base64.decode(payload);
      }
      return Uint8List.fromList(Uri.decodeComponent(payload).codeUnits);
    } catch (e) {
      debugPrint('decodeBitmapDataUri error: $e');
      return null;
    }
  }

  static Future<RemoteImageFormat> detectRemoteFormat(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.head(uri, headers: _fetchHeaders).timeout(const Duration(seconds: 10));
      final contentType = response.headers['content-type']?.toLowerCase();
      debugPrint('HEAD $url => ${response.statusCode} $contentType');
      if (response.statusCode >= 400 || contentType == null) {
        return RemoteImageFormat.unknown;
      }
      if (_isSvgMime(contentType)) return RemoteImageFormat.svg;
      if (_isSupportedBitmapMime(contentType)) return RemoteImageFormat.bitmap;
      return RemoteImageFormat.unsupported;
    } catch (e) {
      debugPrint('detectRemoteFormat error for $url: $e');
      return RemoteImageFormat.unknown;
    }
  }

  static Future<Uint8List?> decodedBitmapBytes(String url) async {
    if (_decodedCache.containsKey(url)) {
      return _decodedCache[url];
    }
    try {
      final file = await _cacheManager.getSingleFile(url, headers: _fetchHeaders);
      final bytes = await file.readAsBytes();
      final pngBytes = await _decodeToPng(bytes);
      if (pngBytes == null) {
        debugPrint('Failed to decode bitmap bytes for $url');
        return null;
      }
      _decodedCache[url] = pngBytes;
      return pngBytes;
    } catch (e) {
      debugPrint('decodedBitmapBytes error for $url: $e');
      return null;
    }
  }

  static Future<void> clearCaches() async {
    _decodedCache.clear();
    try {
      await _cacheManager.emptyCache();
    } catch (e) {
      debugPrint('Failed to empty cache manager: $e');
    }
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (e) {
      debugPrint('Failed to clear painting cache: $e');
    }
  }

  static bool _isSvgMime(String? mime) => mime?.contains('svg') ?? false;

  static bool _isSupportedBitmapMime(String? mime) {
    if (mime == null) return false;
    final normalized = mime.split(';').first.trim();
    const supported = {
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/webp',
      'image/gif',
      'image/bmp',
    };
    return supported.contains(normalized);
  }

  static Future<Uint8List?> _decodeToPng(Uint8List bytes) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        return Uint8List.fromList(img.encodePng(decoded));
      }
      debugPrint('image package failed to decode bytes, attempting Flutter codec fallback.');
    } catch (e) {
      debugPrint('image package threw while decoding: $e');
    }

    try {
      final codec = await PaintingBinding.instance.instantiateImageCodecFromBuffer(
        await ui.ImmutableBuffer.fromUint8List(bytes),
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Fallback Flutter codec failed to decode bytes: $e');
      return null;
    }
  }
}


