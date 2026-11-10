import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/imaging.dart';
import '../core/image_transport.dart';
import '../core/models.dart';
import '../core/materials.dart';
import '../core/store.dart';
import '../ui/glass.dart';
import 'assistant.dart';
import 'library.dart';
import 'materials.dart';

class CreateScreen extends StatefulWidget {
  final AppStore store;
  final StudioApi api;
  final VoidCallback onSettings;
  final ValueChanged<String> onEdit;
  final String? initialPrompt;
  const CreateScreen({
    super.key,
    required this.store,
    required this.api,
    required this.onSettings,
    required this.onEdit,
    this.initialPrompt,
  });
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  String? selectedMaterial;
  late final TextEditingController prompt = TextEditingController(
    text: widget.store.prefs.getString('draft') ?? '',
  );
  late GenerationOptions options = GenerationOptions.fromJson(
    widget.store.defaults.toJson(),
  );
  int mode = 0;
  late String defaultsSignature = jsonEncode(widget.store.defaults.toJson());
  String? base;
  final List<String> references = [];
  bool busy = false, polishing = false;
  CancelToken? token;
  Timer? timer;
  int seconds = 0;
  String taskStage = '正在准备请求';
  String? error;
  List<Artwork> results = [];
  @override
  void initState() {
    super.initState();
    prompt.addListener(_draft);
  }

  void _draft() {
    widget.store.prefs.setString('draft', prompt.text);
  }

  @override
  void didUpdateWidget(covariant CreateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = jsonEncode(widget.store.defaults.toJson());
    if (!busy && signature != defaultsSignature) {
      options = GenerationOptions.fromJson(widget.store.defaults.toJson());
      defaultsSignature = signature;
    }
    if (widget.initialPrompt != oldWidget.initialPrompt &&
        widget.initialPrompt != null) {
      prompt.text = widget.initialPrompt!;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    token?.cancel();
    prompt.dispose();
    super.dispose();
  }

  Future<void> pickBase() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file != null && mounted) {
        setState(() {
          base = file.path;
          mode = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        toast(context, '无法打开图片：$e');
      }
    }
  }

