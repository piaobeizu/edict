import 'package:flutter/material.dart';

import 'theme.dart';

/// Premium light-first mobile theme for Edict (三省六部).
class MobileTheme {
  const MobileTheme._();

  // Core palette
  static const Color bg = Color(0xFFFAFAF9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFF5F5F4);
  static const Color surfaceRaised = Color(0xFFFFFFFF);

  static const Color heading = Color(0xFF1C1917);
  static const Color body = Color(0xFF292524);
  static const Color secondaryText = Color(0xFF78716C);
  static const Color tertiaryText = Color(0xFFA8A29E);

  static const Color accent = Color(0xFF6366F1);
  static const Color accentSoft = Color(0xFFE7E7FF);
  static const Color secondaryAccent = Color(0xFF14B8A6);
  static const Color secondaryAccentSoft = Color(0xFFD8F8F3);

  // Status palette
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Support colors
  static const Color divider = Color(0xFFF0EEEB);
  static const Color focus = accent;

  // Spacing scale
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space14 = 14;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;

  // Radius scale
  static const double radius12 = 12;
  static const double radius16 = 16;
  static const double radius18 = 18;
  static const double radius20 = 20;
  static const double radius24 = 24;
  static const double radiusPill = 999;

  static const BorderRadius cardRadius =
      BorderRadius.all(Radius.circular(radius18));
  static const BorderRadius sheetRadius =
      BorderRadius.vertical(top: Radius.circular(radius24));

  // Timing helpers for micro-interactions
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 280);

  // Typography (system-native feel)
  static const TextStyle headingStyle = TextStyle(
    color: heading,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.25,
  );

  static const TextStyle titleStyle = TextStyle(
    color: heading,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle bodyStyle = TextStyle(
    color: body,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const TextStyle captionStyle = TextStyle(
    color: secondaryText,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static const TextStyle labelStyle = TextStyle(
    color: secondaryText,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0.2,
  );

  // Gradients
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFECEBFF),
      Color(0xFFE6FBF8),
      Color(0xFFFFFFFF),
    ],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7C7FF8),
      Color(0xFF6366F1),
      Color(0xFF4F46E5),
    ],
  );

  static const LinearGradient tealAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF5FE3D3),
      Color(0xFF14B8A6),
    ],
  );

  // Shadows
  static const List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Color(0x120C0A09),
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Color(0x140C0A09),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> shadowLg = [
    BoxShadow(
      color: Color(0x190C0A09),
      blurRadius: 28,
      offset: Offset(0, 14),
    ),
  ];

  // Decoration helpers
  static BoxDecoration cardDecoration({
    Gradient? gradient,
    List<BoxShadow>? shadows,
    BorderRadius? borderRadius,
    Color? color,
  }) {
    return BoxDecoration(
      color: color ?? surfaceRaised,
      gradient: gradient,
      borderRadius: borderRadius ?? cardRadius,
      boxShadow: shadows ?? shadowSm,
    );
  }

  static BoxDecoration panelDecoration({
    Color? color,
    BorderRadius? borderRadius,
  }) {
    return BoxDecoration(
      color: color ?? surface,
      borderRadius:
          borderRadius ?? const BorderRadius.all(Radius.circular(radius16)),
      boxShadow: shadowSm,
    );
  }

  static BoxDecoration bottomSheetDecoration() {
    return const BoxDecoration(
      color: surface,
      borderRadius: sheetRadius,
      boxShadow: shadowLg,
    );
  }

  // State colors for existing Edict workflow states.
  static const Map<String, TagColors> stateTagColorMap = {
    'Inbox': TagColors(
      foreground: Color(0xFF475569),
      background: Color(0xFFF1F5F9),
      border: Color(0xFFE2E8F0),
    ),
    'Taizi': TagColors(
      foreground: Color(0xFF6D28D9),
      background: Color(0xFFF5F3FF),
      border: Color(0xFFE9D5FF),
    ),
    'Zhongshu': TagColors(
      foreground: info,
      background: Color(0xFFEFF6FF),
      border: Color(0xFFBFDBFE),
    ),
    'Menxia': TagColors(
      foreground: secondaryAccent,
      background: Color(0xFFECFEFF),
      border: Color(0xFF99F6E4),
    ),
    'YuLan': TagColors(
      foreground: warning,
      background: Color(0xFFFFFBEB),
      border: Color(0xFFFDE68A),
    ),
    'Assigned': TagColors(
      foreground: accent,
      background: Color(0xFFEEF2FF),
      border: Color(0xFFC7D2FE),
    ),
    'Doing': TagColors(
      foreground: warning,
      background: Color(0xFFFFFBEB),
      border: Color(0xFFFDE68A),
    ),
    'Review': TagColors(
      foreground: info,
      background: Color(0xFFEFF6FF),
      border: Color(0xFFBFDBFE),
    ),
    'Done': TagColors(
      foreground: success,
      background: Color(0xFFECFDF5),
      border: Color(0xFFBBF7D0),
    ),
    'Blocked': TagColors(
      foreground: danger,
      background: Color(0xFFFEF2F2),
      border: Color(0xFFFECACA),
    ),
    'Cancelled': TagColors(
      foreground: danger,
      background: Color(0xFFFEF2F2),
      border: Color(0xFFFECACA),
    ),
  };

  static const Map<String, Color> heartbeatColorMap = {
    'active': success,
    'warn': warning,
    'stalled': danger,
    'idle': secondaryText,
    'unknown': secondaryText,
  };

  static Widget pullToRefresh({
    required Future<void> Function() onRefresh,
    required Widget child,
  }) {
    return RefreshIndicator.adaptive(
      color: accent,
      backgroundColor: surface,
      displacement: 30,
      edgeOffset: 8,
      strokeWidth: 2.6,
      onRefresh: onRefresh,
      child: child,
    );
  }

  static ThemeData get lightTheme {
    const colorScheme = ColorScheme.light(
      primary: accent,
      secondary: secondaryAccent,
      surface: surface,
      error: danger,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: heading,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      cardColor: surface,
      dividerColor: divider,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        headlineSmall: headingStyle,
        titleMedium: titleStyle,
        bodyMedium: bodyStyle,
        bodySmall: captionStyle,
        labelSmall: labelStyle,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: heading,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: heading,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: cardRadius),
        shadowColor: const Color(0x120C0A09),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: space16,
          vertical: space14,
        ),
        hintStyle: const TextStyle(
          color: tertiaryText,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(
          color: secondaryText,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius16),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius16),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius16),
          borderSide: const BorderSide(color: focus, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius16),
          borderSide: const BorderSide(color: danger, width: 1.1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius16),
          borderSide: const BorderSide(color: danger, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceSoft,
        selectedColor: accentSoft,
        disabledColor: surfaceSoft,
        labelStyle: labelStyle,
        secondaryLabelStyle: labelStyle,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: sheetRadius),
        dragHandleColor: Color(0xFFD6D3D1),
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        circularTrackColor: Color(0xFFE7E5E4),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
