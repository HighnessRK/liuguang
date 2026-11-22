import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/imaging.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/updates.dart';
import '../ui/glass.dart';
import 'custom_sticker.dart';

const _fishAsset = 'assets/deepseek/fish_reference.jpg';
const _fish = StickerProfile(
  id: 'fish',
  name: '大肥鱼娘',
  description: '保持蓝发、女仆装、鱼尾和统一角色设计。',
  references: [],
);

GenerationOptions stickerOptions(bool animated) => animated
    ? GenerationOptions(
        width: 512,
        height: 512,
        format: 'gif',
        advanced: {'frame_count': 8, 'frame_duration_ms': 150},
      )
    : GenerationOptions(width: 4096, height: 4096, format: 'jpeg');

class DeepSeekStickerScreen extends StatefulWidget {
  final AppStore store;
  final StudioApi api;
  const DeepSeekStickerScreen({
    super.key,
    required this.store,
    required this.api,
  });
  @override
  State<DeepSeekStickerScreen> createState() => _DeepSeekStickerScreenState();
}

class _DeepSeekStickerScreenState extends State<DeepSeekStickerScreen> {
  final text = TextEditingController();
  bool animated = false, busy = false;
  double? progress;
  final elapsed = Stopwatch();
  Timer? timer;
  CancelToken? token;
  String stage = '等待生成';
  late StickerProfile profile;
  @override
  void initState() {
    super.initState();
    final id = widget.store.prefs.getString('last_sticker_profile');
    profile =
        readStickerProfiles(widget.store)
            .where((p) => p.id == id)
            .firstOrNull ??
        _fish;
  }

  @override
  void dispose() {
    token?.cancel();
    timer?.cancel();
    text.dispose();
    super.dispose();
  }

