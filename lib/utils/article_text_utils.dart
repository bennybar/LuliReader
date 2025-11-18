import 'package:intl/intl.dart';

String stripHtml(String? html) {
  if (html == null) return '';
  return html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool isRTLText(String text) {
  final rtlRegex = RegExp(r'[\u0590-\u08FF]');
  return rtlRegex.hasMatch(text);
}

String formatArticleDate(DateTime date) {
  return DateFormat('MMM d, yyyy • HH:mm').format(date);
}





