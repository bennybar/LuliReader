import 'package:flutter/foundation.dart';

class StarredRefreshNotifier extends ChangeNotifier {
  StarredRefreshNotifier._();
  static final StarredRefreshNotifier instance = StarredRefreshNotifier._();

  void ping() {
    notifyListeners();
  }
}


