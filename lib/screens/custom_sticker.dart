import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/imaging.dart';
import '../core/store.dart';
import '../ui/glass.dart';

class StickerProfile {
  final String id;
  final String name;
  final String description;
  final List<String> references;
  const StickerProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.references,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'references': references,
  };
}

class StickerCharacterCreatorScreen extends StatefulWidget {
  final AppStore store;
  final StudioApi api;
  const StickerCharacterCreatorScreen({
    super.key,
    required this.store,
    required this.api,
  });
  @override
  State<StickerCharacterCreatorScreen> createState() =>
      _StickerCharacterCreatorScreenState();
}

class _StickerCharacterCreatorScreenState
    extends State<StickerCharacterCreatorScreen> {
  final name = TextEditingController(text: '我的表情角色');
  final description = TextEditingController();
  final references = <String>[];
  bool polishing = false, saving = false;

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> pickReferences() async {
    final files = await ImagePicker().pickMultiImage(limit: 3);
    if (!mounted || files.isEmpty) return;
    setState(() {
      references
        ..clear()
        ..addAll(files.take(3).map((f) => f.path));
    });
  }

  Future<void> polishDescription() async {
    if (references.isEmpty && description.text.trim().isEmpty) {
      toast(context, '请先添加三视图或填写基本描述');
      return;
    }
    setState(() => polishing = true);
    try {
      var visual = '';
      if (references.isNotEmpty) {
        visual = await widget.api.imageBrief(
          references,
          '分析这个角色三视图，提取外观、服饰、发型、配色、配件和不可改变的角色特征。',
        );
      }
      final result = await widget.api.chat([
        ChatMessage('user', '''请为一个可重复生成表情包的角色整理一段简洁、稳定的角色设定。
角色名：${name.text.trim()}
用户描述：${description.text.trim()}
三视图分析：$visual
只输出角色设定正文，不要解释，不要生成表情文字。'''),
      ]);
      if (mounted) description.text = result.trim();
    } catch (e) {
      if (mounted) toast(context, describeError(e));
    } finally {
      if (mounted) setState(() => polishing = false);
    }
  }

  Future<void> save() async {
    if (references.isEmpty) {
      toast(context, '请添加角色三视图');
      return;
    }
    if (description.text.trim().isEmpty) {
      await polishDescription();
      if (description.text.trim().isEmpty) return;
    }
    setState(() => saving = true);
    final profile = StickerProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.text.trim().isEmpty ? '我的表情角色' : name.text.trim(),
      description: description.text.trim(),
      references: List.of(references),
    );
    final all = widget.store.prefs.getStringList('sticker_profiles') ?? [];
    all.add(jsonEncode(profile.toJson()));
    await widget.store.prefs.setStringList('sticker_profiles', all);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CustomStickerGeneratorScreen(
            store: widget.store,
            api: widget.api,
            profile: profile,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: StudioBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
          children: [
            PageHeader(
              title: '创建表情角色',
              action: GlassIcon(
                Icons.arrow_back_rounded,
                tooltip: '返回',
                onTap: () => Navigator.pop(context),
              ),
            ),
            const SectionLabel('角色名称'),
            GlassField(controller: name, hint: '例如：蓝莓小猫'),
            const SectionLabel('角色三视图'),
            Glass(
              child: Column(
                children: [
                  if (references.isEmpty)
                    Text(
                      '上传正面、侧面、背面或其他能固定角色特征的参考图。',
                      style: TextStyle(color: muted(context), height: 1.6),
                    )
                  else
                    SizedBox(
                      height: 118,
                      child: Row(
                        children: [
                          for (final path in references)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(
                                    File(path),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  GlassButton(
                    references.isEmpty ? '添加三视图' : '重新选择三视图',
                    icon: Icons.add_photo_alternate_outlined,
                    onTap: pickReferences,
                  ),
                ],
              ),
            ),
            const SectionLabel('基本描述'),
            GlassField(
              controller: description,
              hint: '描述角色的身份、性格、服饰、配色和不可改变特征…',
              minLines: 4,
              maxLines: 8,
            ),
            if (polishing)
              const AuroraBusyButton()
            else
              GlassButton(
                '智能润色描述',
                icon: Icons.auto_awesome_rounded,
                onTap: polishDescription,
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GlassButton(
                '保存并开始制作',
                icon: Icons.auto_awesome_rounded,
                onTap: saving ? null : save,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class CustomStickerGeneratorScreen extends StatefulWidget {
  final AppStore store;
  final StudioApi api;
  final StickerProfile profile;
  const CustomStickerGeneratorScreen({
    super.key,
    required this.store,
    required this.api,
    required this.profile,
  });
  @override
  State<CustomStickerGeneratorScreen> createState() =>
      _CustomStickerGeneratorScreenState();
}

class _CustomStickerGeneratorScreenState
    extends State<CustomStickerGeneratorScreen> {
  final text = TextEditingController();
  bool animated = false, busy = false;
  double progress = 0;
  String stage = '等待生成';
  CancelToken? token;

  @override
  void dispose() {
    token?.cancel();
    text.dispose();
    super.dispose();
  }

  Future<void> generate() async {
    if (busy || text.text.trim().isEmpty) return;
    if (!widget.store.imageApi.ready || !widget.store.chatApi.ready) {
      toast(context, '请先配置生图和对话模型');
      return;
    }
    setState(() {
      busy = true;
      progress = .08;
      stage = '对话模型正在理解表情文本';
    });
    token = CancelToken();
    try {
      final brief = await widget.api.chat([
        ChatMessage('user', '''根据角色设定和表情文字，设计一个可执行的表情包画面指令。
角色设定：${widget.profile.description}
表情文字：${text.text.trim()}
只输出生图提示词，保留角色外观一致性、动作、道具和文字位置。'''),
      ], cancelToken: token);
      setState(() {
        progress = .25;
        stage = animated ? '生图模型正在生成动图' : '生图模型正在生成表情包';
      });
      final options = animated
          ? GenerationOptions(
              width: 512,
              height: 512,
              format: 'gif',
              quality: 'high',
              advanced: {'frame_count': 8, 'frame_duration_ms': 200},
            )
          : GenerationOptions(
              width: 4096,
              height: 4096,
              format: 'png',
              quality: 'high',
            );
      final reply = await widget.api.generate(
        prompt:
            '''$brief
角色设定：${widget.profile.description}
画面文字：${text.text.trim()}
保持 consistent character，smooth motion，画面铺满画布，不要白边。''',
        options: options,
        inputs: widget.profile.references,
        cancelToken: token,
        operation: '${widget.profile.name} ${animated ? '动图' : '表情包'}',
        onStage: (v) {
          if (mounted)
            setState(() {
              stage = v;
              progress = stageProgress(v) ?? progress;
            });
        },
      );
      for (final bytes in reply.images) {
        await saveArtwork(
          widget.store,
          bytes,
          prompt: text.text.trim(),
          model: widget.store.imageApi.model,
          kind: '${widget.profile.name}${animated ? ' 动图表情包' : ' 表情包'}',
        );
      }
      if (mounted) toast(context, '已保存到作品');
    } catch (e) {
      if (mounted) toast(context, describeError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: StudioBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
          children: [
            PageHeader(
              title: widget.profile.name,
              action: GlassIcon(
                Icons.arrow_back_rounded,
                tooltip: '返回',
                onTap: () => Navigator.pop(context),
              ),
            ),
            Glass(
              child: Text(
                widget.profile.description,
                style: TextStyle(color: muted(context), height: 1.6),
              ),
            ),
            const SectionLabel('表情文本'),
            GlassField(
              controller: text,
              hint: '例如：今天也要元气满满',
              minLines: 3,
              maxLines: 5,
            ),
            const SectionLabel('生成类型'),
            GlassSegments(
              labels: const ['静态 1:1 · 4K', '动图 1:1 · 512'],
              selected: animated ? 1 : 0,
              onChanged: busy
                  ? (_) {}
                  : (v) => setState(() => animated = v == 1),
            ),
            const SizedBox(height: 18),
            if (animated)
              Glass(
                child: Text(
                  '固定 8 帧 · 每帧 200 ms · smooth motion · consistent character',
                  style: TextStyle(color: muted(context), height: 1.5),
                ),
              ),
            if (busy) ...[
              const SizedBox(height: 18),
              TaskStatusCard(
                title: animated
                    ? '${widget.profile.name} 动图ing'
                    : '${widget.profile.name} 表情包ing',
                stage: stage,
                progress: progress,
                seconds: 0,
                onCancel: () => token?.cancel(),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: GlassButton(
                '生成表情包',
                icon: Icons.auto_awesome_rounded,
                onTap: busy ? null : generate,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
