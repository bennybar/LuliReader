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
  final bool isUnread;
  final bool isStarred;
  final bool isReadLater;
  final DateTime? updateAt;
  String? fullContent; // Cached full content after download

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
    this.isUnread = true,
    this.isStarred = false,
    this.isReadLater = false,
    this.updateAt,
    this.fullContent,
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
      'feedId': feedId,
      'accountId': accountId,
      'isUnread': isUnread ? 1 : 0,
      'isStarred': isStarred ? 1 : 0,
      'isReadLater': isReadLater ? 1 : 0,
      'updateAt': updateAt?.toIso8601String(),
      'fullContent': fullContent,
    };
  }

  factory Article.fromMap(Map<String, dynamic> map) {
    return Article(
      id: map['id'] as String,
      date: DateTime.parse(map['date'] as String),
      title: map['title'] as String,
      author: map['author'] as String?,
      rawDescription: map['rawDescription'] as String,
      shortDescription: map['shortDescription'] as String,
      img: map['img'] as String?,
      link: map['link'] as String,
      feedId: map['feedId'] as String,
      accountId: map['accountId'] as int,
      isUnread: (map['isUnread'] as int? ?? 1) == 1,
      isStarred: (map['isStarred'] as int? ?? 0) == 1,
      isReadLater: (map['isReadLater'] as int? ?? 0) == 1,
      updateAt: map['updateAt'] != null
          ? DateTime.parse(map['updateAt'] as String)
          : null,
      fullContent: map['fullContent'] as String?,
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
    bool? isUnread,
    bool? isStarred,
    bool? isReadLater,
    DateTime? updateAt,
    String? fullContent,
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
      feedId: feedId ?? this.feedId,
      accountId: accountId ?? this.accountId,
      isUnread: isUnread ?? this.isUnread,
      isStarred: isStarred ?? this.isStarred,
      isReadLater: isReadLater ?? this.isReadLater,
      updateAt: updateAt ?? this.updateAt,
      fullContent: fullContent ?? this.fullContent,
    );
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

