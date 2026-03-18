import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../providers/morning_provider.dart';
import 'mobile_ui_kit.dart';
import 'mobile_surface.dart';

class MobileNewsScreen extends ConsumerWidget {
  const MobileNewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: MobileImmersiveBackground.pagePadding,
            children: [
              MobileSectionTitle(
                title: '🌤️ 要闻晨览',
                trailing: Text(
                  '$dateText · 晴',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF78716C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
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
                    margin: const EdgeInsets.only(bottom: 10),
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
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF78716C),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.35,
                              color: Color(0xFF1C1917),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (item.body.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              item.body,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: Color(0xFF78716C),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
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
                  label: '推送到飞书',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已触发推送（演示）'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(milliseconds: 1200),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
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
