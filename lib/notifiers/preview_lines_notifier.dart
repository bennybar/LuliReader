import 'package:flutter/foundation.dart';

class PreviewLinesNotifier extends ChangeNotifier {
  PreviewLinesNotifier._();
  static final PreviewLinesNotifier instance = PreviewLinesNotifier._();

  int _lines = 3;

  int get lines => _lines;

  void setLines(int value) {
    if (value == _lines) return;
    _lines = value.clamp(1, 4);
    notifyListeners();
  }
}





