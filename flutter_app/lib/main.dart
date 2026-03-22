import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'app_mobile.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const isMobile = !kIsWeb;
  if (isMobile) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ),
    );
  }
  if (kIsWeb) {
    // Auto-enable web semantics so automation and a11y tools
    // can operate without manual "Enable accessibility" clicks.
    SemanticsBinding.instance.ensureSemantics();
  }
  runApp(
    const ProviderScope(
      child: isMobile ? EdictMobileApp() : EdictApp(),
    ),
  );
}
