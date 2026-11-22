import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
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
import 'deepseek.dart';

class CreateScreen extends StatefulWidget {
  final AppStore store;
  final StudioApi api;
  final VoidCallback onSettings;
  final ValueChanged<Artwork>? onOpenLibrary;
  final ValueChanged<String> onEdit;
  final String? initialPrompt;
  const CreateScreen({
    super.key,
    required this.store,
    required this.api,
    required this.onSettings,
    required this.onEdit,
    this.initialPrompt,
    this.onOpenLibrary,
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
  bool professional = false;
  final professionalKey = GlobalKey<_ProfessionalControlsState>();
  final negative = TextEditingController();
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
  String polishText = '';
  List<Artwork> results = [];
  @override
  void initState() {
    super.initState();
    prompt.addListener(_draft);
    professional = widget.store.prefs.getBool('professional') ?? false;
    selectedMaterial = widget.store.prefs.getString('selected_material');
    mode = widget.store.prefs.getInt('creation_mode') ?? 0;
    negative.text = widget.store.prefs.getString('negative') ?? '';
    final savedBase = widget.store.prefs.getString('creation_base');
    if (savedBase != null && File(savedBase).existsSync()) base = savedBase;
    references.addAll(
      (widget.store.prefs.getStringList('creation_references') ?? [])
          .where((p) => File(p).existsSync())
          .take(8),
    );
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    final prefs = widget.store.prefs;
    prefs.setStringList('creation_references', references);
    if (base == null) {
      prefs.remove('creation_base');
    } else {
      prefs.setString('creation_base', base!);
    }
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
    negative.dispose();
    super.dispose();
  }

  Future<List<String>> chooseImages({required bool multiple}) async {
    final source = await glassSheet<String>(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            multiple ? '添加参考图' : '选择底图',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          GlassButton(
            '从相册选择',
            icon: Icons.photo_library_outlined,
            onTap: () => Navigator.pop(context, 'album'),
          ),
          const SizedBox(height: 12),
          GlassButton(
            '从作品选择',
            icon: Icons.collections_outlined,
            onTap: () => Navigator.pop(context, 'works'),
          ),
        ],
      ),
    );
    if (!mounted || source == null) return [];
    if (source == 'album') {
      if (multiple) {
        return (await ImagePicker().pickMultiImage(limit: 8))
            .map((f) => f.path)
            .toList();
      }
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      return file == null ? [] : [file.path];
    }
    final chosen = <String>{};
    final paths = await glassSheet<List<String>>(
      context,
      StatefulBuilder(
        builder: (ctx, update) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '选择作品',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (widget.store.visibleArtworks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('还没有作品，可先从相册添加'),
              ),
            for (final art in widget.store.visibleArtworks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Glass(
                  radius: 18,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(art.path),
                        width: 48,
                        height: 48,
                        cacheWidth: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.image_outlined),
                      ),
                    ),
                    title: Text(art.kind, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      '${art.width} × ${art.height}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Icon(
                      chosen.contains(art.path)
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: chosen.contains(art.path)
                          ? accent(context)
                          : muted(context),
                    ),
                    onTap: () {
                      if (!multiple) {
                        Navigator.pop(ctx, [art.path]);
                        return;
                      }
                      update(() {
                        if (!chosen.remove(art.path) &&
                            chosen.length < 8 - references.length) {
                          chosen.add(art.path);
                        }
                      });
                    },
                  ),
                ),
              ),
            if (multiple) ...[
              const SizedBox(height: 12),
              GlassButton(
                '添加选中图片（${chosen.length}）',
                primary: true,
                onTap: chosen.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, chosen.toList()),
              ),
            ],
          ],
        ),
      ),
    );
    return paths ?? [];
  }

  Future<void> pickBase() async {
    try {
      final paths = await chooseImages(multiple: false);
      if (paths.isNotEmpty && mounted) {
        final dims = await compute(
          imageDimensions,
          await File(paths.first).readAsBytes(),
        );
        final fitted = matchedPhotoOptions(
          dims['width']!,
          dims['height']!,
          edge: widget.store.defaults.width > widget.store.defaults.height
              ? widget.store.defaults.width
              : widget.store.defaults.height,
        );
        setState(() {
          base = paths.first;
          mode = 1;
          options.width = fitted.width;
          options.height = fitted.height;
        });
        widget.store.prefs.setInt('creation_mode', 1);
      }
    } catch (e) {
      if (mounted) toast(context, '无法打开图片：$e');
    }
  }

  Future<void> pickReferences() async {
    if (references.length >= 8) {
      toast(context, '最多添加 8 张参考图');
      return;
    }
    try {
      final paths = await chooseImages(multiple: true);
      if (mounted) {
        setState(() {
          references.addAll(paths.where((p) => !references.contains(p)));
          if (references.length > 8) {
            references.removeRange(8, references.length);
          }
        });
      }
    } catch (e) {
      if (mounted) toast(context, '无法读取参考图：$e');
    }
  }

  Future<void> polish() async {
    if (busy || polishing) return;
    if (prompt.text.trim().isEmpty && base == null && references.isEmpty) {
      toast(context, '请先输入提示词或添加底图 / 参考图');
      return;
    }
    if (!widget.store.chatApi.ready) {
      widget.onSettings();
      return;
    }
    final original = prompt.text.trim();
    final imagePaths = [if (base != null) base!, ...references];
    setState(() {
      polishing = true;
      polishText = '';
    });
    try {
      final visual = imagePaths.isEmpty
          ? ''
          : await widget.api.imageBrief(
              imagePaths,
              '为提示词润色提供画面理解与推荐优化方向',
              cancelToken: token,
            );
      final improved = await widget.api.chat(
        [
          ChatMessage(
            'user',
            [
              if (original.isNotEmpty) '用户提示词：$original',
              if (visual.isNotEmpty) '底图 / 参考图理解：$visual',
              '请综合以上内容输出可直接用于生图的提示词。',
            ].join('\n\n'),
          ),
        ],
        polish: true,
        onText: (value) {
          if (mounted) setState(() => polishText = value);
        },
      );
      if (!mounted) {
        return;
      }
      setState(() => polishing = false);
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
    if (professional && professionalKey.currentState?.error != null) {
      toast(context, professionalKey.currentState!.error!);
      return;
    }
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
    final animationInput = mode == 1
        ? base
        : (references.isEmpty ? null : references.first);
    if (prompt.text.trim().isEmpty &&
        !(options.format == 'gif' && animationInput != null)) {
      toast(context, '请描述想要的画面');
      return;
    }
    final original = prompt.text, model = widget.store.imageApi.model;
    final settings = GenerationOptions.fromJson(options.toJson());
    if (!professional) settings.advanced.clear();
    token = CancelToken();
    setState(() {
      busy = true;
      error = null;
      taskStage = '正在准备请求';
      seconds = 0;
      results = [];
    });
    final elapsed = Stopwatch()..start();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => seconds = elapsed.elapsed.inSeconds);
      }
    });
    try {
      await beginProcessing();
      var requestPrompt = original;
      if (professional && negative.text.trim().isNotEmpty) {
        requestPrompt += '\n避免：${negative.text.trim()}';
      }
      if (settings.format == 'gif' && !supportsNativeGif(model)) {
        throw StudioException('当前模型暂不支持 GIF');
      }
      final gifInput = animationInput;
      if (settings.format == 'gif' && gifInput != null) {
        setState(() => taskStage = '正在识图并设计动态提示词');
        final description = await widget.api.describeImage(
          gifInput,
          goal: 'gif',
          cancelToken: token,
        );
        final dimensions = await compute(
          imageDimensions,
          await File(gifInput).readAsBytes(),
        );
        settings.width = dimensions['width']!;
        settings.height = dimensions['height']!;
        requestPrompt =
            '$requestPrompt\n\n动态图像建议（以用户要求为优先）：$description\n请基于原图设计自然连贯的动态变化，保留主体身份、构图与背景；请直接输出原生 GIF 动画，保持上传图片的原尺寸与画面比例，首尾尽可能连续。';
      }
      final reply = await widget.api.generate(
        prompt: withMaterial(requestPrompt, selectedMaterial),
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
        if (settings.format == 'gif' && imageExtension(bytes) != 'gif') {
          throw StudioException('模型未返回原生 GIF，已停止，未用静态图冒充动图');
        }
        saved.add(
          await saveArtwork(
            widget.store,
            bytes,
            prompt: settings.format == 'gif' ? requestPrompt.trim() : original,
            model: model,
            kind: settings.format == 'gif'
                ? 'GIF'
                : mode == 1
                ? '图生图'
                : '文生图',
            format: settings.format == 'gif' ? null : settings.format,
            quality: settings.compression,
            parameters: {
              ...settings.toJson(),
              'references': references.length,
              if (selectedMaterial != null) 'material': selectedMaterial,
              'professional': professional,
            },
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
      await endProcessing();
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
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          28 + StudioTabInset.of(context),
        ),
        children: [
          const PageHeader(title: '创作'),
          TaskStatusCard(
            title: options.format == 'gif'
                ? 'GIF 生成ing'
                : mode == 1
                ? '图生图ing'
                : '文生图ing',
            stage: taskStage,
            progress: stageProgress(taskStage),
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
            options.format == 'gif' && (base != null || references.isNotEmpty)
                ? 'GIF · 原图尺寸'
                : '${options.resolution} · ${options.aspectLabel}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted(context)),
          ),
        ],
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 5, 24, 28 + StudioTabInset.of(context)),
      children: [
        PageHeader(
          title: '创作',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassIcon(
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
            ],
          ),
        ),

        GlassSegments(
          labels: const ['文生图', '图生图', '表情包'],
          selected: mode.clamp(0, 2),
          onChanged: (v) async {
            if (busy) return;
            if (v == 2) {
              final saved = await Navigator.push<Artwork>(
                context,
                MaterialPageRoute(
                  builder: (_) => DeepSeekStickerScreen(
                    store: widget.store,
                    api: widget.api,
                  ),
                ),
              );
              if (mounted && saved != null) widget.onOpenLibrary?.call(saved);
              return;
            }
            setState(() => mode = v);
            widget.store.prefs.setInt('creation_mode', v);
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Text('专业模式', style: TextStyle(fontSize: 14))),
            GlassToggle(
              value: professional,
              onChanged: (v) {
                setState(() => professional = v);
                widget.store.prefs.setBool('professional', v);
              },
            ),
          ],
        ),
        if (professional) const SizedBox(height: 12),
        if (professional)
          GlassField(
            controller: negative,
            hint: '负面约束：不希望出现的内容',
            onChanged: (v) => widget.store.prefs.setString('negative', v),
          ),
        if (professional) ...[
          const SizedBox(height: 16),
          ProfessionalControls(
            key: professionalKey,
            options: options,
            onChanged: () {
              widget.store.defaults = GenerationOptions.fromJson(
                options.toJson(),
              );
              widget.store.saveSettings();
            },
          ),
        ],
        const SizedBox(height: 4),
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
              if (polishing)
                const AuroraBusyButton()
              else
                GlassButton(
                  '智能润色',
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
          onChanged: (id) {
            setState(() => selectedMaterial = id);
            if (id == null) {
              widget.store.prefs.remove('selected_material');
            } else {
              widget.store.prefs.setString('selected_material', id);
            }
          },
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
        if (polishing && polishText.isNotEmpty) Glass(child: Text(polishText)),
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
                  if (mounted) {
                    setState(() {
                      if (result != null) options = result;
                    });
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
                        options.format == 'gif' &&
                                (base != null || references.isNotEmpty)
                            ? 'GIF · 原图尺寸'
                            : '${options.resolution} · ${options.aspectLabel}',
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
              onTap: busy
                  ? null
                  : () async {
                      final chosen = await glassSheet<String>(
                        context,
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '切换生图模型',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            for (final id in widget.store.imageApi.models)
                              ListTile(
                                title: Text(id),
                                trailing: id == widget.store.imageApi.model
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: accent(context),
                                      )
                                    : null,
                                onTap: () => Navigator.pop(context, id),
                              ),
                          ],
                        ),
                      );
                      if (chosen != null) {
                        widget.store.imageApi.model = chosen;
                        await widget.store.saveSettings(keys: true);
                        if (mounted) setState(() {});
                      }
                    },
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
            title: options.format == 'gif'
                ? 'GIF 生成ing'
                : mode == 1
                ? '图生图ing'
                : '文生图ing',
            stage: taskStage,
            progress: stageProgress(taskStage),
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
                child: ZoomableImage(
                  image: FileImage(File(art.path)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.file(File(art.path), fit: BoxFit.cover),
                  ),
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
          ZoomableImage(
            image: FileImage(File(path)),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            ),
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
  void setState(VoidCallback fn) {
    super.setState(fn);
    applySize();
    final updated = GenerationOptions.fromJson(o.toJson());
    widget.initial.width = updated.width;
    widget.initial.height = updated.height;
    widget.initial.count = updated.count;
    widget.initial.compression = updated.compression;
    widget.initial.quality = updated.quality;
    widget.initial.format = updated.format;
    widget.initial.moderation = updated.moderation;
    widget.initial.advanced = Map.of(updated.advanced);
    final store = StudioScope.of(context);
    store.defaults = updated;
    store.saveSettings();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              '生成规格',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          GlassIcon(
            Icons.close_rounded,
            tooltip: '关闭',
            onTap: () => Navigator.pop(context),
          ),
        ],
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
        onChanged: (i) {
          if (i == 3 &&
              !supportsNativeGif(StudioScope.of(context).imageApi.model)) {
            toast(context, '当前模型暂不支持 GIF');
            return;
          }
          setState(() => o.format = ['png', 'jpeg', 'webp', 'gif'][i]);
        },
      ),
      const SizedBox(height: 13),
      Text(
        o.format == 'gif'
            ? '仅 gpt-image-2.6 系列支持原生 GIF；有上传图片时使用原尺寸请求，直接保留返回动画和实际像素，不重新编码或缩放。'
            : o.format == 'png'
            ? 'PNG 为无损格式，压缩质量不改变画质。'
            : '编码质量越低，文件通常越小。',
        style: TextStyle(fontSize: 12, color: muted(context), height: 1.7),
      ),
      if (o.format == 'jpeg' || o.format == 'webp') ...[
        const SizedBox(height: 16),
        GlassSlider(
          label: '压缩质量',
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
    ],
  );
}