  Future<void> pickReferences() async {
    try {
      final files = await ImagePicker().pickMultiImage(limit: 8);
      if (mounted) {
        setState(() {
          references.addAll(files.map((f) => f.path));
          if (references.length > 8) {
            references.removeRange(8, references.length);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        toast(context, '无法读取参考图：$e');
      }
    }
  }

  Future<void> polish() async {
    if (busy || polishing) return;
    if (prompt.text.trim().isEmpty) {
      toast(context, '先写下你的创意，再让助手润色');
      return;
    }
    if (!widget.store.chatApi.ready) {
      widget.onSettings();
      return;
    }
    final original = prompt.text;
    setState(() => polishing = true);
    try {
      final improved = await widget.api.chat([
        ChatMessage('user', original),
      ], polish: true);
      if (!mounted) {
        return;
      }
      final apply = await glassSheet<bool>(
        context,
        Builder(
          builder: (ctx) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '润色预览',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                '请确认主体与创作意图保持一致后应用。',
                style: TextStyle(color: muted(ctx), fontSize: 14),
              ),
              const SectionLabel('原提示词'),
              StudioSelectable(
                original,
                style: TextStyle(color: muted(ctx), height: 1.7),
              ),
              const SectionLabel('润色结果'),
              Glass(
                child: StudioSelectable(
                  improved,
                  style: const TextStyle(height: 1.8),
                ),
              ),
              const SizedBox(height: 22),
              GlassButton(
                '应用润色',
                primary: true,
                icon: Icons.check_rounded,
                onTap: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      );
      if (apply == true && mounted) {
        prompt.text = improved;
      }
    } catch (e) {
      if (mounted) {
        toast(context, describeError(e));
      }
    } finally {
      if (mounted) {
        setState(() => polishing = false);
      }
    }
  }

  Future<void> generate() async {
    if (busy || polishing) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!widget.store.imageApi.ready) {
      widget.onSettings();
      toast(context, '先连接你的生图模型');
      return;
    }
    if (mode == 1 && base == null) {
      toast(context, '请添加一张底图');
      return;
    }
    if (prompt.text.trim().isEmpty) {
      toast(context, '请描述想要的画面');
      return;
    }
    final original = prompt.text, model = widget.store.imageApi.model;
    final settings = GenerationOptions.fromJson(options.toJson());
    token = CancelToken();
    setState(() {
      busy = true;
      error = null;
      seconds = 0;
      results = [];
    });
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => seconds++);
      }
    });
    try {
      final reply = await widget.api.generate(
        prompt: withMaterial(original, selectedMaterial),
        options: settings,
        inputs: [if (mode == 1 && base != null) base!, ...references],
        cancelToken: token,
        operation: mode == 1 || references.isNotEmpty ? '图生图' : '文生图',
        onStage: (stage) {
          if (mounted && taskStage != stage) setState(() => taskStage = stage);
        },
      );
      final saved = <Artwork>[];
      for (final bytes in reply.images) {
        saved.add(
          await saveArtwork(
            widget.store,
            bytes,
            prompt: original,
            model: model,
            kind: mode == 1 ? '图生图' : '文生图',
            format: settings.format == 'gif' ? null : settings.format,
            quality: settings.compression,
          ),
        );
      }
      if (settings.format == 'gif') {
        final gif = await compute(encodeAnimation, {
          'frames': reply.images,
          'duration': 500,
          'colors': settings.compression < 50 ? 128 : 256,
        });
        saved.insert(
          0,
          await saveArtwork(
            widget.store,
            gif,
            prompt: original,
            model: model,
            kind: 'GIF',
          ),
        );
      }
      if (mounted) {
        setState(() => results = saved);
        final mismatch = saved.where(
          (art) => !matchesRequestedAspect(
            art.width,
            art.height,
            settings.width,
            settings.height,
          ),
        );
        if (mismatch.isNotEmpty) {
          setState(
            () => error =
                '接口返回的画面比例与所选 ${settings.aspectLabel} 不一致（实际 ${mismatch.first.width}×${mismatch.first.height}）。已保存原始结果，未裁切或拉伸；请检查服务商对此模型的尺寸支持。',
          );
        } else {
          toast(context, '已完成并保存 ${saved.length} 个作品');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = describeError(e));
      }
    } finally {
      timer?.cancel();
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 125),
        children: [
          const PageHeader(title: '创作'),
          TaskStatusCard(
            title: '正在创作',
            stage: taskStage,
            seconds: seconds,
            onCancel: token?.isCancelled == true
                ? null
                : () {
                    token?.cancel();
                    setState(() => taskStage = '正在取消等待');
                  },
          ),
          const SizedBox(height: 18),
          Text(
            '${options.resolution} · ${options.aspectLabel}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted(context)),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 5, 24, 28),
      children: [
        PageHeader(
          title: '创作',
          action: GlassIcon(
            Icons.forum_outlined,
            tooltip: '创作助手',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssistantScreen(
                  store: widget.store,
                  api: widget.api,
                  onUsePrompt: (value) {
                    prompt.text = value;
                  },
                ),
              ),
            ),
          ),
        ),

        GlassSegments(
          labels: const ['文生图', '图生图'],
          selected: mode,
          onChanged: (v) {
            if (!busy) {
              setState(() => mode = v);
            }
          },
        ),
        SectionLabel(
          '提示词',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassIcon(
                Icons.backspace_outlined,
                tooltip: '清空提示词',
                onTap: busy ? null : () => prompt.clear(),
              ),
              const SizedBox(width: 8),
              GlassButton(
                polishing ? '润色中…' : '智能润色',
                small: true,
                icon: Icons.auto_awesome_outlined,
                onTap: polishing || busy ? null : polish,
              ),
            ],
          ),
        ),
        IgnorePointer(
          ignoring: busy,
          child: GlassField(
            controller: prompt,
            hint: '描述主体、场景与光线…',
            minLines: 4,
            maxLines: 9,
          ),
        ),
        const SectionLabel('材质'),
        MaterialSelection(
          selected: selectedMaterial,
          onChanged: (id) => setState(() => selectedMaterial = id),
        ),
        if (mode == 1) ...[
          const SectionLabel('底图', caption: '原图会单独保留'),
          if (base == null)
            GlassButton(
              '添加底图',
              icon: Icons.add_photo_alternate_outlined,
              onTap: busy ? null : pickBase,
            )
          else
            _inputTile(
              base!,
              '底图',
              () => setState(() => base = null),
              large: true,
            ),
        ],
        SectionLabel(
          '参考图',
          caption: '${references.length} / 8 · 可添加多张',
          action: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: busy ? null : pickReferences,
            child: Icon(
              Icons.add_circle_outline_rounded,
              size: 21,
              color: accentInk(context),
            ),
          ),
        ),
        if (references.isEmpty)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: busy ? null : pickReferences,
            child: Glass(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    color: muted(context),
                    size: 23,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '添加人物、构图或风格参考',
                      style: TextStyle(color: muted(context), fontSize: 14),
                    ),
                  ),
                  Icon(Icons.add_rounded, color: accentInk(context), size: 20),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 99,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: references.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(
                width: 100,
                child: _inputTile(
                  references[i],
                  '${i + 1}',
                  () => setState(() => references.removeAt(i)),
                ),
              ),
            ),
          ),
        const SectionLabel('生成规格'),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy
              ? null
              : () async {
                  final result = await glassSheet<GenerationOptions>(
                    context,
                    GenerationSettings(initial: options),
                  );
                  if (result != null && mounted) {
                    setState(() => options = result);
                  }
                },
          child: Glass(
            child: Row(
              children: [
                Glass(
                  radius: 16,
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.aspect_ratio_rounded,
                    color: accentInk(context),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${options.resolution} · ${options.aspectLabel}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${_quality(options.quality)}  /  ${options.format.toUpperCase()}  /  ${options.count} 张',
                        style: TextStyle(color: muted(context), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: muted(context)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: widget.store.imageApi.ready
                    ? accentInk(context)
                    : muted(context),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.store.imageApi.model.isEmpty
                    ? '尚未连接生图模型'
                    : widget.store.imageApi.model,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: muted(context)),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onSettings,
              child: Text(
                '切换模型',
                style: TextStyle(fontSize: 12, color: accentInk(context)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (busy)
          TaskStatusCard(
            title: '正在创作',
            stage: taskStage,
            seconds: seconds,
            onCancel: token?.isCancelled == true
                ? null
                : () {
                    token?.cancel();
                    setState(() => taskStage = '正在取消等待');
                  },
          )
        else
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              '开始创作',
              primary: true,
              icon: Icons.auto_awesome_rounded,
              onTap: generate,
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  results.isEmpty ? '这次没有完成' : '尺寸提示',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                StudioSelectable(
                  error!,
                  style: TextStyle(
                    color: muted(context),
                    fontSize: 14,
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (results.isNotEmpty) ...[
          const SectionLabel('生成结果', caption: '已保存到作品'),
          ...results.map(
            (art) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    openArtwork(context, widget.store, art, widget.onEdit),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.file(File(art.path), fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _inputTile(
    String path,
    String label,
    VoidCallback remove, {
    bool large = false,
  }) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: SizedBox(
      height: large ? 180 : 99,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          ),
          Positioned(
            top: 7,
            right: 7,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: busy ? null : remove,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 7,
            left: 9,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _quality(String value) => switch (value) {
  'high' => '精细质量',
  'medium' => '标准质量',
  'low' => '快速质量',
  _ => '自动质量',
};

class GenerationSettings extends StatefulWidget {
  final GenerationOptions initial;
  const GenerationSettings({super.key, required this.initial});
  @override
  State<GenerationSettings> createState() => _GenerationSettingsState();
}

class _GenerationSettingsState extends State<GenerationSettings> {
  late GenerationOptions o = GenerationOptions.fromJson(
    widget.initial.toJson(),
  );
  static const ratios = [
    (1, 1),
    (3, 4),
    (4, 3),
    (2, 3),
    (3, 2),
    (9, 16),
    (16, 9),
  ];
  int resolution = 1024, ratioIndex = 0;
  @override
  void initState() {
    super.initState();
    final longest = o.width > o.height ? o.width : o.height;
    resolution = longest >= 3072
        ? 4096
        : longest >= 1536
        ? 2048
        : 1024;
    var distance = double.infinity;
    for (var i = 0; i < ratios.length; i++) {
      final d = (o.width / o.height - ratios[i].$1 / ratios[i].$2).abs();
      if (d < distance) {
        distance = d;
        ratioIndex = i;
      }
    }
  }

  void applySize() {
    final r = ratios[ratioIndex];
    o.width = r.$1 >= r.$2
        ? resolution
        : (resolution * r.$1 / r.$2 / 16).round() * 16;
    o.height = r.$2 >= r.$1
        ? resolution
        : (resolution * r.$2 / r.$1 / 16).round() * 16;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '生成规格',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      const SectionLabel('画面比例'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < ratios.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => ratioIndex = i),
              child: Glass(
                padding: const EdgeInsets.all(12),
                radius: 18,
                tint: ratioIndex == i ? accent(context) : null,
                opacity: ratioIndex == i ? .55 : null,
                child: SizedBox(
                  width: 48,
                  height: 58,
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: ratios[i].$1 / ratios[i].$2,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: accentInk(context),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${ratios[i].$1}:${ratios[i].$2}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      const SectionLabel('分辨率'),
      GlassSegments(
        labels: const ['1K', '2K', '4K'],
        selected: [1024, 2048, 4096].indexOf(resolution),
        onChanged: (i) => setState(() => resolution = [1024, 2048, 4096][i]),
      ),
      const SectionLabel('生成质量'),
      GlassSegments(
        labels: const ['快速', '标准', '精细', '自动'],
        selected: [
          'low',
          'medium',
          'high',
          'auto',
        ].indexOf(o.quality).clamp(0, 3),
        onChanged: (i) =>
            setState(() => o.quality = ['low', 'medium', 'high', 'auto'][i]),
      ),
      const SectionLabel('输出格式'),
      GlassSegments(
        labels: const ['PNG', 'JPEG', 'WebP', 'GIF'],
        selected: ['png', 'jpeg', 'webp', 'gif'].indexOf(o.format).clamp(0, 3),
        onChanged: (i) =>
            setState(() => o.format = ['png', 'jpeg', 'webp', 'gif'][i]),
      ),
      const SizedBox(height: 13),
      Text(
        o.format == 'gif'
            ? 'GIF 由返回图片在本地合成，默认每帧 0.5 秒；仅一张图片时为静态 GIF。可在作品页用多张图片制作动画。'
            : o.format == 'png'
            ? 'PNG 为无损格式，压缩质量不改变画质。'
            : '编码质量越低，文件通常越小。',
        style: TextStyle(fontSize: 12, color: muted(context), height: 1.7),
      ),
      if (o.format != 'png') ...[
        const SizedBox(height: 16),
        GlassSlider(
          label: o.format == 'gif' ? 'GIF 调色精度' : '压缩质量',
          value: o.compression / 100,
          min: .1,
          max: 1,
          onChanged: (v) => setState(() => o.compression = (v * 100).round()),
        ),
      ],
      const SectionLabel('数量'),
      Row(
        children: [
          GlassIcon(
            Icons.remove_rounded,
            tooltip: '减少数量',
            onTap: () => setState(() => o.count = (o.count - 1).clamp(1, 10)),
          ),
          Expanded(
            child: Text(
              '${o.count} 张',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          GlassIcon(
            Icons.add_rounded,
            tooltip: '增加数量',
            onTap: () => setState(() => o.count = (o.count + 1).clamp(1, 10)),
          ),
        ],
      ),
      const SectionLabel('审核偏好'),
      GlassSegments(
        labels: const ['严格', '自动', '宽松'],
        selected: ['strict', 'auto', 'low'].indexOf(o.moderation).clamp(0, 2),
        onChanged: (i) =>
            setState(() => o.moderation = ['strict', 'auto', 'low'][i]),
      ),
      const SizedBox(height: 12),
      Text(
        '偏好会独立附加到原提示词，支持时同时发送 moderation 参数；实际审核、尺寸及质量范围由模型服务决定。标准 Images 协议仅发送通用参数，输出格式在本地转换。',
        style: TextStyle(fontSize: 12, color: muted(context), height: 1.8),
      ),
      const SizedBox(height: 24),
      GlassButton(
        '应用规格',
        primary: true,
        onTap: () {
          applySize();
          Navigator.pop(context, o);
        },
      ),
    ],
  );
}
