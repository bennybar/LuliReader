class UserConfig {
  final String serverUrl;
  final String username;
  final String? password;
  final String? token;
  final int backgroundSyncIntervalMinutes;
  final int articleFetchLimit;
  final String? locale;

  UserConfig({
    required this.serverUrl,
    required this.username,
    this.password,
    this.token,
    this.backgroundSyncIntervalMinutes = 60,
    this.articleFetchLimit = 200,
    this.locale,
  });

  String get apiUrl {
    if (serverUrl.contains('api/greader.php')) {
      return serverUrl;
    }
    return '$serverUrl/api/greader.php';
  }

  Map<String, dynamic> toMap() {
    return {
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'token': token,
      'backgroundSyncIntervalMinutes': backgroundSyncIntervalMinutes,
      'articleFetchLimit': articleFetchLimit,
      'locale': locale,
    };
  }

  factory UserConfig.fromMap(Map<String, dynamic> map) {
    return UserConfig(
      serverUrl: map['serverUrl'] as String,
      username: map['username'] as String,
      password: map['password'] as String?,
      token: map['token'] as String?,
      backgroundSyncIntervalMinutes:
          map['backgroundSyncIntervalMinutes'] as int? ?? 60,
      articleFetchLimit: map['articleFetchLimit'] as int? ?? 200,
      locale: map['locale'] as String?,
    );
  }

  UserConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? token,
    int? backgroundSyncIntervalMinutes,
    int? articleFetchLimit,
    String? locale,
  }) {
    return UserConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      token: token ?? this.token,
      backgroundSyncIntervalMinutes:
          backgroundSyncIntervalMinutes ?? this.backgroundSyncIntervalMinutes,
      articleFetchLimit: articleFetchLimit ?? this.articleFetchLimit,
      locale: locale ?? this.locale,
    );
  }
}

