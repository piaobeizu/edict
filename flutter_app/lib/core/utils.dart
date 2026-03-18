import 'package:flutter/material.dart';

import '../models/task.dart';
import 'constants.dart';
import 'theme.dart';

enum PipeNodeStatus { done, active, pending }

class PipeStatus {
  final String key;
  final String dept;
  final String icon;
  final String action;
  final PipeNodeStatus status;

  const PipeStatus({
    required this.key,
    required this.dept,
    required this.icon,
    required this.action,
    required this.status,
  });
}

bool isEdict(Task t) => t.id.toUpperCase().startsWith('JJC-');

bool isSession(Task t) => RegExp(r'^(OC-|MC-)', caseSensitive: false).hasMatch(t.id);

bool isArchived(Task t) => t.archived || const ['Done', 'Cancelled'].contains(t.state);

List<PipeStatus> getPipeStatus(Task t) {
  final stateIdx = kPipeStateIdx[t.state] ?? 4;
  return List<PipeStatus>.generate(kPipe.length, (i) {
    final stage = kPipe[i];
    final status = i < stateIdx
        ? PipeNodeStatus.done
        : i == stateIdx
            ? PipeNodeStatus.active
            : PipeNodeStatus.pending;
    return PipeStatus(
      key: stage.key,
      dept: stage.dept,
      icon: stage.icon,
      action: stage.action,
      status: status,
    );
  });
}

Color deptColor(String dept) => kDeptColor[dept] ?? EdictTheme.muted;

String stateLabel(Task t) {
  final r = t.reviewRound;
  if (t.state == 'Menxia' && r > 1) return '门下审议（第${r}轮）';
  if (t.state == 'Zhongshu' && r > 0) return '中书修订（第${r}轮）';
  if (t.state == 'YuLan') return '👑 待御批';
  return kStateLabel[t.state] ?? t.state;
}

String timeAgo(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final normalized = iso.contains('T') ? iso : '${iso.replaceFirst(' ', 'T')}Z';
    final d = DateTime.tryParse(normalized);
    if (d == null) return '';

    final diff = DateTime.now().difference(d.toLocal());
    final mins = diff.inMinutes;
    if (mins < 1) return '刚刚';
    if (mins < 60) return '${mins}分钟前';
    final hrs = diff.inHours;
    if (hrs < 24) return '${hrs}小时前';
    return '${diff.inDays}天前';
  } catch (_) {
    return '';
  }
}

String escHtml(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String extractAgent(Task t) {
  final m = RegExp(r'^OC-(\w+)-', caseSensitive: false).firstMatch(t.id);
  if (m != null) return (m.group(1) ?? '').toLowerCase();
  return t.org.replaceAll(RegExp(r'省|部'), '').toLowerCase();
}

String humanTitle(Task t, [Map<String, String> labelMap = const {}]) {
  var title = t.title;
  if (title == 'heartbeat 会话') return '💓 心跳检测';

  final m = RegExp(r'^agent:(\w+):(\w+)', caseSensitive: false).firstMatch(title);
  if (m != null) {
    final agentId = (m.group(1) ?? '').toLowerCase();
    final kind = (m.group(2) ?? '').toLowerCase();
    final agLabel = labelMap[agentId] ?? agentId;
    if (kind == 'main') return '$agLabel · 主会话';
    if (kind == 'subagent') return '$agLabel · 子任务执行';
    if (kind == 'cron') return '$agLabel · 定时任务';
    return '$agLabel · $kind';
  }

  title = title.replaceFirst(RegExp(r' 会话$'), '');
  return title.isEmpty ? t.id : title;
}

String channelLabel(Task t) {
  final now = t.now;
  if (now.contains('feishu/direct')) return '💬 飞书对话';
  if (now.contains('feishu')) return '💬 飞书';
  if (now.contains('webchat')) return '🌐 WebChat';
  if (now.contains('cron')) return '⏰ 定时';
  if (now.contains('direct')) return '📨 直连';
  return '🔗 会话';
}
