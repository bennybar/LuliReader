import 'package:html/parser.dart' as html_parser;

class ReadingTime {
  // Average reading speed: 200 words per minute
  static const int wordsPerMinute = 200;

  /// Calculate reading time in minutes from text content
  static int calculateMinutes(String? content) {
    if (content == null || content.isEmpty) return 0;
    
    // If it's HTML, extract text content
    String textContent = content;
    try {
      final document = html_parser.parse(content);
      textContent = document.body?.text ?? content;
    } catch (e) {
      // If parsing fails, use content as-is
    }
    
    // Count words (split by whitespace)
    final words = textContent.trim().split(RegExp(r'\s+'));
    final wordCount = words.where((word) => word.isNotEmpty).length;
    
    // Calculate minutes (round up, minimum 1 minute if there's content)
    final minutes = (wordCount / wordsPerMinute).ceil();
    return minutes > 0 ? minutes : 0;
  }

  /// Format reading time as a readable string
  static String format(int minutes) {
    if (minutes <= 0) return '';
    if (minutes == 1) return '1 min read';
    if (minutes < 60) return '$minutes min read';
    
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return hours == 1 ? '1 hour read' : '$hours hours read';
    }
    return '$hours h ${remainingMinutes} min read';
  }

  /// Calculate and format reading time from content
  static String calculateAndFormat(String? content) {
    final minutes = calculateMinutes(content);
    return format(minutes);
  }
}














