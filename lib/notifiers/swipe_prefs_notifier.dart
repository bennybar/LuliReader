import 'package:flutter/foundation.dart';

class SwipePrefsNotifier extends ChangeNotifier {
  SwipePrefsNotifier._();
  static final SwipePrefsNotifier instance = SwipePrefsNotifier._();

  void ping() {
    notifyListeners();
  }
}