class ProfessionalControls extends StatefulWidget {
  final GenerationOptions options;
  final VoidCallback onChanged;
  const ProfessionalControls({
    super.key,
    required this.options,
    required this.onChanged,
  });
  @override
  State<ProfessionalControls> createState() => _ProfessionalControlsState();
}

class _ProfessionalControlsState extends State<ProfessionalControls> {
  late final seed = TextEditingController(
    text: widget.options.advanced['seed']?.toString() ?? '',
  );
  late final steps = TextEditingController(
    text: widget.options.advanced['steps']?.toString() ?? '',
  );
  late final sampler = TextEditingController(
    text: widget.options.advanced['sampler']?.toString() ?? '',
  );
  late bool enabled = widget.options.advanced.isNotEmpty;
  late double guidance =
      (widget.options.advanced['guidance_scale'] as num? ?? 7).toDouble().clamp(
        1,
        20,
      );
  String? error;
  void update() {
    final s = int.tryParse(seed.text), n = int.tryParse(steps.text);
    if ((seed.text.isNotEmpty && (s == null || s < 0 || s > 2147483647)) ||
        (steps.text.isNotEmpty && (n == null || n < 1 || n > 150))) {
      setState(() => error = 'Seed 为 0–2147483647；采样步数为 1–150');
      return;
    }
    setState(() => error = null);
    widget.options.advanced = enabled
        ? {
            'seed': ?s,
            'steps': ?n,
            'guidance_scale': double.parse(guidance.toStringAsFixed(1)),
            if (sampler.text.trim().isNotEmpty) 'sampler': sampler.text.trim(),
          }
        : {};
    widget.onChanged();
  }

