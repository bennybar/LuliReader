class Feed {
  final String id;
  final String title;
  final String? description;
  final String? websiteUrl;
  final String? iconUrl;
  final DateTime? lastSyncDate;
  final int unreadCount;
  final DateTime? lastArticleDate;

  Feed({
    required this.id,
    required this.title,
    this.description,
    this.websiteUrl,
    this.iconUrl,
    this.lastSyncDate,
    this.unreadCount = 0,
    this.lastArticleDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'websiteUrl': websiteUrl,
      'iconUrl': iconUrl,
      'lastSyncDate': lastSyncDate?.toIso8601String(),
      'unreadCount': unreadCount,
      'lastArticleDate': lastArticleDate?.toIso8601String(),
    };
  }

  factory Feed.fromMap(Map<String, dynamic> map) {
    return Feed(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      websiteUrl: map['websiteUrl'] as String?,
      iconUrl: map['iconUrl'] as String?,
      lastSyncDate: map['lastSyncDate'] != null
          ? DateTime.parse(map['lastSyncDate'] as String)
          : null,
      unreadCount: map['unreadCount'] as int? ?? 0,
      lastArticleDate: map['lastArticleDate'] != null
          ? DateTime.parse(map['lastArticleDate'] as String)
          : null,
    );
  }

  Feed copyWith({
    String? id,
    String? title,
    String? description,
    String? websiteUrl,
    String? iconUrl,
    DateTime? lastSyncDate,
    int? unreadCount,
    DateTime? lastArticleDate,
  }) {
    return Feed(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      iconUrl: iconUrl ?? this.iconUrl,
      lastSyncDate: lastSyncDate ?? this.lastSyncDate,
      unreadCount: unreadCount ?? this.unreadCount,
      lastArticleDate: lastArticleDate ?? this.lastArticleDate,
    );
  }
}

