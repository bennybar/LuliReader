/// Normalizes article titles for duplicate detection.
/// - Trims whitespace
/// - Collapses internal whitespace to single spaces
/// - Uppercases for case-insensitive matching
class TitleNormalizer {
  static String normalize(String title) {
    var t = title.trim();
    // Collapse multiple whitespace to a single space
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t.toUpperCase();
  }
}

