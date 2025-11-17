import 'package:flutter/foundation.dart';

class LastSyncNotifier extends ChangeNotifier {
  LastSyncNotifier._();
  static final LastSyncNotifier instance = LastSyncNotifier._();

  void ping() {
    notifyListeners();
  }
}


