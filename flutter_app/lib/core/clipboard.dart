import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'clipboard_stub.dart'
    if (dart.library.html) 'clipboard_web.dart' as browser_clipboard;

Future<bool> copyTextToClipboard(
  BuildContext context,
  String text, {
  String? successMessage,
  String? failMessage,
}) async {
  final value = text.trim();
  if (value.isEmpty) return false;

  if (kIsWeb) {
    final copied = await browser_clipboard.tryCopyText(value);
    if (copied) {
      if (successMessage != null && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
      return true;
    }
  }

  try {
    await Clipboard.setData(ClipboardData(text: value));
    if (successMessage != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    }
    return true;
  } on PlatformException {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            failMessage ??
                (kIsWeb
                    ? '当前页面剪贴板不可用（HTTP 环境常见），请优先使用 HTTPS 域名访问。'
                    : '复制失败，请稍后重试。'),
          ),
        ),
      );
    }
    return false;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(failMessage ?? '复制失败，请稍后重试。')),
      );
    }
    return false;
  }
}