  Future<void> editCharacter([StickerProfile? existing]) async {
    final edited = await Navigator.push<StickerProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => StickerCharacterCreatorScreen(
          store: widget.store,
          api: widget.api,
          profile: existing,
        ),
      ),
    );
    if (mounted && edited != null) await selectProfile(edited);
  }

  Future<void> selectProfile(StickerProfile value) async {
    setState(() => profile = value);
    await widget.store.prefs.setString('last_sticker_profile', value.id);
    await AppLog.record('sticker_character_selected');
  }

  Future<void> manageCharacters() async {
    final profiles = [_fish, ...readStickerProfiles(widget.store)];
    final choice = await glassSheet<(String, StickerProfile)>(
      context,
      Builder(
        builder: (sheetContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('表情角色管理'),
            for (final item in profiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Glass(
                  padding: const EdgeInsets.all(10),
                  blur: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.id == _fish.id
                              ? 'DeepSeek 大肥鱼娘 · 内置'
                              : item.name,
                        ),
                      ),
                      GlassIcon(
                        item.id == profile.id
                            ? Icons.check_circle_rounded
                            : Icons.arrow_forward_rounded,
                        tooltip: '选用${item.name}',
                        onTap: () =>
                            Navigator.pop(sheetContext, ('select', item)),
                      ),
                      if (item.id != _fish.id) ...[
                        const SizedBox(width: 8),
                        GlassIcon(
                          Icons.edit_outlined,
                          tooltip: '编辑${item.name}',
                          onTap: () =>
                              Navigator.pop(sheetContext, ('edit', item)),
                        ),
                        const SizedBox(width: 8),
                        GlassIcon(
                          Icons.delete_outline_rounded,
                          tooltip: '删除${item.name}',
                          onTap: () =>
                              Navigator.pop(sheetContext, ('delete', item)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final (action, item) = choice;
    switch (action) {
      case 'select':
        await selectProfile(item);
      case 'edit':
        await editCharacter(item);
      case 'delete':
        if (!await confirm(context, '删除「${item.name}」？', '已生成的表情包仍保存在作品中。'))
          return;
        final remaining = readStickerProfiles(widget.store)
          ..removeWhere((p) => p.id == item.id);
        await widget.store.prefs.setStringList(
          'sticker_profiles',
          remaining.map((p) => jsonEncode(p.toJson())).toList(),
        );
        if (widget.store.prefs.getString('last_sticker_profile') == item.id) {
          await widget.store.prefs.remove('last_sticker_profile');
        }
        if (mounted && profile.id == item.id) await selectProfile(_fish);
        await AppLog.record('sticker_character_deleted');
    }
  }

  Future<List<String>> referencePaths() async {
    if (profile.id != _fish.id) {
      if (profile.references.isEmpty ||
          profile.references.any((path) => !File(path).existsSync())) {
        throw StudioException('角色参考图已失效，请在角色管理中重新添加三视图');
      }
      return profile.references;
    }
    final data = await rootBundle.load(_fishAsset);
    final dir = await safeTemporaryDirectory();
    return [
      (await File('${dir.path}/deepseek-fish-reference.jpg').writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      )).path,
    ];
  }

  Future<void> generate() async {
    if (busy) return;
    final caption = text.text.trim();
    if (caption.isEmpty) {
      toast(context, '请先填写表情文本');
      return;
    }
    final config = widget.store.imageApi.snapshot();
    if (!config.ready || !widget.store.chatApi.ready) {
      toast(context, '请先配置生图和对话模型');
      return;
    }
    if (animated &&
        (!supportsNativeGif(config.model) ||
            config.protocol != ApiProtocol.gptImage)) {
      toast(context, '动图需要支持原生 GIF 的模型和 GPT Image 图片协议');
      return;
    }
    final cancel = token = CancelToken();
    final options = stickerOptions(animated);
    final kind = '${profile.name}${animated ? '动图' : ''}表情包';
    setState(() {
      busy = true;
      progress = null;
      stage = '正在理解表情文本';
    });
    elapsed
      ..reset()
      ..start();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    try {
      await beginProcessing();
      final references = await referencePaths();
      final brief = await widget.api.chat([
        ChatMessage(
          'user',
          '设计表情包画面指令，明确动作、道具、表情、构图和文字位置。只输出生图提示词。\n角色设定：${profile.description}\n表情文字：$caption',
        ),
      ], cancelToken: cancel);
      if (!mounted || cancel.isCancelled) return;
      final reply = await widget.api.generate(
        prompt:
            '$brief\n角色设定：${profile.description}\n画面文字：$caption\n'
            '$stickerProps。smooth motion, consistent character。保持帧间一致性，统一角色外形、服装、配色、构图和文字位置。画面铺满画布，去除白边。',
        options: options,
        inputs: references,
        cancelToken: cancel,
        operation: kind,
        onStage: (value) {
          if (mounted)
            setState(() {
              stage = value;
              progress = stageProgress(value) ?? progress;
            });
        },
      );
      if (!mounted || cancel.isCancelled) return;
      setState(() {
        stage = '正在校验并保存';
        progress = null;
      });
      final bytes = reply.images.first;
      if (animated) await compute(validateStickerGif, bytes);
      final artwork = await saveArtwork(
        widget.store,
        bytes,
        prompt: caption,
        model: config.model,
        kind: kind,
        format: options.format,
        parameters: options.toJson(),
      );
      await widget.store.prefs.setString('last_sticker_profile', profile.id);
      if (mounted) Navigator.pop(context, artwork);
    } catch (e) {
      if (mounted) toast(context, describeError(e));
    } finally {
      elapsed.stop();
      timer?.cancel();
      await endProcessing();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = profile.id == _fish.id
        ? <ImageProvider>[const AssetImage(_fishAsset)]
        : profile.references.map((path) => FileImage(File(path))).toList();
    return Scaffold(
      body: StudioBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
            children: [
              PageHeader(
                title: profile.id == _fish.id ? 'DeepSeek 表情包' : '表情包',
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassIcon(
                      Icons.swap_horiz_rounded,
                      tooltip: '表情角色管理',
                      onTap: busy ? null : manageCharacters,
                    ),
                    const SizedBox(width: 8),
                    GlassIcon(
                      Icons.person_add_alt_1_rounded,
                      tooltip: '创建表情角色',
                      onTap: busy ? null : editCharacter,
                    ),
                    const SizedBox(width: 8),
                    GlassIcon(
                      Icons.arrow_back_rounded,
                      tooltip: '返回',
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Glass(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${profile.name} · 固定角色参考',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (images.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 128,
                        child: Row(
                          children: [
                            for (var i = 0; i < images.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: ZoomableImage(
                                    image: images[i],
                                    child: Image(
                                      image: images[i],
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) => const Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SectionLabel('表情文本'),
              GlassField(
                controller: text,
                readOnly: busy,
                hint: '例如：今天也要元气满满',
                minLines: 3,
                maxLines: 5,
              ),
              const SectionLabel('生成类型'),
              GlassSegments(
                labels: const ['静态 · 4K JPEG', '动图 · 512 GIF'],
                selected: animated ? 1 : 0,
                onChanged: (i) {
                  if (!busy) setState(() => animated = i == 1);
                },
              ),
              if (animated) ...[
                const SizedBox(height: 12),
                Text(
                  '512 × 512 · 8 帧 · 每帧 150 ms',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted(context)),
                ),
              ],
              const SizedBox(height: 20),
              if (busy)
                TaskStatusCard(
                  title: animated ? '正在生成动图' : '正在生成表情包',
                  stage: stage,
                  seconds: elapsed.elapsed.inSeconds,
                  progress: progress,
                  onCancel: () => token?.cancel(),
                )
              else
                GlassButton(
                  '生成表情包',
                  primary: true,
                  icon: Icons.auto_awesome_rounded,
                  onTap: generate,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
