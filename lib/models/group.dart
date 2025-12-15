class Group {
  final String id;
  final String name;
  final int accountId;
  final bool? isRtl; // null means auto-detect, true/false means force RTL/LTR

  Group({
    required this.id,
    required this.name,
    required this.accountId,
    this.isRtl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'accountId': accountId,
      'isRtl': isRtl == null ? null : (isRtl! ? 1 : 0),
    };
  }

  factory Group.fromMap(Map<String, dynamic> map) {
    final isRtlValue = map['isRtl'];
    return Group(
      id: map['id'] as String,
      name: map['name'] as String,
      accountId: map['accountId'] as int,
      isRtl: isRtlValue == null ? null : (isRtlValue as int) == 1,
    );
  }

  Group copyWith({
    String? id,
    String? name,
    int? accountId,
    bool? isRtl,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      accountId: accountId ?? this.accountId,
      isRtl: isRtl ?? this.isRtl,
    );
  }
}

// Forward declaration - Feed is defined in feed.dart
class GroupWithFeed {
  final Group group;
  final List<dynamic> feeds; // Using dynamic to avoid circular dependency

  GroupWithFeed({
    required this.group,
    required this.feeds,
  });
}

