import 'dart:html' as html;

Future<bool> tryCopyText(String text) async {
  if (text.isEmpty) return false;

  try {
    final clipboard = html.window.navigator.clipboard;
    if (clipboard != null) {
      await clipboard.writeText(text);
      return true;
    }
  } catch (_) {
    // Fall through to execCommand fallback for insecure contexts.
  }

  try {
    final textArea = html.TextAreaElement()
      ..value = text
      ..style.position = 'fixed'
      ..style.left = '-9999px'
      ..style.top = '-9999px'
      ..style.opacity = '0';
    html.document.body?.append(textArea);
    textArea.focus();
    textArea.select();
    final copied = html.document.execCommand('copy');
    textArea.remove();
    return copied;
  } catch (_) {
    return false;
  }
}
