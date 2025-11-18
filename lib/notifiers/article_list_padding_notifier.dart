import 'package:flutter/foundation.dart';

class ArticleListPaddingNotifier extends ChangeNotifier {
  ArticleListPaddingNotifier._();

  static final ArticleListPaddingNotifier instance =
      ArticleListPaddingNotifier._();

  double _padding = 16.0;

  double get padding => _padding;

  void setPadding(double value) {
    final clamped = value.clamp(8.0, 32.0);
    if (_padding == clamped) return;
    _padding = clamped;
    notifyListeners();
  }
}
