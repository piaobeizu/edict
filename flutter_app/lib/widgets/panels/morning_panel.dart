import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/api_provider.dart';
import '../../providers/morning_provider.dart';
import '../../providers/notify_provider.dart';

const Map<String, ({String icon, Color color, String desc})> _catMeta =
    <String, ({String icon, Color color, String desc})>{
  '政治': (icon: '🏛️', color: EdictTheme.acc, desc: '全球政治动态'),
  '军事': (icon: '⚔️', color: EdictTheme.danger, desc: '军事与冲突'),
  '经济': (icon: '💹', color: EdictTheme.ok, desc: '经济与市场'),
  'AI大模型': (icon: '🤖', color: EdictTheme.acc2, desc: 'AI与大模型进展'),
};

const List<String> _defaultCats = <String>['政治', '军事', '经济', 'AI大模型'];

class MorningPanel extends ConsumerStatefulWidget {
  const MorningPanel({super.key});

  @override
  ConsumerState<MorningPanel> createState() => _MorningPanelState();
}

class _MorningPanelState extends ConsumerState<MorningPanel> {
  bool _showConfig = false;
  SubConfig? _localConfig;

  bool _refreshing = false;
  int _refreshSeconds = 0;
  Timer? _refreshTicker;
  ProviderSubscription<AsyncValue<SubConfig>>? _subConfigSub;

