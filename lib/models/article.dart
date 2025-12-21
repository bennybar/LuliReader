class Article {
  final String id;
  final DateTime date;
  final String title;
  final String? author;
  final String rawDescription;
  final String shortDescription;
  final String? img;
  final String link;
  final String feedId;
  final int accountId;
  final String? normalizedLink;
  final String? normalizedTitle;
  final int? syncedAt; // epoch millis (UTC) when this article was synced locally
  final bool isUnread;
  final bool isStarred;
  final bool isReadLater;
  final DateTime? updateAt;
  String? fullContent; // Cached full content after download
  final String? syncHash; // Base64 hash of title + feed URL for duplicate detection

  Article({
    required this.id,
    required this.date,
    required this.title,
    this.author,
    required this.rawDescription,
    required this.shortDescription,
    this.img,
    required this.link,
    required this.feedId,
    required this.accountId,
    this.normalizedLink,
    this.normalizedTitle,
    this.syncedAt,
    this.isUnread = true,
    this.isStarred = false,
    this.isReadLater = false,
    this.updateAt,
    this.fullContent,
    this.syncHash,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'title': title,
      'author': author,
      'rawDescription': rawDescription,
      'shortDescription': shortDescription,
      'img': img,
      'link': link,
      'normalizedLink': normalizedLink,
      'normalizedTitle': normalizedTitle,
      'syncedAt': syncedAt,
      'feedId': feedId,
      'accountId': accountId,
      'isUnread': isUnread ? 1 : 0,
      'isStarred': isStarred ? 1 : 0,
      'isReadLater': isReadLater ? 1 : 0,
      'updateAt': updateAt?.toUtc().toIso8601String(),
      'fullContent': fullContent,
      'syncHash': syncHash,
    };
  }

  factory Article.fromMap(Map<String, dynamic> map) {
    // Parse date and convert to local timezone for consistent display
    final dateString = map['date'] as String;
    final parsedDate = DateTime.parse(dateString);
    final localDate = parsedDate.isUtc ? parsedDate.toLocal() : parsedDate;
    
    return Article(
      id: map['id'] as String,
      date: localDate,
      title: map['title'] as String,
      author: map['author'] as String?,
      rawDescription: map['rawDescription'] as String,
      shortDescription: map['shortDescription'] as String,
      img: map['img'] as String?,
      link: map['link'] as String,
      normalizedLink: map['normalizedLink'] as String?,
      normalizedTitle: map['normalizedTitle'] as String?,
      syncedAt: map['syncedAt'] as int?,
      feedId: map['feedId'] as String,
      accountId: map['accountId'] as int,
      isUnread: (map['isUnread'] as int? ?? 1) == 1,
      isStarred: (map['isStarred'] as int? ?? 0) == 1,
      isReadLater: (map['isReadLater'] as int? ?? 0) == 1,
      updateAt: map['updateAt'] != null
          ? DateTime.parse(map['updateAt'] as String).toLocal()
          : null,
      fullContent: map['fullContent'] as String?,
      syncHash: map['syncHash'] as String?,
    );
  }

  Article copyWith({
    String? id,
    DateTime? date,
    String? title,
    String? author,
    String? rawDescription,
    String? shortDescription,
    String? img,
    String? link,
    String? feedId,
    int? accountId,
    String? normalizedLink,
    String? normalizedTitle,
    int? syncedAt,
    bool? isUnread,
    bool? isStarred,
    bool? isReadLater,
    DateTime? updateAt,
    String? fullContent,
    String? syncHash,
  }) {
    return Article(
      id: id ?? this.id,
      date: date ?? this.date,
      title: title ?? this.title,
      author: author ?? this.author,
      rawDescription: rawDescription ?? this.rawDescription,
      shortDescription: shortDescription ?? this.shortDescription,
      img: img ?? this.img,
      link: link ?? this.link,
      normalizedLink: normalizedLink ?? this.normalizedLink,
      normalizedTitle: normalizedTitle ?? this.normalizedTitle,
      syncedAt: syncedAt ?? this.syncedAt,
      feedId: feedId ?? this.feedId,
      accountId: accountId ?? this.accountId,
      isUnread: isUnread ?? this.isUnread,
      isStarred: isStarred ?? this.isStarred,
      isReadLater: isReadLater ?? this.isReadLater,
      updateAt: updateAt ?? this.updateAt,
      fullContent: fullContent ?? this.fullContent,
      syncHash: syncHash ?? this.syncHash,
    );
  }

  DateTime? get syncedAtDate {
    if (syncedAt == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(syncedAt!, isUtc: true).toLocal();
  }
}

// Forward declaration - Feed is defined in feed.dart
class ArticleWithFeed {
  final Article article;
  final dynamic feed; // Using dynamic to avoid circular dependency

  ArticleWithFeed({
    required this.article,
    required this.feed,
  });
}

