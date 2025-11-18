import 'package:flutter/foundation.dart';

class UnreadRefreshNotifier extends ChangeNotifier {
  UnreadRefreshNotifier._();
  static final UnreadRefreshNotifier instance = UnreadRefreshNotifier._();

  void ping() {
    notifyListeners();
  }
}



