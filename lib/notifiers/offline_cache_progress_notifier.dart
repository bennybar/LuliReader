import 'dart:async';

import 'package:flutter/foundation.dart';

/// Tracks background offline caching progress so the UI can show a subtle
/// indicator without tying itself to any specific screen.
class OfflineCacheProgressNotifier extends ChangeNotifier {
  OfflineCacheProgressNotifier._();

  static final OfflineCacheProgressNotifier instance =
      OfflineCacheProgressNotifier._();

  bool _isActive = false;
  double _progress = 0.0;
  int _total = 0;
  int _processed = 0;

  bool get isActive => _isActive;
  double get progress => _progress;

  void begin({required int total}) {
    if (total <= 0) {
      reset();
      return;
    }
    _total = total;
    _processed = 0;
    _isActive = true;
    _progress = 0.0;
    notifyListeners();
  }

  void report({required int processed, required int total}) {
    if (total <= 0) {
      reset();
      return;
    }
    _total = total;
    _processed = processed.clamp(0, total);
    final ratio = (_processed / _total).clamp(0.0, 1.0);
    if (!_isActive) {
      _isActive = true;
    }
    if ((ratio - _progress).abs() < 0.001) {
      return;
    }
    _progress = ratio;
    notifyListeners();
  }

  void complete() {
    if (!_isActive) {
      reset();
      return;
    }

    _progress = 1.0;
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 350), () {
      _isActive = false;
      _progress = 0.0;
      _total = 0;
      _processed = 0;
      notifyListeners();
    });
  }

  void reset() {
    final shouldNotify = _isActive || _progress != 0.0;
    _isActive = false;
    _progress = 0.0;
    _total = 0;
    _processed = 0;
    if (shouldNotify) {
      notifyListeners();
    }
  }
}