  @override
  void initState() {
    super.initState();
    _subConfigSub = ref.listenManual<AsyncValue<SubConfig>>(subConfigProvider, (
      previous,
      next,
    ) {
      final config = next.valueOrNull;
      if (config != null && mounted) {
        setState(() {
          _localConfig = SubConfig(
            categories: config.categories
                .map((e) => SubCategoryConfig(name: e.name, enabled: e.enabled))
                .toList(growable: false),
            keywords: List<String>.from(config.keywords),
            customFeeds: config.customFeeds
                .map((e) => CustomFeed(name: e.name, url: e.url, category: e.category))
                .toList(growable: false),
            feishuWebhook: config.feishuWebhook,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _subConfigSub?.close();
    _refreshTicker?.cancel();
    super.dispose();
  }

  Future<void> _refreshNews() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshSeconds = 0;
    });
    _refreshTicker?.cancel();
    _refreshTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _refreshSeconds += 1);
    });

    await ref.read(morningBriefProvider.notifier).triggerRefreshAndPoll();

    _refreshTicker?.cancel();
    _refreshTicker = null;
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _refreshSeconds = 0;
    });

    final state = ref.read(morningBriefProvider);
    if (state.hasError) {
      _snack('采集失败：${state.error}', isError: true);
    } else {
      _snack('✅ 天下要闻已更新');
    }
  }

  void _snack(String msg, {bool isError = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? EdictTheme.danger : EdictTheme.ok,
      ),
    );
  }

  Set<String> _enabledSet(SubConfig? config) {
    if (config == null) return _defaultCats.toSet();
    return config.categories
        .where((c) => c.enabled)
        .map((c) => c.name)
        .toSet();
  }

  void _toggleCat(String name) {
    final config = _localConfig;
    if (config == null) return;
    final cats = List<SubCategoryConfig>.from(config.categories);
    final idx = cats.indexWhere((c) => c.name == name);
    if (idx >= 0) {
      final c = cats[idx];
      cats[idx] = SubCategoryConfig(name: c.name, enabled: !c.enabled);
    } else {
      cats.add(SubCategoryConfig(name: name, enabled: true));
    }
    setState(() {
      _localConfig = SubConfig(
        categories: cats,
        keywords: config.keywords,
        customFeeds: config.customFeeds,
        feishuWebhook: config.feishuWebhook,
      );
    });
  }

  void _addKeyword(String value) {
    final config = _localConfig;
    final kw = value.trim();
    if (config == null || kw.isEmpty) return;
    final kws = List<String>.from(config.keywords);
    if (!kws.contains(kw)) kws.add(kw);
    setState(() {
      _localConfig = SubConfig(
        categories: config.categories,
        keywords: kws,
        customFeeds: config.customFeeds,
        feishuWebhook: config.feishuWebhook,
      );
    });
  }

  void _removeKeyword(int i) {
    final config = _localConfig;
    if (config == null || i < 0 || i >= config.keywords.length) return;
    final kws = List<String>.from(config.keywords)..removeAt(i);
    setState(() {
      _localConfig = SubConfig(
        categories: config.categories,
        keywords: kws,
        customFeeds: config.customFeeds,
        feishuWebhook: config.feishuWebhook,
      );
    });
  }

  void _addFeed(String name, String url, String category) {
    final config = _localConfig;
    if (config == null) return;
    if (name.trim().isEmpty || url.trim().isEmpty) {
      _snack('请填写源名称和URL', isError: true);
      return;
    }
    final feeds = List<CustomFeed>.from(config.customFeeds)
      ..add(CustomFeed(name: name.trim(), url: url.trim(), category: category));
    setState(() {
      _localConfig = SubConfig(
        categories: config.categories,
        keywords: config.keywords,
        customFeeds: feeds,
        feishuWebhook: config.feishuWebhook,
      );
    });
  }

  void _removeFeed(int i) {
    final config = _localConfig;
    if (config == null || i < 0 || i >= config.customFeeds.length) return;
    final feeds = List<CustomFeed>.from(config.customFeeds)..removeAt(i);
    setState(() {
      _localConfig = SubConfig(
        categories: config.categories,
        keywords: config.keywords,
        customFeeds: feeds,
        feishuWebhook: config.feishuWebhook,
      );
    });
  }

  Future<void> _saveConfig() async {
    final config = _localConfig;
    if (config == null) return;
    final result = await ref.read(subConfigProvider.notifier).save(config);
    if (!mounted) return;
    if (result.ok) {
      _snack('订阅配置已保存');
    } else {
      _snack(result.error ?? '保存失败', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final morningAsync = ref.watch(morningBriefProvider);
    final subConfigAsync = ref.watch(subConfigProvider);
    final brief = morningAsync.valueOrNull;

    if (_localConfig == null && subConfigAsync.valueOrNull != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _localConfig = subConfigAsync.valueOrNull;
        });
      });
    }

    final cats = brief?.categories ?? const <String, List<MorningNewsItem>>{};
    final enabled = _enabledSet(_localConfig);
    final totalNews = cats.values.fold<int>(0, (acc, list) => acc + list.length);

    final dateLabel = _formatBriefDate(brief?.date);
    final generated = brief?.generatedAt ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MorningHeader(
            dateLabel: dateLabel,
            generatedAt: generated,
            totalNews: totalNews,
            showConfig: _showConfig,
            onToggleConfig: () => setState(() => _showConfig = !_showConfig),
            refreshing: _refreshing,
            refreshSeconds: _refreshSeconds,
            onRefresh: _refreshNews,
          ),
          if (_showConfig && _localConfig != null) ...[
            const SizedBox(height: 14),
            SubConfigPanel(
              config: _localConfig!,
              enabledSet: enabled,
              onToggleCat: _toggleCat,
              onAddKeyword: _addKeyword,
              onRemoveKeyword: _removeKeyword,
              onAddFeed: _addFeed,
              onRemoveFeed: _removeFeed,
              onSave: _saveConfig,
            ),
          ],
          const SizedBox(height: 14),
          if (morningAsync.isLoading && brief == null)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else if (morningAsync.hasError)
            _EmptyCard(text: '加载失败：${morningAsync.error}')
          else if (cats.isEmpty)
            const _EmptyCard(text: '暂无数据，点击右上角「立即采集」获取今日简报')
          else
            _NewsGrid(
              categories: cats,
              enabledSet: enabled,
              userKeywords: (_localConfig?.keywords ?? const <String>[])
                  .map((e) => e.toLowerCase())
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _MorningHeader extends StatelessWidget {
  const _MorningHeader({
    required this.dateLabel,
    required this.generatedAt,
    required this.totalNews,
    required this.showConfig,
    required this.onToggleConfig,
    required this.refreshing,
    required this.refreshSeconds,
    required this.onRefresh,
  });

  final String dateLabel;
  final String generatedAt;
  final int totalNews;
  final bool showConfig;
  final VoidCallback onToggleConfig;
  final bool refreshing;
  final int refreshSeconds;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: EdictTheme.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: <Color>[Color(0xFFFFD67A), Color(0xFFF5C842), Color(0xFFFFF2B8)],
                  ).createShader(bounds),
                  child: const Text(
                    '🌅 天下要闻',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 21,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (dateLabel.isNotEmpty) dateLabel,
                    if (generatedAt.isNotEmpty) '采集于 $generatedAt',
                    '共 $totalNews 条要闻',
                  ].join(' | '),
                  style: EdictTheme.mutedStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                onPressed: onToggleConfig,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: showConfig ? EdictTheme.acc : EdictTheme.line),
                ),
                child: const Text('⚙ 订阅配置'),
              ),
              FilledButton(
                onPressed: refreshing ? null : onRefresh,
                child: Text(refreshing ? '采集中… (${refreshSeconds}s)' : '⟳ 立即采集'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SubConfigPanel extends StatefulWidget {
  const SubConfigPanel({
    super.key,
    required this.config,
    required this.enabledSet,
    required this.onToggleCat,
    required this.onAddKeyword,
    required this.onRemoveKeyword,
    required this.onAddFeed,
    required this.onRemoveFeed,
    required this.onSave,
  });

  final SubConfig config;
  final Set<String> enabledSet;
  final ValueChanged<String> onToggleCat;
  final ValueChanged<String> onAddKeyword;
  final ValueChanged<int> onRemoveKeyword;
  final void Function(String name, String url, String category) onAddFeed;
  final ValueChanged<int> onRemoveFeed;
  final Future<void> Function() onSave;

  @override
  State<SubConfigPanel> createState() => _SubConfigPanelState();
}

class _SubConfigPanelState extends State<SubConfigPanel> {
  final _kwController = TextEditingController();
  final _feedNameController = TextEditingController();
  final _feedUrlController = TextEditingController();

  String _feedCat = _defaultCats.first;
  bool _saving = false;

  @override
  void dispose() {
    _kwController.dispose();
    _feedNameController.dispose();
    _feedUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allCats = <String>[..._defaultCats];
    for (final c in widget.config.categories) {
      if (!allCats.contains(c.name)) allCats.add(c.name);
    }
    if (!allCats.contains(_feedCat)) {
      _feedCat = allCats.first;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: EdictTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚙ 订阅配置', style: EdictTheme.titleStyle),
          const SizedBox(height: 12),
          const Text('订阅分类', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allCats.map((cat) {
              final meta = _catMeta[cat] ?? (icon: '📰', color: EdictTheme.acc, desc: cat);
              final enabled = widget.enabledSet.contains(cat);
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => widget.onToggleCat(cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: enabled ? EdictTheme.acc : EdictTheme.line),
                    color: enabled ? EdictTheme.acc.withOpacity(0.12) : Colors.transparent,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(meta.icon),
                      const SizedBox(width: 5),
                      Text(cat, style: const TextStyle(fontSize: 12)),
                      if (enabled) ...[
                        const SizedBox(width: 4),
                        const Text('✓', style: TextStyle(fontSize: 10, color: EdictTheme.ok)),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 14),
          const Text('关注关键词', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List<Widget>.generate(widget.config.keywords.length, (i) {
              final kw = widget.config.keywords[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: EdictTheme.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: EdictTheme.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(kw, style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => widget.onRemoveKeyword(i),
                      child: const Text('✕', style: TextStyle(fontSize: 11, color: EdictTheme.danger)),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _kwController,
                  decoration: const InputDecoration(hintText: '输入关键词'),
                  onSubmitted: (v) {
                    widget.onAddKeyword(v);
                    _kwController.clear();
                  },
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: () {
                  widget.onAddKeyword(_kwController.text);
                  _kwController.clear();
                },
                child: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('自定义信息源', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 8),
          ...List<Widget>.generate(widget.config.customFeeds.length, (i) {
            final feed = widget.config.customFeeds[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text(feed.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feed.url,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: EdictTheme.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(feed.category, style: const TextStyle(fontSize: 11, color: EdictTheme.acc)),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => widget.onRemoveFeed(i),
                    child: const Text('✕', style: TextStyle(fontSize: 12, color: EdictTheme.danger)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _feedNameController,
                  decoration: const InputDecoration(hintText: '源名称'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _feedUrlController,
                  decoration: const InputDecoration(hintText: 'RSS / URL'),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  value: _feedCat,
                  decoration: const InputDecoration(isDense: true),
                  items: allCats
                      .map((e) => DropdownMenuItem<String>(value: e, child: Text(e, style: const TextStyle(fontSize: 12))))
                      .toList(growable: false),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _feedCat = v);
                  },
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: () {
                  widget.onAddFeed(_feedNameController.text, _feedUrlController.text, _feedCat);
                  _feedNameController.clear();
                  _feedUrlController.clear();
                },
                child: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      await widget.onSave();
                      if (mounted) setState(() => _saving = false);
                    },
              child: Text(_saving ? '保存中…' : '💾 保存订阅配置'),
            ),
          ),
          const SizedBox(height: 14),
          const NotifyChannelsPanel(),
        ],
      ),
    );
  }
}

class NotifyChannelsPanel extends ConsumerStatefulWidget {
  const NotifyChannelsPanel({super.key});

  @override
  ConsumerState<NotifyChannelsPanel> createState() => _NotifyChannelsPanelState();
}

class _NotifyChannelsPanelState extends ConsumerState<NotifyChannelsPanel> {
  List<ChannelMeta>? _channels;
  bool _saving = false;
  String? _testingChannel;
  final Map<String, ({bool ok, String msg})> _testResults =
      <String, ({bool ok, String msg})>{};
  ProviderSubscription<AsyncValue<NotifyChannelsResult>>? _notifySub;

  @override
  void initState() {
    super.initState();
    _notifySub = ref.listenManual<AsyncValue<NotifyChannelsResult>>(
      notifyChannelsProvider,
      (previous, next) {
        final incoming = next.valueOrNull;
        if (incoming?.channels != null && mounted) {
          setState(() {
          _channels = incoming!.channels!
              .map(
                (ch) => ChannelMeta(
                  channelId: ch.channelId,
                  displayName: ch.displayName,
                  icon: ch.icon,
                  configSchema: ch.configSchema,
                  enabled: ch.enabled,
                  params: Map<String, dynamic>.from(ch.params),
                  secretState: ch.secretState == null
                      ? null
                      : Map<String, dynamic>.from(ch.secretState!),
                ),
              )
              .toList(growable: false);
        });
      }
      },
    );
  }

  @override
  void dispose() {
    _notifySub?.close();
    super.dispose();
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? EdictTheme.danger : EdictTheme.ok,
      ),
    );
  }

  void _toggleChannel(String channelId) {
    final channels = _channels;
    if (channels == null) return;
    setState(() {
      _channels = channels
          .map((ch) {
            if (ch.channelId != channelId) return ch;
            return ChannelMeta(
              channelId: ch.channelId,
              displayName: ch.displayName,
              icon: ch.icon,
              configSchema: ch.configSchema,
              enabled: !ch.enabled,
              params: ch.params,
              secretState: ch.secretState,
            );
          })
          .toList(growable: false);
    });
  }

  void _updateParam(String channelId, String key, String value) {
    final channels = _channels;
    if (channels == null) return;
    setState(() {
      _channels = channels
          .map((ch) {
            if (ch.channelId != channelId) return ch;
            final nextParams = <String, dynamic>{...ch.params, key: value};
            return ChannelMeta(
              channelId: ch.channelId,
              displayName: ch.displayName,
              icon: ch.icon,
              configSchema: ch.configSchema,
              enabled: ch.enabled,
              params: nextParams,
              secretState: ch.secretState,
            );
          })
          .toList(growable: false);
    });
  }

  Future<void> _saveAll() async {
    final channels = _channels;
    if (channels == null) return;
    setState(() => _saving = true);
    final api = ref.read(apiClientProvider);
    final configObj = <String, Map<String, dynamic>>{};
    for (final ch in channels) {
      final hasParams = ch.params.values.any((v) => (v?.toString() ?? '').trim().isNotEmpty);
      if (ch.enabled || hasParams) {
        configObj[ch.channelId] = <String, dynamic>{'enabled': ch.enabled, ...ch.params};
      }
    }
    final result = await api.saveNotifyConfig(<String, dynamic>{'channels': configObj});
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.ok) {
      _snack('推送渠道配置已保存');
      unawaited(ref.read(notifyChannelsProvider.notifier).refresh());
    } else {
      _snack(result.error ?? '保存失败', isError: true);
    }
  }

  Future<void> _testChannel(ChannelMeta ch) async {
    setState(() {
      _testingChannel = ch.channelId;
      _testResults[ch.channelId] = (ok: false, msg: '测试中…');
    });
    final api = ref.read(apiClientProvider);
    final params = ch.params.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    final result = await api.testNotifyChannel(ch.channelId, params);
    if (!mounted) return;
    final msg = result.message ?? result.error ?? '未知';
    setState(() {
      _testingChannel = null;
      _testResults[ch.channelId] = (ok: result.ok, msg: msg);
    });
    if (result.ok) {
      _snack('${ch.displayName} 测试成功');
    } else {
      _snack('${ch.displayName} 测试失败: $msg', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(notifyChannelsProvider);
    final channels = _channels ?? channelsAsync.valueOrNull?.channels;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('📡 推送渠道', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 8),
        if (channelsAsync.isLoading && channels == null)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('加载推送渠道…', style: EdictTheme.mutedStyle),
          )
        else if (channels == null || channels.isEmpty)
          const SizedBox.shrink()
        else
          Column(
            children: channels.map((ch) {
              final test = _testResults[ch.channelId];
              final enabled = ch.enabled;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: enabled ? EdictTheme.bg : Colors.transparent,
                  border: Border.all(color: enabled ? EdictTheme.acc : EdictTheme.line),
                ),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => _toggleChannel(ch.channelId),
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        children: [
                          Text(ch.icon.isEmpty ? '📡' : ch.icon, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(ch.displayName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          Switch.adaptive(
                            value: enabled,
                            onChanged: (_) => _toggleChannel(ch.channelId),
                          ),
                        ],
                      ),
                    ),
                    if (enabled) ...[
                      const SizedBox(height: 8),
                      ...ch.configSchema.map((field) {
                        final raw = ch.params[field.key]?.toString() ?? field.defaultValue ?? '';
                        final isPwd = field.type == ChannelFieldType.password;
                        final secret = ch.secretState?[field.key];
                        final hasSaved = secret is Map && secret['has_value'] == true;
                        final masked = secret is Map ? secret['masked']?.toString() ?? '' : '';
                        final placeholder = isPwd && hasSaved
                            ? '${field.placeholder ?? ''}${masked.isNotEmpty ? '（已保存：$masked，留空则保持不变）' : ''}'
                            : (field.placeholder ?? '');

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 96,
                                child: Text.rich(
                                  TextSpan(
                                    text: field.label,
                                    children: [
                                      if (field.isRequired == true)
                                        const TextSpan(text: ' *', style: TextStyle(color: EdictTheme.danger)),
                                    ],
                                  ),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 11, color: EdictTheme.muted),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final opts = field.options ?? const <String>[];
                                    final selectValue = raw.isNotEmpty && opts.contains(raw)
                                        ? raw
                                        : null;
                                    if (field.type == ChannelFieldType.select) {
                                      return DropdownButtonFormField<String>(
                                        value: selectValue,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                        ),
                                        items: opts
                                            .map(
                                              (opt) => DropdownMenuItem<String>(
                                                value: opt,
                                                child: Text(
                                                  opt,
                                                  style: const TextStyle(fontSize: 11),
                                                ),
                                              ),
                                            )
                                            .toList(growable: false),
                                        onChanged: (v) => _updateParam(
                                          ch.channelId,
                                          field.key,
                                          v ?? '',
                                        ),
                                      );
                                    }
                                    return TextFormField(
                                      key: ValueKey('${ch.channelId}:${field.key}'),
                                      initialValue: raw,
                                      obscureText: isPwd,
                                      keyboardType:
                                          field.type == ChannelFieldType.number
                                          ? TextInputType.number
                                          : TextInputType.text,
                                      onChanged: (v) => _updateParam(
                                        ch.channelId,
                                        field.key,
                                        v,
                                      ),
                                      style: const TextStyle(fontSize: 11),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: placeholder,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (ch.configSchema.any((f) => f.type == ChannelFieldType.password))
                        const Padding(
                          padding: EdgeInsets.only(left: 104, bottom: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '密码/Token 字段不会回传明文；留空表示沿用已保存值。',
                              style: TextStyle(fontSize: 10, color: EdictTheme.muted),
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          const SizedBox(width: 104),
                          OutlinedButton(
                            onPressed: _testingChannel == ch.channelId ? null : () => _testChannel(ch),
                            child: Text(_testingChannel == ch.channelId ? '⏳ 测试中…' : '🧪 测试'),
                          ),
                          const SizedBox(width: 8),
                          if (test != null)
                            Expanded(
                              child: Text(
                                '${test.ok ? '✅' : '❌'} ${test.msg}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: test.ok ? EdictTheme.ok : EdictTheme.danger,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }).toList(growable: false),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saving ? null : _saveAll,
            child: Text(_saving ? '⏳ 保存中…' : '💾 保存推送配置'),
          ),
        ),
      ],
    );
  }
}

class _NewsGrid extends StatelessWidget {
  const _NewsGrid({
    required this.categories,
    required this.enabledSet,
    required this.userKeywords,
  });

  final Map<String, List<MorningNewsItem>> categories;
  final Set<String> enabledSet;
  final List<String> userKeywords;

  @override
  Widget build(BuildContext context) {
    final visible = categories.entries
        .where((entry) => enabledSet.contains(entry.key))
        .toList(growable: false);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 560,
      ),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final cat = visible[i].key;
        final items = visible[i].value;
        final meta = _catMeta[cat] ?? (icon: '📰', color: EdictTheme.acc, desc: cat);

        final scored = items
            .map((item) {
              final text = '${item.title}${item.summary ?? ''}${item.desc ?? ''}'.toLowerCase();
              final kwHits = userKeywords.where((kw) => text.contains(kw)).length;
              return (item: item, kwHits: kwHits);
            })
            .toList(growable: false)
          ..sort((a, b) => b.kwHits.compareTo(a.kwHits));

        return Container(
          decoration: EdictTheme.cardDecoration,
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  Text(meta.icon),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(cat, style: TextStyle(color: meta.color, fontWeight: FontWeight.w800)),
                  ),
                  Text('${scored.length} 条', style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: scored.isEmpty
                    ? const Center(child: Text('暂无新闻', style: EdictTheme.mutedStyle))
                    : ListView.separated(
                        itemCount: scored.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final pair = scored[idx];
                          return _NewsCard(item: pair.item, kwHits: pair.kwHits, catIcon: meta.icon);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item, required this.kwHits, required this.catIcon});

  final MorningNewsItem item;
  final int kwHits;
  final String catIcon;

  Future<void> _open() async {
    if (item.link.isEmpty) return;
    final uri = Uri.tryParse(item.link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final hasImg = (item.image ?? '').startsWith('http');
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: EdictTheme.panel2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: EdictTheme.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 72,
                height: 52,
                child: hasImg
                    ? CachedNetworkImage(
                        imageUrl: item.image!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _FallbackImage(icon: catIcon),
                        placeholder: (_, __) => Container(
                          color: EdictTheme.bg,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.6),
                          ),
                        ),
                      )
                    : _FallbackImage(icon: catIcon),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (kwHits > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: EdictTheme.acc2.withOpacity(0.12),
                            border: Border.all(color: EdictTheme.acc2.withOpacity(0.4)),
                          ),
                          child: const Text('⭐关注', style: TextStyle(fontSize: 9, color: EdictTheme.acc2)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.summary ?? item.desc ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: EdictTheme.muted),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '📡 ${item.source}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: EdictTheme.muted),
                        ),
                      ),
                      if ((item.pubDate ?? '').isNotEmpty)
                        Text(
                          _formatPub(item.pubDate!),
                          style: const TextStyle(fontSize: 10, color: EdictTheme.muted),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackImage extends StatelessWidget {
  const _FallbackImage({required this.icon});

  final String icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EdictTheme.bg,
      alignment: Alignment.center,
      child: Text(icon, style: const TextStyle(fontSize: 20)),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: EdictTheme.cardDecoration,
      child: Text(text, style: EdictTheme.mutedStyle),
    );
  }
}

String _formatBriefDate(String? value) {
  if (value == null || value.isEmpty) return '';
  try {
    if (RegExp(r'^\d{8}$').hasMatch(value)) {
      final d = DateFormat('yyyyMMdd').parseStrict(value);
      return DateFormat('yyyy年MM月dd日').format(d);
    }
    final d = DateTime.tryParse(value);
    if (d == null) return value;
    return DateFormat('yyyy年MM月dd日').format(d);
  } catch (_) {
    return value;
  }
}

String _formatPub(String value) {
  if (value.length >= 16) return value.substring(0, 16);
  return value;
}
