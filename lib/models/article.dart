class Article {
  final String id;
  final String feedId;
  final String title;
  final String? content;
  final String? summary;
  final String? author;
  final DateTime publishedDate;
  final DateTime? updatedDate;
  final String? link;
  final String? imageUrl;
  final bool isRead;
  final bool isStarred;
  final DateTime? lastSyncedAt;
  final DateTime? readAt;
  final String? offlineCachePath;
  final DateTime? offlineCachedAt;

  Article({
    required this.id,
    required this.feedId,
    required this.title,
    this.content,
    this.summary,
    this.author,
    required this.publishedDate,
    this.updatedDate,
    this.link,
    this.imageUrl,
    this.isRead = false,
    this.isStarred = false,
    this.lastSyncedAt,
    this.readAt,
    this.offlineCachePath,
    this.offlineCachedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'feedId': feedId,
      'title': title,
      'content': content,
      'summary': summary,
      'author': author,
      'publishedDate': publishedDate.toIso8601String(),
      'updatedDate': updatedDate?.toIso8601String(),
      'link': link,
      'imageUrl': imageUrl,
      'isRead': isRead ? 1 : 0,
      'isStarred': isStarred ? 1 : 0,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'readAt': readAt?.toIso8601String(),
      'offlineCachePath': offlineCachePath,
      'offlineCachedAt': offlineCachedAt?.toIso8601String(),
    };
  }

  factory Article.fromMap(Map<String, dynamic> map) {
    return Article(
      id: map['id'] as String,
      feedId: map['feedId'] as String,
      title: map['title'] as String,
      content: map['content'] as String?,
      summary: map['summary'] as String?,
      author: map['author'] as String?,
      publishedDate: DateTime.parse(map['publishedDate'] as String),
      updatedDate: map['updatedDate'] != null
          ? DateTime.parse(map['updatedDate'] as String)
          : null,
      link: map['link'] as String?,
      imageUrl: map['imageUrl'] as String?,
      isRead: (map['isRead'] as int) == 1,
      isStarred: (map['isStarred'] as int) == 1,
      lastSyncedAt: map['lastSyncedAt'] != null
          ? DateTime.parse(map['lastSyncedAt'] as String)
          : null,
      readAt: map['readAt'] != null ? DateTime.parse(map['readAt'] as String) : null,
      offlineCachePath: map['offlineCachePath'] as String?,
      offlineCachedAt: map['offlineCachedAt'] != null
          ? DateTime.parse(map['offlineCachedAt'] as String)
          : null,
    );
  }

  Article copyWith({
    String? id,
    String? feedId,
    String? title,
    String? content,
    String? summary,
    String? author,
    DateTime? publishedDate,
    DateTime? updatedDate,
    String? link,
    String? imageUrl,
    bool? isRead,
    bool? isStarred,
    DateTime? lastSyncedAt,
  }) {
    return Article(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      title: title ?? this.title,
      content: content ?? this.content,
      summary: summary ?? this.summary,
      author: author ?? this.author,
      publishedDate: publishedDate ?? this.publishedDate,
      updatedDate: updatedDate ?? this.updatedDate,
      link: link ?? this.link,
      imageUrl: imageUrl ?? this.imageUrl,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      readAt: readAt ?? this.readAt,
      offlineCachePath: offlineCachePath ?? this.offlineCachePath,
      offlineCachedAt: offlineCachedAt ?? this.offlineCachedAt,
    );
  }
}

