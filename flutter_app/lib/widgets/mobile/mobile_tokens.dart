import 'package:flutter/material.dart';

/// Shared visual tokens for mobile pages aligned with prototype.
class MobileUiTokens {
  const MobileUiTokens._();

  static const Color pageBg = Color(0xFFFAFAF9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color heading = Color(0xFF1C1917);
  static const Color body = Color(0xFF292524);
  static const Color muted = Color(0xFF78716C);
  static const Color border = Color(0xFFF0EEEB);
  static const Color primary = Color(0xFF4338CA);
  static const Color primaryStart = Color(0xFF6366F1);
  static const Color primaryEnd = Color(0xFF4338CA);

  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(16, 8, 16, 96);
  static const EdgeInsets pagePaddingWide = EdgeInsets.fromLTRB(12, 8, 12, 96);

  static const double gap6 = 6;
  static const double gap8 = 8;
  static const double gap10 = 10;
  static const double gap12 = 12;
  static const double gap16 = 16;

  static const TextStyle trailingText = TextStyle(
    color: muted,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle sectionLabel = TextStyle(
    color: heading,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle bodyMuted = TextStyle(
    color: muted,
    fontSize: 12,
    height: 1.5,
  );

  static const TextStyle cardTitle = TextStyle(
    color: heading,
    fontSize: 16,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle cardDesc = TextStyle(
    color: muted,
    fontSize: 12,
    height: 1.4,
  );

  static const TextStyle miniMeta = TextStyle(
    color: Color(0xFF57534E),
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryStart, primaryEnd],
  );

  static const LinearGradient indigoSoftGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
  );

  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x12000000),
    blurRadius: 12,
    offset: Offset(0, 4),
  );
}
