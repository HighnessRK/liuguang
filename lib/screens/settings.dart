import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/appearance.dart';
import '../ui/theme_preview.dart';
import 'personalization.dart';
import 'vision.dart';
import 'storage.dart';
import '../ui/glass.dart';
import 'create.dart';
import 'usage.dart';
import 'updates.dart';
import '../core/updates.dart' show appVersion;

class SettingsScreen extends StatefulWidget {
  final AppStore store;
  final StudioApi api;
  const SettingsScreen({super.key, required this.store, required this.api});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final search = TextEditingController();
  AppStore get store => widget.store;
  void open(Widget Function() page) {
    FocusScope.of(context).unfocus();
    Navigator.push(context, MaterialPageRoute(builder: (_) => page()));
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<(IconData, String, String, VoidCallback)>)>[
      (
        '创作与模型',
        [
          (
            Icons.hub_outlined,
            '模型连接',
            '生图、对话与识图',
            () => open(() => ConnectionScreen(store: store, api: widget.api)),
          ),
          (
            Icons.tune_rounded,
            '生成偏好',
            '尺寸、格式与审核',
            () async {
              FocusScope.of(context).unfocus();
              final value = await Navigator.push<GenerationOptions>(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsDetail(
                    title: '生成偏好',
                    children: [GenerationSettings(initial: store.defaults)],
                  ),
                ),
              );
              if (value != null) {
                store.defaults = value;
                await store.saveSettings();
              }
            },
          ),
          (
            Icons.bar_chart_rounded,
            '使用明细',
            'Token、费用与调用记录',
            () => open(() => UsageScreen(store: store)),
          ),
        ],
      ),
      (
        '显示与交互',
        [
          (
            Icons.auto_awesome_mosaic_outlined,
            '个性化',
            '外观主题与桌面图标',
            () => open(() => PersonalizationSettings(store: store)),
          ),
          (
            Icons.touch_app_outlined,
            '交互与辅助',
            '触感、动效与文字大小',
            () => open(() => InteractionSettings(store: store)),
          ),
        ],
      ),
      (
        '应用与数据',
        [
          (
            Icons.storage_rounded,
            '存储管理',
            '作品、缓存与安装包',
            () => open(() => StorageSettings(store: store)),
          ),
          (
            Icons.system_update_outlined,
            '应用更新',
            '检查更新、更新日志与诊断日志',
            () => open(() => UpdatesScreen(store: store)),
          ),
          (
            Icons.info_outline_rounded,
            '关于琉光',
            'V$appVersion',
            () => open(
              () => const SettingsDetail(
                title: '关于琉光',
                children: [AboutStudio()],
              ),
            ),
          ),
        ],
      ),
    ];
    final query = search.text.trim().toLowerCase();
    final visible = groups
        .map(
          (g) => (
            g.$1,
            g.$2
                .where(
                  (r) => (r.$2 + r.$3 + g.$1).toLowerCase().contains(query),
                )
                .toList(),
          ),
        )
        .where((g) => g.$2.isNotEmpty);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(14, 36, 14, 18 + StudioTabInset.of(context)),
      children: [
        const SettingsHeading('设置'),
        const SizedBox(height: 18),
        GlassField(
          controller: search,
          hint: '搜索设置项',
          onChanged: (_) => setState(() {}),
          suffix: search.text.isEmpty
              ? const Icon(Icons.search_rounded, size: 22)
              : IconButton(
                  tooltip: '清除搜索',
                  onPressed: () => setState(search.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        if (visible.isEmpty)
          const EmptyState(
            icon: Icons.search_off_rounded,
            title: '没有匹配的设置项',
            subtitle: '换个关键词试试。',
          ),
        for (final (section, items) in visible) ...[
          SettingsGroupLabel(section),
          SettingsPanel(
            child: Column(
              children: [
                for (final (icon, label, subtitle, onTap) in items)
                  settingRow(
                    context,
                    icon,
                    label,
                    subtitle,
                    onTap,
                    inline: true,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 36,
        height: 1.13,
        fontWeight: FontWeight.w500,
        color: ink(context),
      ),
    ),
  );
}

class SettingsGroupLabel extends StatelessWidget {
  const SettingsGroupLabel(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 22, 14, 9),
    child: Text(
      title,
      style: TextStyle(
        color: muted(context),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      color: isDark(context)
          ? const Color(0xff202229)
          : const Color(0xfffcfcfd),
    ),
    child: Padding(padding: padding, child: child),
  );
}

Widget _line(BuildContext context) =>
    Divider(height: 1, color: muted(context).withValues(alpha: .10));

class SettingsDetail extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SettingsDetail({
    super.key,
    required this.title,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: StudioBackground(
      child: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: ink(context),
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 22),
            SettingsHeading(title),
            const SizedBox(height: 22),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class AppearanceSettings extends StatelessWidget {
  final AppStore store;
  const AppearanceSettings({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    StudioScope.of(context);
    return SettingsDetail(
      title: '外观',
      children: [
        Row(
          children: [
            for (final (value, label) in [
              ('light', '浅色模式'),
              ('dark', '深色模式'),
            ]) ...[
              if (value == 'dark') const SizedBox(width: 10),
              Expanded(
                child: _AppearanceMode(
                  value: value,
                  label: label,
                  selected:
                      store.theme == value ||
                      (store.theme == 'system' &&
                          isDark(context) == (value == 'dark')),
                  onTap: () {
                    store.theme = value;
                    store.saveSettings();
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        SettingsPanel(
          child: _toggle(context, '跟随系统', '', store.theme == 'system', (value) {
            store.theme = value
                ? 'system'
                : (isDark(context) ? 'dark' : 'light');
            store.saveSettings();
          }),
        ),
        const SectionLabel('主题氛围', caption: '背景与控件一起改变'),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 14) / 2;
            return Wrap(
              spacing: 14,
              runSpacing: 18,
              children: [
                for (final palette in studioPalettes)
                  SizedBox(
                    width: width,
                    child: Semantics(
                      excludeSemantics: true,
                      button: true,
                      selected: store.palette == palette.id,
                      label: palette.name,
                      child: GestureDetector(
                        onTap: () {
                          store.palette = palette.id;
                          store.accent = palette.primary;
                          store.saveSettings();
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: store.palette == palette.id
                                      ? accent(context)
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: PalettePreview(palette: palette),
                            ),
                            const SizedBox(height: 9),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    palette.name,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                if (store.palette == palette.id)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: accent(context),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SettingsGroupLabel('玻璃材质'),
        SettingsPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              GlassSlider(
                label: '不透明度',
                value: store.glassOpacity,
                min: .08,
                max: .7,
                onChanged: (v) {
                  store.glassOpacity = v;
                  store.refresh();
                },
                onChangeEnd: (_) => store.saveSettings(),
              ),
              const SizedBox(height: 18),
              GlassSlider(
                label: '柔化强度',
                value: store.blur / 24,
                min: 0,
                max: 1,
                onChanged: (v) {
                  store.blur = v * 24;
                  store.refresh();
                },
                onChangeEnd: (_) => store.saveSettings(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class InteractionSettings extends StatelessWidget {
  final AppStore store;
  const InteractionSettings({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    StudioScope.of(context);
    return SettingsDetail(
      title: '交互与辅助',
      children: [
        SettingsPanel(
          child: Column(
            children: [
              _toggle(context, '触感反馈', '轻触时振动', store.haptics, (v) {
                store.haptics = v;
                store.saveSettings();
              }),
              _toggle(context, '减少动态效果', '降低过渡与回弹', store.reduceMotion, (v) {
                store.reduceMotion = v;
                store.saveSettings();
              }),
              _toggle(context, '增强文字对比', '提高玻璃遮盖，保护阅读', store.highContrast, (
                v,
              ) {
                store.highContrast = v;
                store.saveSettings();
              }),
            ],
          ),
        ),
        const SettingsGroupLabel('文字大小'),
        SettingsPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '默认跟随系统，不下载或安装字体。',
                style: TextStyle(fontSize: 14, color: muted(context)),
              ),
              const SizedBox(height: 18),
              GlassSlider(
                label: '额外缩放',
                value: store.textScale - 1,
                min: -.15,
                max: .3,
                onChanged: (v) {
                  store.textScale = 1 + v;
                  store.refresh();
                },
                onChangeEnd: (_) => store.saveSettings(),
              ),
              const SizedBox(height: 10),
              GlassButton(
                '恢复系统字号',
                small: true,
                onTap: () {
                  store.textScale = 1;
                  store.saveSettings();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppearanceMode extends StatelessWidget {
  const _AppearanceMode({
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String value, label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1.15,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected
                      ? const Color(0xff4286f5)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff4666e5), Color(0xff5eb9f1)],
                  ),
                ),
                child: FractionallySizedBox(
                  widthFactor: .8,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 2; i++)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: FractionallySizedBox(
                              widthFactor: 1,
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(9),
                                  color: value == 'dark'
                                      ? const Color(0x99223367)
                                      : const Color(0x60e6f3ff),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (final width in [.94, .57])
                                      Flexible(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          child: FractionallySizedBox(
                                            widthFactor: width,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: value == 'dark'
                                                    ? const Color(0xff94b7e7)
                                                    : const Color(0xff436ab4),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const SizedBox(height: 4),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: selected ? accentInk(context) : ink(context),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget settingRow(
  BuildContext context,
  IconData icon,
  String title,
  String subtitle,
  VoidCallback onTap, {
  bool inline = false,
}) {
  final color = switch (title) {
    '生成偏好' || '个性化' => const Color(0xff7664ee),
    '使用明细' || '应用更新' => const Color(0xff199762),
    '存储管理' => const Color(0xffcf7442),
    '关于琉光' => const Color(0xff70839b),
    _ => const Color(0xff357de9),
  };
  final compact =
      MediaQuery.textScalerOf(context).scale(1) < 1.25 &&
      MediaQuery.sizeOf(context).width >= 350;
  final trailing = inline && compact;
  return Semantics(
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: ink(context),
                      ),
                    ),
                    if (!trailing && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: muted(context)),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing && subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: muted(context)),
                  ),
                ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                color: muted(context),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _toggle(
  BuildContext context,
  String title,
  String subtitle,
  bool value,
  ValueChanged<bool> onChanged,
) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: muted(context)),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(width: 12),
      GlassToggle(
        value: value,
        onChanged: onChanged,
        activeTrackColor: accentInk(context),
      ),
    ],
  ),
);

class ConnectionScreen extends StatefulWidget {
  final AppStore store;
  final StudioApi api;
  const ConnectionScreen({super.key, required this.store, required this.api});
  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final image = widget.store.imageApi.snapshot(),
      chat = widget.store.chatApi.snapshot();
  late final imageUrl = TextEditingController(text: image.baseUrl),
      imageKey = TextEditingController(text: image.key),
      imageModel = TextEditingController(text: image.model);
  late final chatUrl = TextEditingController(text: chat.baseUrl),
      chatKey = TextEditingController(text: chat.key),
      chatModel = TextEditingController(text: chat.model);
  bool imageVisible = false, chatVisible = false, saving = false;
  String? imageStatus, chatStatus;
  int tab = 0;
  Timer? autosave;
  @override
  void initState() {
    super.initState();
    for (final controller in [
      imageUrl,
      imageKey,
      imageModel,
      chatUrl,
      chatKey,
      chatModel,
    ]) {
      controller.addListener(scheduleSave);
    }
  }

  void scheduleSave() {
    autosave?.cancel();
    autosave = Timer(const Duration(milliseconds: 350), persistConnection);
  }

  Future<void> persistConnection() async {
    sync();
    widget.store.imageApi = image;
    widget.store.chatApi = chat;
    await widget.store.saveSettings(keys: true);
  }

  @override
  void dispose() {
    autosave?.cancel();
    if (autosave != null) persistConnection();
    for (final c in [
      imageUrl,
      imageKey,
      imageModel,
      chatUrl,
      chatKey,
      chatModel,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void sync() {
    image.baseUrl = imageUrl.text.trim();
    image.key = imageKey.text.trim();
    image.model = imageModel.text.trim();
    chat.baseUrl = chatUrl.text.trim();
    chat.key = chatKey.text.trim();
    chat.model = chatModel.text.trim();
  }

  Future<void> discover(bool isImage) async {
    sync();
    final config = isImage ? image : chat;
    setState(() {
      if (isImage) {
        imageStatus = '正在读取模型列表…';
      } else {
        chatStatus = '正在读取模型列表…';
      }
    });
    try {
      final models = await widget.api.discover(config);
      config.models = models;
      if (config.model.isEmpty) {
        config.model = models.firstWhere(
          (m) => isImage
              ? RegExp(
                  r'image|dall|flux|stable|sdxl|绘',
                  caseSensitive: false,
                ).hasMatch(m)
              : !RegExp(
                  r'image|dall|flux|embed|whisper|tts',
                  caseSensitive: false,
                ).hasMatch(m),
          orElse: () => models.first,
        );
        (isImage ? imageModel : chatModel).text = config.model;
        if (isImage && config.model.contains('gpt-image')) {
          config.protocol = ApiProtocol.gptImage;
        }
        if (isImage && config.model.contains('dall-e')) {
          config.protocol = ApiProtocol.dalle;
        }
      }
      if (mounted) {
        setState(() {
          if (isImage) {
            imageStatus = '已发现 ${models.length} 个模型，点击模型列表选择';
          } else {
            chatStatus = '已发现 ${models.length} 个模型，点击模型列表选择';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (isImage) {
            imageStatus = describeError(e);
          } else {
            chatStatus = describeError(e);
          }
        });
      }
    }
  }

  Future<void> save({bool detect = true}) async {
    if (saving) {
      return;
    }
    sync();
    for (final c in [image, chat]) {
      if (c.baseUrl.isNotEmpty) {
        try {
          apiUri(c.baseUrl, 'models');
        } catch (e) {
          toast(context, '$e');
          return;
        }
      }
    }
    setState(() => saving = true);
    try {
      if (detect) {
        await Future.wait([
          if (image.baseUrl.isNotEmpty && image.key.isNotEmpty) discover(true),
          if (chat.baseUrl.isNotEmpty && chat.key.isNotEmpty) discover(false),
        ]);
      }
      sync();
      widget.store.imageApi = image;
      widget.store.chatApi = chat;
      await widget.store.saveSettings(keys: true);
      if (mounted) {
        toast(context, '连接配置已加密保存');
      }
    } catch (e) {
      if (mounted) {
        toast(context, '保存失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Future<void> choose(bool isImage) async {
    final config = isImage ? image : chat;
    final picked = await glassSheet<String>(
      context,
      ModelPicker(models: config.models, current: config.model),
      scroll: false,
    );
    if (picked != null && mounted) {
      setState(() {
        config.model = picked;
        (isImage ? imageModel : chatModel).text = picked;
        if (isImage && picked.contains('gpt-image')) {
          config.protocol = ApiProtocol.gptImage;
        } else if (isImage && picked.contains('dall-e')) {
          config.protocol = ApiProtocol.dalle;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isImage = tab == 0, config = isImage ? image : chat;
    return SettingsDetail(
      title: '模型连接',
      children: [
        GlassSegments(
          labels: const ['生图模型', '对话模型', '识图模型'],
          selected: tab,
          onChanged: (v) => setState(() => tab = v),
        ),
        if (tab == 2)
          VisionSettings(store: widget.store, api: widget.api, embedded: true)
        else ...[
          const SectionLabel('API 基础地址'),
          GlassField(
            controller: isImage ? imageUrl : chatUrl,
            hint: 'https://your-provider.com/v1',
            keyboard: TextInputType.url,
          ),
          const SectionLabel('API Key'),
          GlassField(
            controller: isImage ? imageKey : chatKey,
            hint: '填入这组模型的独立 Key',
            obscure: !(isImage ? imageVisible : chatVisible),
            suffix: IconButton(
              icon: Icon(
                (isImage ? imageVisible : chatVisible)
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() {
                if (isImage) {
                  imageVisible = !imageVisible;
                } else {
                  chatVisible = !chatVisible;
                }
              }),
            ),
          ),
          SectionLabel(
            '模型 ID',
            action: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => choose(isImage),
              child: Text(
                '模型列表 (${config.models.length})',
                style: TextStyle(fontSize: 12, color: accentInk(context)),
              ),
            ),
          ),
          GlassField(
            controller: isImage ? imageModel : chatModel,
            hint: '自动检测后选择，或手动填写精确 ID',
          ),
          const SizedBox(height: 14),
          GlassButton(
            '检测全部可用模型',
            small: true,
            icon: Icons.radar_rounded,
            onTap: saving ? null : () => discover(isImage),
          ),
          if ((isImage ? imageStatus : chatStatus) != null) ...[
            const SizedBox(height: 12),
            StudioSelectable(
              (isImage ? imageStatus : chatStatus)!,
              style: TextStyle(
                fontSize: 12,
                color: muted(context),
                height: 1.8,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '读取 GET /models，完整列出服务端返回的模型。模型名称仅用于初选，列表通常不提供能力信息，请按服务商文档选择生图或对话模型。',
            style: TextStyle(fontSize: 12, height: 1.8, color: muted(context)),
          ),
          if (isImage) ...[
            const SectionLabel('图片协议'),
            Glass(
              child: RadioGroup<ApiProtocol>(
                groupValue: image.protocol,
                onChanged: (v) {
                  setState(() => image.protocol = v!);
                  scheduleSave();
                },
                child: Column(
                  children: [
                    for (final protocol in ApiProtocol.values)
                      RadioListTile<ApiProtocol>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: protocol,
                        title: Text(
                          _protocolTitle(protocol),
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          _protocolDescription(protocol),
                          style: TextStyle(
                            fontSize: 12,
                            color: muted(context),
                            height: 1.7,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          SectionLabel(
            '费用估算',
            caption: '可选 · 自定义 USD 单价',
            action: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final rates = await glassSheet<List<double>>(
                  context,
                  PricingSheet(config: config),
                );
                if (rates != null && mounted) {
                  setState(() {
                    config.inputPrice = rates[0];
                    config.outputPrice = rates[1];
                    config.imagePrice = rates[2];
                  });
                  scheduleSave();
                }
              },
              child: Text(
                '设置单价',
                style: TextStyle(fontSize: 12, color: accentInk(context)),
              ),
            ),
          ),
          Glass(
            child: Text(
              '输入 \$${config.inputPrice}/百万 Token\n输出 \$${config.outputPrice}/百万 Token\n图片 \$${config.imagePrice}/张',
              style: TextStyle(
                color: muted(context),
                fontSize: 14,
                height: 1.9,
              ),
            ),
          ),
          const SizedBox(height: 24),
          GlassButton(
            '保存并自动检测',
            primary: true,
            icon: Icons.check_rounded,
            busy: saving,
            onTap: save,
          ),
          const SizedBox(height: 12),
          GlassButton(
            '仅保存配置',
            small: true,
            onTap: saving ? null : () => save(detect: false),
          ),
          const SizedBox(height: 20),
          Text(
            '两组地址与 Key 独立存储。配置只发往你填写的接口，图片下载不会附带 Key。',
            style: TextStyle(fontSize: 12, height: 1.8, color: muted(context)),
          ),
        ],
      ],
    );
  }
}

class ModelPicker extends StatefulWidget {
  final List<String> models;
  final String current;
  const ModelPicker({super.key, required this.models, required this.current});
  @override
  State<ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<ModelPicker> {
  final input = TextEditingController();
  String query = '';
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.models
        .where((s) => s.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return SizedBox(
      height: (180.0 + list.length * 56).clamp(
        220.0,
        MediaQuery.sizeOf(context).height * .65,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '选择模型',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 15),
          GlassField(
            controller: input,
            hint: '搜索，或输入完整模型 ID',
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 12),
          if (query.trim().isNotEmpty)
            GlassButton(
              '使用「${query.trim()}」',
              small: true,
              onTap: () => Navigator.pop(context, query.trim()),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(list[i], style: const TextStyle(fontSize: 14)),
                trailing: list[i] == widget.current
                    ? Icon(Icons.check_rounded, color: accentInk(context))
                    : null,
                onTap: () => Navigator.pop(context, list[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PricingSheet extends StatefulWidget {
  final EndpointConfig config;
  const PricingSheet({super.key, required this.config});
  @override
  State<PricingSheet> createState() => _PricingSheetState();
}

class _PricingSheetState extends State<PricingSheet> {
  late final controllers = [
    widget.config.inputPrice,
    widget.config.outputPrice,
    widget.config.imagePrice,
  ].map((v) => TextEditingController(text: '$v')).toList();
  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '自定义费用估算',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      Text(
        '按服务商报价填写，0 表示不估算。两组 Token 价格和每张图片价格会相加，请按实际计费方式填写，避免重复计价。',
        style: TextStyle(fontSize: 12, height: 1.8, color: muted(context)),
      ),
      for (var i = 0; i < 3; i++) ...[
        SectionLabel(
          ['输入 / USD 每百万 Token', '输出 / USD 每百万 Token', '图片 / USD 每张'][i],
        ),
        GlassField(
          controller: controllers[i],
          hint: '0',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
      const SizedBox(height: 24),
      GlassButton(
        '应用单价',
        primary: true,
        onTap: () {
          final values = controllers
              .map((c) => double.tryParse(c.text))
              .toList();
          if (values.any((v) => v == null || !v.isFinite || v < 0)) {
            toast(context, '请输入有效的非负单价');
            return;
          }
          Navigator.pop(context, values.cast<double>());
        },
      ),
    ],
  );
}

String _protocolTitle(ApiProtocol p) => switch (p) {
  ApiProtocol.images => '标准 Images · 最大兼容',
  ApiProtocol.gptImage => 'GPT Image · 扩展参数',
  ApiProtocol.dalle => 'DALL·E · 传统图片协议',
  ApiProtocol.chatImage => '对话生图 · 多模态接口',
};
String _protocolDescription(ApiProtocol p) => switch (p) {
  ApiProtocol.images => 'images/generations 与 images/edits；格式本地转换',
  ApiProtocol.gptImage => '发送 quality、output_format、moderation、压缩参数',
  ApiProtocol.dalle => 'response_format；DALL·E 3 仅支持单张文生图',
  ApiProtocol.chatImage => 'chat/completions；支持图片 URL/base64 返回，无标准蒙版能力',
};

class AboutStudio extends StatelessWidget {
  const AboutStudio({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 20),
      Center(
        child: LauncherPreview(
          id: StudioScope.of(context).launcherIcon,
          size: 82,
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        '琉光',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(
        'V$appVersion',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: muted(context)),
      ),
      const SizedBox(height: 10),
      Text(
        '让灵感成像',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: muted(context)),
      ),
      const SizedBox(height: 32),
      Glass(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
        child: Column(
          children: [
            settingRow(
              context,
              Icons.system_update_rounded,
              '应用更新',
              '版本与更新记录',
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UpdatesScreen(store: StudioScope.of(context)),
                ),
              ),
            ),
            _line(context),
            settingRow(
              context,
              Icons.receipt_long_outlined,
              '日志详情',
              '正常与错误记录',
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
              ),
            ),
            _line(context),
            settingRow(
              context,
              Icons.shield_outlined,
              '隐私与数据',
              '本机存储与模型请求',
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsDetail(
                    title: '隐私与数据',
                    children: [PrivacyInfo()],
                  ),
                ),
              ),
            ),
            _line(context),
            settingRow(
              context,
              Icons.code_rounded,
              '开源许可',
              '感谢开源社区',
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StudioLicensesScreen()),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class PrivacyInfo extends StatelessWidget {
  const PrivacyInfo({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const InfoHero(
        icon: Icons.shield_outlined,
        title: '创作由你掌握',
        subtitle: '清楚知道每一份数据去向',
      ),
      for (final item in [
        (
          Icons.key_rounded,
          '密钥只留本机',
          'API Key 由 Android Keystore 加密保存，不写入作品、使用明细或导出文件。',
        ),
        (Icons.photo_outlined, '本地处理，无需上传', '调色、裁切、GIF、本地虚化与本机人像美化均在手机完成。'),
        (
          Icons.cloud_outlined,
          '云端请求，由你发起',
          '仅在生成、云端编辑、传奇二瞬、AI 人像美化或对话时，将所需文字和图片发送给你配置的服务。',
        ),
        (
          Icons.folder_outlined,
          '保留自己的作品',
          '作品和对话保存在应用私有目录，卸载会删除这些本机数据，请先将重要作品保存到相册。',
        ),
        (
          Icons.receipt_long_outlined,
          '统计清楚，费用透明',
          '本机费用按自定义单价估算，不等于服务端账单。应用不含广告与遥测 SDK，审核偏好不能覆盖服务政策。',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: InfoCard(icon: item.$1, title: item.$2, text: item.$3),
        ),
    ],
  );
}

class InfoHero extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const InfoHero({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent(context),
                Color.lerp(accent(context), const Color(0xffb79ae7), .6)!,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(icon, color: Colors.white, size: 34),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: muted(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class InfoCard extends StatelessWidget {
  final IconData icon;
  final String title, text;
  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });
  @override
  Widget build(BuildContext context) => Glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 22, color: accent(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        StudioSelectable(
          text,
          style: TextStyle(fontSize: 14, height: 1.8, color: muted(context)),
        ),
      ],
    ),
  );
}

class StudioLicensesScreen extends StatefulWidget {
  const StudioLicensesScreen({super.key});
  @override
  State<StudioLicensesScreen> createState() => _StudioLicensesScreenState();
}

class _StudioLicensesScreenState extends State<StudioLicensesScreen> {
  final future = LicenseRegistry.licenses.toList();
  @override
  Widget build(BuildContext context) => SettingsDetail(
    title: '开源许可',
    children: [
      const InfoHero(
        icon: Icons.code_rounded,
        title: '与开源同行',
        subtitle: '每一份贡献，都值得被看见',
      ),
      FutureBuilder<List<LicenseEntry>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final grouped = <String, List<LicenseEntry>>{};
          for (final entry in snapshot.data!) {
            for (final package in entry.packages) {
              (grouped[package] ??= []).add(entry);
            }
          }
          final names = grouped.keys.toList()..sort();
          return Column(
            children: [
              for (final name in names)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Glass(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: settingRow(
                      context,
                      Icons.inventory_2_outlined,
                      name,
                      '查看许可证',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SettingsDetail(
                            title: name,
                            children: [
                              for (final entry in grouped[name]!)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: Glass(
                                    child: StudioSelectable(
                                      entry.paragraphs
                                          .map((p) => p.text)
                                          .join('\n\n'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.8,
                                        color: muted(context),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}