  @override
  void dispose() {
    seed.dispose();
    steps.dispose();
    sampler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Glass(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '接口扩展参数',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            GlassToggle(
              value: enabled,
              onChanged: (v) {
                setState(() => enabled = v);
                update();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '仅在服务商明确支持 Seed、步数、CFG、采样器时启用。GPT Image 通常不接受这些采样参数，关闭时不会发送。',
          style: TextStyle(fontSize: 12, height: 1.7, color: muted(context)),
        ),
        if (enabled) ...[
          const SectionLabel('随机种子 / Seed'),
          GlassField(
            controller: seed,
            hint: '留空由模型随机决定',
            keyboard: TextInputType.number,
            onChanged: (_) => update(),
          ),
          const SectionLabel('采样步数'),
          GlassField(
            controller: steps,
            hint: '留空采用服务端默认值',
            keyboard: TextInputType.number,
            onChanged: (_) => update(),
          ),
          const SizedBox(height: 20),
          GlassSlider(
            label: '提示词遵循 / CFG',
            valueLabel: guidance.toStringAsFixed(1),
            value: guidance,
            min: 1,
            max: 20,
            onChanged: (v) {
              setState(() => guidance = v);
              update();
            },
          ),
          const SectionLabel('采样器 / Sampler'),
          GlassField(
            controller: sampler,
            hint: '按服务商文档填写，留空使用默认值',
            onChanged: (_) => update(),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.deepOrange, fontSize: 12),
              ),
            ),
        ],
      ],
    ),
  );
}
