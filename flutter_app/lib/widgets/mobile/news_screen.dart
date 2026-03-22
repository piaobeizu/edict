import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../providers/api_provider.dart';
import '../../providers/morning_provider.dart';
import 'mobile_tokens.dart';
import 'mobile_ui_kit.dart';
import 'mobile_surface.dart';

class MobileNewsScreen extends ConsumerStatefulWidget {
  const MobileNewsScreen({super.key});

  @override
  ConsumerState<MobileNewsScreen> createState() => _MobileNewsScreenState();
}

class _MobileNewsScreenState extends ConsumerState<MobileNewsScreen> {
  bool _pushing = false;

  Map<String, String> _toStringParams(Map<String, dynamic> raw) {
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value == null) continue;
      out[entry.key] = value.toString();
    }
    return out;
  }

  Future<void> _pushMorningToFeishu() async {
    if (_pushing) {
      return;
    }
    setState(() => _pushing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(morningBriefProvider.notifier).triggerRefreshAndPoll();
      final api = ref.read(apiClientProvider);
      final channelsResult = await api.notifyChannels();
      final channels = channelsResult.channels ?? const <ChannelMeta>[];
      ChannelMeta? feishu;
      for (final channel in channels) {
        if (!channel.enabled) continue;
        if (!channel.channelId.toLowerCase().contains('feishu')) continue;
        feishu = channel;
        break;
      }

      if (feishu == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('晨报已刷新，未检测到已启用的飞书通知渠道'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final testResult =
          await api.testNotifyChannel(feishu.channelId, _toStringParams(feishu.params));
      if (testResult.ok) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已刷新晨报并推送飞书测试消息'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(milliseconds: 1400),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('晨报已刷新，飞书推送失败：${testResult.error ?? testResult.message ?? '未知错误'}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('推送失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pushing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final morningAsync = ref.watch(morningBriefProvider);
    final items = <_NewsUiItem>[
      for (final entry in (morningAsync.valueOrNull?.categories ??
              const <String, List<MorningNewsItem>>{})
          .entries)
        for (final news in entry.value)
          _NewsUiItem(
            chip: entry.key,
            source: news.source.isEmpty ? '未知来源' : news.source,
            title: news.title,
            body: (news.summary ?? news.desc ?? '').trim(),
            link: news.link,
          ),
    ];
    final dateText = morningAsync.valueOrNull?.date ?? '今日';

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF9),
      body: MobileImmersiveBackground(
        child: ListView(
            padding: MobileUiTokens.pagePadding,
            children: [
              MobileSectionTitle(
                title: '🌤️ 要闻晨览',
                trailing: Text(
                  '$dateText · 晴',
                  style: MobileUiTokens.trailingText,
                ),
              ),
              const SizedBox(height: MobileUiTokens.gap10),
              if (morningAsync.isLoading && items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '暂无要闻，稍后再试',
                      style: TextStyle(color: Color(0xFF78716C)),
                    ),
                  ),
                )
              else
                ...items.take(12).map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: MobileUiTokens.gap10),
                    child: MobileSurfaceCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              MobilePillTag(
                                text: item.chip,
                                background: _chipBg(item.chip),
                                foreground: _chipFg(item.chip),
                              ),
                              const Spacer(),
                              Text(
                                item.source,
                                style: MobileUiTokens.trailingText
                                    .copyWith(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: MobileUiTokens.gap8),
                          Text(
                            item.title,
                            style:
                                MobileUiTokens.cardTitle.copyWith(height: 1.35),
                          ),
                          if (item.body.isNotEmpty) ...[
                            const SizedBox(height: MobileUiTokens.gap8),
                            Text(
                              item.body,
                              style: MobileUiTokens.bodyMuted.copyWith(
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: MobileUiTokens.gap8),
                          InkWell(
                            onTap: () async {
                              final uri = Uri.tryParse(item.link);
                              if (uri == null) return;
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            child: const Text(
                              '查看原文',
                              style: TextStyle(
                                color: Color(0xFF4338CA),
                                decoration: TextDecoration.underline,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 2),
              SizedBox(
                width: double.infinity,
                child: MobilePrimaryButton(
                  label: _pushing ? '推送中...' : '推送到飞书',
                  onPressed: _pushing ? null : _pushMorningToFeishu,
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
      ),
    );
  }

  Color _chipBg(String chip) {
    if (chip.contains('财经') || chip.contains('经济')) {
      return const Color(0xFFFFF3E0);
    }
    if (chip.contains('AI')) return const Color(0xFFDCFCE7);
    return const Color(0xFF4338CA);
  }

  Color _chipFg(String chip) {
    if (chip.contains('财经') || chip.contains('经济')) {
      return const Color(0xFFB45309);
    }
    if (chip.contains('AI')) return const Color(0xFF047857);
    return Colors.white;
  }
}

class _NewsUiItem {
  const _NewsUiItem({
    required this.chip,
    required this.source,
    required this.title,
    required this.body,
    required this.link,
  });

  final String chip;
  final String source;
  final String title;
  final String body;
  final String link;
}
