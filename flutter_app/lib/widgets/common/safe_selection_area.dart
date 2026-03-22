import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/core.dart';

class SafeSelectionArea extends StatefulWidget {
  const SafeSelectionArea({super.key, required this.child});

  final Widget child;

  @override
  State<SafeSelectionArea> createState() => _SafeSelectionAreaState();
}

class _SafeSelectionAreaState extends State<SafeSelectionArea> {
  String _selectedText = '';

  Future<void> _copySelection({required bool showFailMessage}) async {
    await copyTextToClipboard(
      context,
      _selectedText,
      failMessage: showFailMessage
          ? '复制失败：当前页面剪贴板受限，请使用 HTTPS 域名访问。'
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _CopySelectionIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            _CopySelectionIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CopySelectionIntent: CallbackAction<_CopySelectionIntent>(
            onInvoke: (_) {
              unawaited(_copySelection(showFailMessage: false));
              return null;
            },
          ),
        },
        child: SelectionArea(
          onSelectionChanged: (selectedContent) {
            _selectedText = selectedContent?.plainText ?? '';
          },
          contextMenuBuilder: (context, selectableRegionState) {
            final items = List<ContextMenuButtonItem>.from(
              selectableRegionState.contextMenuButtonItems,
            );
            final copyIndex = items.indexWhere(
              (item) => item.type == ContextMenuButtonType.copy,
            );
            if (copyIndex >= 0) {
              items[copyIndex] = items[copyIndex].copyWith(
                onPressed: () async {
                  await _copySelection(showFailMessage: true);
                  selectableRegionState.hideToolbar();
                },
              );
            }
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: selectableRegionState.contextMenuAnchors,
              buttonItems: items,
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _CopySelectionIntent extends Intent {
  const _CopySelectionIntent();
}
