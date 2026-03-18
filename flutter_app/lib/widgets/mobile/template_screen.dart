import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import 'mobile_ui_kit.dart';
import 'mobile_surface.dart';

class MobileTemplateScreen extends ConsumerStatefulWidget {
  const MobileTemplateScreen({super.key});

  @override
  ConsumerState<MobileTemplateScreen> createState() =>
      _MobileTemplateScreenState();
}

class _MobileTemplateScreenState extends ConsumerState<MobileTemplateScreen> {
  String? _selectedCat;

  @override
  Widget build(BuildContext context) {
    final cats = <String>{for (final t in kTemplates) t.cat}.toList()..sort();
    final templates = _selectedCat == null
        ? kTemplates
        : kTemplates
            .where((t) => t.cat == _selectedCat)
            .toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF9),
      body: MobileImmersiveBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: MobileImmersiveBackground.pagePadding,
            children: [
              MobileSectionTitle(
                title: '旨库',
                trailing: Text(
                  '${kTemplates.length}类高频模板',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF78716C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chip('全部', _selectedCat == null,
                        () => setState(() => _selectedCat = null)),
                    const SizedBox(width: 8),
                    for (final c in cats) ...[
                      _chip(c, _selectedCat == c,
                          () => setState(() => _selectedCat = c)),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: templates.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.86,
                ),
                itemBuilder: (context, index) {
                  final card = templates[index];
                  return MobileSurfaceCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(card.icon, style: const TextStyle(fontSize: 20)),
                        const SizedBox(height: 6),
                        Text(
                          card.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1C1917),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          card.desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF78716C),
                            height: 1.4,
                          ),
                        ),
                        const Spacer(),
                        MobilePillTag(
                          text: '${card.est} · ${card.cost}',
                          background: const Color(0xFFF5F5F4),
                          foreground: const Color(0xFF57534E),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              backgroundColor: const Color(0xFFEEF2FF),
                              foregroundColor: const Color(0xFF3730A3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('已选择模板：${card.name}（交互接入中）'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(milliseconds: 1200),
                                ),
                              );
                            },
                            child: const Text(
                              '一键下旨',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? const Color(0xFF4338CA) : const Color(0xFFF5F5F4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF57534E),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
