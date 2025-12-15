class Feed {
  final String id;
  final String name;
  final String? icon;
  final String url;
  final String groupId;
  final int accountId;
  final bool isNotification;
  final bool isFullContent;
  final bool isBrowser;
  final bool? isRtl; // null means auto-detect, true/false means force RTL/LTR
  final int important;

  Feed({
    required this.id,
    required this.name,
    this.icon,
    required this.url,
    required this.groupId,
    required this.accountId,
    this.isNotification = false,
    this.isFullContent = false,
    this.isBrowser = false,
    this.isRtl,
    this.important = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'url': url,
      'groupId': groupId,
      'accountId': accountId,
      'isNotification': isNotification ? 1 : 0,
      'isFullContent': isFullContent ? 1 : 0,
      'isBrowser': isBrowser ? 1 : 0,
      'isRtl': isRtl == null ? null : (isRtl! ? 1 : 0),
    };
  }

  factory Feed.fromMap(Map<String, dynamic> map) {
    final isRtlValue = map['isRtl'];
    return Feed(
      id: map['id'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String?,
      url: map['url'] as String,
      groupId: map['groupId'] as String,
      accountId: map['accountId'] as int,
      isNotification: (map['isNotification'] as int? ?? 0) == 1,
      isFullContent: (map['isFullContent'] as int? ?? 0) == 1,
      isBrowser: (map['isBrowser'] as int? ?? 0) == 1,
      isRtl: isRtlValue == null ? null : (isRtlValue as int) == 1,
    );
  }

  Feed copyWith({
    String? id,
    String? name,
    String? icon,
    String? url,
    String? groupId,
    int? accountId,
    bool? isNotification,
    bool? isFullContent,
    bool? isBrowser,
    bool? isRtl,
    int? important,
  }) {
    return Feed(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      url: url ?? this.url,
      groupId: groupId ?? this.groupId,
      accountId: accountId ?? this.accountId,
      isNotification: isNotification ?? this.isNotification,
      isFullContent: isFullContent ?? this.isFullContent,
      isBrowser: isBrowser ?? this.isBrowser,
      isRtl: isRtl ?? this.isRtl,
      important: important ?? this.important,
    );
  }
}

// Forward declaration - Article is defined in article.dart
class FeedWithArticle {
  final Feed feed;
  final List<dynamic> articles; // Using dynamic to avoid circular dependency

  FeedWithArticle({
    required this.feed,
    required this.articles,
  });
}

