import 'package:flutter/material.dart';

class RtlHelper {
  /// Detects if text content is in an RTL language (Hebrew, Arabic, etc.)
  /// by analyzing the characters in the text
  static bool isRtlContent(String text) {
    if (text.isEmpty) return false;
    
    // Count RTL characters
    int rtlCount = 0;
    int totalChars = 0;
    
    for (final char in text.runes) {
      final codePoint = char;
      // Skip whitespace, punctuation, and numbers
      if (codePoint <= 0x007F || // Basic ASCII
          (codePoint >= 0x0030 && codePoint <= 0x0039) || // Numbers
          (codePoint >= 0x0020 && codePoint <= 0x0040) || // Punctuation
          (codePoint >= 0x005B && codePoint <= 0x0060) || // More punctuation
          (codePoint >= 0x007B && codePoint <= 0x007E)) { // More punctuation
        continue;
      }
      
      totalChars++;
      
      // Hebrew: U+0590 to U+05FF
      if (codePoint >= 0x0590 && codePoint <= 0x05FF) {
        rtlCount++;
      }
      // Arabic: U+0600 to U+06FF (includes Arabic, Persian, Urdu)
      else if (codePoint >= 0x0600 && codePoint <= 0x06FF) {
        rtlCount++;
      }
      // Arabic Supplement: U+0750 to U+077F
      else if (codePoint >= 0x0750 && codePoint <= 0x077F) {
        rtlCount++;
      }
      // Arabic Extended-A: U+08A0 to U+08FF
      else if (codePoint >= 0x08A0 && codePoint <= 0x08FF) {
        rtlCount++;
      }
      // Arabic Presentation Forms-A: U+FB50 to U+FDFF
      else if (codePoint >= 0xFB50 && codePoint <= 0xFDFF) {
        rtlCount++;
      }
      // Arabic Presentation Forms-B: U+FE70 to U+FEFF
      else if (codePoint >= 0xFE70 && codePoint <= 0xFEFF) {
        rtlCount++;
      }
    }
    
    // If we have at least 3 RTL characters and they make up at least 30% of the text, it's RTL
    if (totalChars > 0 && rtlCount >= 3) {
      final rtlRatio = rtlCount / totalChars;
      return rtlRatio >= 0.3;
    }
    
    return false;
  }

  /// Detects if the current locale is RTL (Hebrew, Arabic, etc.)
  /// This is kept for backward compatibility but content-based detection is preferred
  static bool isRtl(Locale locale, {bool? feedRtl, bool? groupRtl}) {
    // Feed-level RTL setting takes precedence (force override)
    if (feedRtl != null && feedRtl == true) {
      return true;
    }
    // Group-level RTL setting (force override)
    if (groupRtl != null && groupRtl == true) {
      return true;
    }
    // Don't auto-detect by locale - use content-based detection instead
    return false;
  }

  /// Gets text direction based on content analysis
  /// Feed/group RTL settings can force RTL, otherwise content is analyzed
  static TextDirection getTextDirectionFromContent(String content, {bool? feedRtl, bool? groupRtl}) {
    // Feed-level RTL setting takes precedence (force override)
    if (feedRtl != null && feedRtl == true) {
      return TextDirection.rtl;
    }
    // Group-level RTL setting (force override)
    if (groupRtl != null && groupRtl == true) {
      return TextDirection.rtl;
    }
    // Analyze content to determine RTL
    return isRtlContent(content) ? TextDirection.rtl : TextDirection.ltr;
  }

  /// Gets text direction based on locale and optional feed/group settings
  /// This is kept for backward compatibility
  static TextDirection getTextDirection(Locale locale, {bool? feedRtl, bool? groupRtl}) {
    return isRtl(locale, feedRtl: feedRtl, groupRtl: groupRtl) 
        ? TextDirection.rtl 
        : TextDirection.ltr;
  }
}

