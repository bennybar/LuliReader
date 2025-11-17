enum SwipeAction {
  toggleRead,
  toggleStar,
}

extension SwipeActionX on SwipeAction {
  String get storageValue {
    switch (this) {
      case SwipeAction.toggleStar:
        return 'toggle_star';
      case SwipeAction.toggleRead:
      default:
        return 'toggle_read';
    }
  }

  String get label {
    switch (this) {
      case SwipeAction.toggleStar:
        return 'Toggle Star';
      case SwipeAction.toggleRead:
      default:
        return 'Toggle Read';
    }
  }
}

SwipeAction swipeActionFromString(String? value) {
  switch (value) {
    case 'toggle_star':
      return SwipeAction.toggleStar;
    case 'toggle_read':
    default:
      return SwipeAction.toggleRead;
  }
}


