class Account {
  final int? id;
  final String name;
  final AccountType type;
  final DateTime? updateAt;
  final String? lastArticleId;
  final String? apiEndpoint; // Remote API base (e.g. FreshRSS greader endpoint)
  final String? username; // Remote account username
  final String? password; // Stored to allow re-auth when token expires
  final String? authToken; // Cached remote auth token
  final int syncInterval; // minutes
  final bool syncOnStart;
  final bool syncOnlyOnWiFi;
  final bool syncOnlyWhenCharging;
  final int keepArchived; // milliseconds
  final String syncBlockList;
  final bool isFullContent; // Parse full content for all feeds
  final int swipeStartAction; // 0=None, 1=ToggleRead, 2=ToggleStarred
  final int swipeEndAction; // 0=None, 1=ToggleRead, 2=ToggleStarred
  final int defaultScreen; // 0=Feeds, 1=Flow
  final String lastFlowFilter; // all, unread, starred
  final int maxPastDays; // limit how far back to sync articles

  Account({
    this.id,
    required this.name,
    required this.type,
    this.updateAt,
    this.lastArticleId,
    this.apiEndpoint,
    this.username,
    this.password,
    this.authToken,
    this.syncInterval = 30,
    this.syncOnStart = false,
    this.syncOnlyOnWiFi = false,
    this.syncOnlyWhenCharging = false,
    this.keepArchived = 2592000000, // 30 days
    this.syncBlockList = '',
    this.isFullContent = false,
    this.swipeStartAction = 2, // Default: ToggleStarred
    this.swipeEndAction = 1, // Default: ToggleRead
    this.defaultScreen = 1, // Default: Flow
    this.lastFlowFilter = 'all', // Default: all
    this.maxPastDays = 10, // Default: 10 days back
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.id,
      'updateAt': updateAt?.toUtc().toIso8601String(),
      'lastArticleId': lastArticleId,
      'apiEndpoint': apiEndpoint,
      'username': username,
      'password': password,
      'authToken': authToken,
      'syncInterval': syncInterval,
      'syncOnStart': syncOnStart ? 1 : 0,
      'syncOnlyOnWiFi': syncOnlyOnWiFi ? 1 : 0,
      'syncOnlyWhenCharging': syncOnlyWhenCharging ? 1 : 0,
      'keepArchived': keepArchived,
      'syncBlockList': syncBlockList,
      'isFullContent': isFullContent ? 1 : 0,
      'swipeStartAction': swipeStartAction,
      'swipeEndAction': swipeEndAction,
      'defaultScreen': defaultScreen,
      'lastFlowFilter': lastFlowFilter,
      'maxPastDays': maxPastDays,
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: AccountType.fromId(map['type'] as int),
      updateAt: map['updateAt'] != null
          ? DateTime.parse(map['updateAt'] as String).toLocal()
          : null,
      lastArticleId: map['lastArticleId'] as String?,
      apiEndpoint: map['apiEndpoint'] as String?,
      username: map['username'] as String?,
      password: map['password'] as String?,
      authToken: map['authToken'] as String?,
      syncInterval: map['syncInterval'] as int? ?? 30,
      syncOnStart: (map['syncOnStart'] as int? ?? 0) == 1,
      syncOnlyOnWiFi: (map['syncOnlyOnWiFi'] as int? ?? 0) == 1,
      syncOnlyWhenCharging: (map['syncOnlyWhenCharging'] as int? ?? 0) == 1,
      keepArchived: map['keepArchived'] as int? ?? 2592000000,
      syncBlockList: map['syncBlockList'] as String? ?? '',
      isFullContent: (map['isFullContent'] as int? ?? 0) == 1,
      swipeStartAction: map['swipeStartAction'] as int? ?? 2,
      swipeEndAction: map['swipeEndAction'] as int? ?? 1,
      defaultScreen: map['defaultScreen'] as int? ?? 1,
      lastFlowFilter: map['lastFlowFilter'] as String? ?? 'all',
      maxPastDays: map['maxPastDays'] as int? ?? 10,
    );
  }

  Account copyWith({
    int? id,
    String? name,
    AccountType? type,
    DateTime? updateAt,
    String? lastArticleId,
    String? apiEndpoint,
    String? username,
    String? password,
    String? authToken,
    int? syncInterval,
    bool? syncOnStart,
    bool? syncOnlyOnWiFi,
    bool? syncOnlyWhenCharging,
    int? keepArchived,
    String? syncBlockList,
    bool? isFullContent,
    int? swipeStartAction,
    int? swipeEndAction,
    int? defaultScreen,
    String? lastFlowFilter,
    int? maxPastDays,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      updateAt: updateAt ?? this.updateAt,
      lastArticleId: lastArticleId ?? this.lastArticleId,
      apiEndpoint: apiEndpoint ?? this.apiEndpoint,
      username: username ?? this.username,
      password: password ?? this.password,
      authToken: authToken ?? this.authToken,
      syncInterval: syncInterval ?? this.syncInterval,
      syncOnStart: syncOnStart ?? this.syncOnStart,
      syncOnlyOnWiFi: syncOnlyOnWiFi ?? this.syncOnlyOnWiFi,
      syncOnlyWhenCharging: syncOnlyWhenCharging ?? this.syncOnlyWhenCharging,
      keepArchived: keepArchived ?? this.keepArchived,
      syncBlockList: syncBlockList ?? this.syncBlockList,
      isFullContent: isFullContent ?? this.isFullContent,
      swipeStartAction: swipeStartAction ?? this.swipeStartAction,
      swipeEndAction: swipeEndAction ?? this.swipeEndAction,
      defaultScreen: defaultScreen ?? this.defaultScreen,
      lastFlowFilter: lastFlowFilter ?? this.lastFlowFilter,
      maxPastDays: maxPastDays ?? this.maxPastDays,
    );
  }
}

enum AccountType {
  local(0),
  freshrss(1),
  miniflux(2);

  final int id;
  const AccountType(this.id);

  static AccountType fromId(int id) {
    return AccountType.values.firstWhere((e) => e.id == id, orElse: () => AccountType.local);
  }
}

