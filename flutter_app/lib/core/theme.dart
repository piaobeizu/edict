import 'package:flutter/material.dart';

class TagColors {
  final Color foreground;
  final Color background;
  final Color border;

  const TagColors({
    required this.foreground,
    required this.background,
    required this.border,
  });
}

class EdictTheme {
  const EdictTheme._();

  static const bg = Color(0xFF07090f);
  static const panel = Color(0xFF0f1219);
  static const panel2 = Color(0xFF141824);
  static const line = Color(0xFF1c2236);
  static const text = Color(0xFFdde4f8);
  static const muted = Color(0xFF5a6b92);
  static const ok = Color(0xFF2ecc8a);
  static const warn = Color(0xFFf5c842);
  static const danger = Color(0xFFff5270);
  static const acc = Color(0xFF6a9eff);
  static const acc2 = Color(0xFFa07aff);

  static const TextStyle headerStyle = TextStyle(
    color: text,
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 1.35,
  );

  static const TextStyle titleStyle = TextStyle(
    color: text,
    fontWeight: FontWeight.w700,
    fontSize: 15,
    height: 1.4,
  );

  static const TextStyle bodyStyle = TextStyle(
    color: text,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 1.5,
  );

  static const TextStyle mutedStyle = TextStyle(
    color: muted,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.4,
  );

  static const TextStyle captionStyle = TextStyle(
    color: muted,
    fontWeight: FontWeight.w500,
    fontSize: 10,
    height: 1.3,
    letterSpacing: 0.25,
  );

  static const TextStyle monoStyle = TextStyle(
    color: text,
    fontWeight: FontWeight.w500,
    fontSize: 11,
    fontFamily: 'monospace',
  );

  static BoxDecoration get cardDecoration => BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
      );

  static BoxDecoration get modalDecoration => BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 60,
            offset: Offset(0, 20),
          ),
        ],
      );

  static BoxDecoration get panelDecoration => BoxDecoration(
        color: panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: line),
      );

  static const Map<String, TagColors> stateTagColorMap = {
    'Done': TagColors(
      foreground: ok,
      background: Color(0xFF0a2018),
      border: Color(0x702ecc8a),
    ),
    'Blocked': TagColors(
      foreground: danger,
      background: Color(0xFF200a10),
      border: Color(0x70ff5270),
    ),
    'Cancelled': TagColors(
      foreground: danger,
      background: Color(0xFF200a10),
      border: Color(0x70ff5270),
    ),
    'Review': TagColors(
      foreground: acc,
      background: Color(0xFF0a1228),
      border: Color(0x706a9eff),
    ),
    'Doing': TagColors(
      foreground: warn,
      background: Color(0xFF201a08),
      border: Color(0x70f5c842),
    ),
  };

  static const Map<String, Color> heartbeatColorMap = {
    'active': ok,
    'warn': warn,
    'stalled': danger,
    'idle': muted,
    'unknown': muted,
  };

  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
      primary: acc,
      secondary: acc2,
      surface: panel,
      error: danger,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: text,
      onError: Colors.white,
    );

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: colorScheme,
      dividerColor: line,
      cardColor: panel,
      dialogBackgroundColor: panel,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      textTheme: const TextTheme(
        headlineSmall: headerStyle,
        titleMedium: titleStyle,
        bodyMedium: bodyStyle,
        bodySmall: mutedStyle,
        labelSmall: captionStyle,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: acc),
        ),
        hintStyle: mutedStyle,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        selectedColor: const Color(0xFF0a1228),
        labelStyle: captionStyle,
        secondaryLabelStyle: captionStyle,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
