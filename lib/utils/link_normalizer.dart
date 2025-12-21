/// Normalizes article links to reduce duplicate entries caused by tracking params or minor URL variants.
class LinkNormalizer {
  static final Set<String> _stripKeys = {
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_term',
    'utm_content',
    'utm_name',
    'fbclid',
    'gclid',
    'yclid',
    'mc_cid',
    'mc_eid',
    'mibextid',
    'ref',
    'source',
    'rss',
    'rss_id',
  };

  static String normalize(String link) {
    final trimmed = link.trim();
    if (trimmed.isEmpty) return trimmed;

    Uri? uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return trimmed;
    }

    if (!uri.hasScheme || uri.host.isEmpty) {
      return trimmed;
    }

    // Drop fragment
    uri = uri.replace(fragment: null);

    // Remove tracking query params
    final filteredQuery = Map.of(uri.queryParameters)
      ..removeWhere((key, value) => _stripKeys.contains(key.toLowerCase()));

    uri = uri.replace(queryParameters: filteredQuery.isEmpty ? null : filteredQuery);

    // Normalize host casing and trailing slash
    final normalizedHost = uri.host.toLowerCase();
    var path = uri.path;
    if (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }

    uri = Uri(
      scheme: uri.scheme.toLowerCase(),
      userInfo: uri.userInfo,
      host: normalizedHost,
      port: uri.hasPort ? uri.port : null,
      path: path,
      queryParameters: filteredQuery.isEmpty ? null : filteredQuery,
    );

    return uri.toString();
  }
}

