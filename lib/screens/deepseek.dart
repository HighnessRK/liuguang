import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/imaging.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/glass.dart';
import 'custom_sticker.dart';

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
  double progress = 0;
  int seconds = 0;
  Timer? timer;
  CancelToken? token;
  String stage = '等待生成';
  List<StickerProfile> profiles = [];
  StickerProfile? selectedProfile;
  @override
  void initState() {
    super.initState();
    final raw = widget.store.prefs.getStringList('sticker_profiles') ?? [];
    profiles = raw
        .map((v) {
          try {
            return StickerProfile.fromJson(jsonDecode(v));
          } catch (_) {
            return null;
          }
        })
        .whereType<StickerProfile>()
        .toList();
    final selectedId = widget.store.prefs.getString('last_sticker_profile');
    selectedProfile = profiles.where((p) => p.id == selectedId).firstOrNull;
  }

  @override
  void dispose() {
    token?.cancel();
    timer?.cancel();
    text.dispose();
    super.dispose();
  }

  Future<String> referencePath() async {
    final data = await rootBundle.load('assets/deepseek/fish_reference.jpg');
    final dir = await safeTemporaryDirectory();
    final file = File('${dir.path}/deepseek-fish-reference.jpg');
    await file.writeAsBytes(data.buffer.asUint8List());
    return file.path;
  }

  Future<void> generate() async {
    if (busy || text.text.trim().isEmpty) return;
    if (!widget.store.imageApi.ready || !widget.store.chatApi.ready) {
      toast(context, '请先配置生图和对话模型');
      return;
    }
    setState(() {
      busy = true;
      seconds = 0;
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => seconds++);
      });
      stage = '对话模型正在理解表情文本';
      progress = .08;
    });
    token = CancelToken();
    try {
      final brief = await widget.api.chat([
        ChatMessage(
          'user',
          '''请把以下表情包文字设计成画面指令，保留大肥鱼娘基本形象，明确动作、道具、表情、构图和文字位置。只输出生图模型可执行的中文提示词。
${text.text.trim()}
角色设定：${selectedProfile?.description ?? '保持大肥鱼娘固定形象'}''',
        ),
      ], cancelToken: token);
      final paths = selectedProfile?.references.isNotEmpty == true
          ? selectedProfile!.references
          : [await referencePath()];
      setState(() {
        stage = animated ? '生图模型正在生成动图' : '生图模型正在生成表情包';
        progress = .25;
      });
      final options = animated
          ? GenerationOptions(
              width: 512,
              height: 512,
              format: 'gif',
              quality: 'high',
              count: 1,
              advanced: {'frame_count': 8, 'frame_duration_ms': 150},
            )
          : GenerationOptions(
              width: 4096,
              height: 4096,
              format: 'jpeg',
              quality: 'high',
            );
      final reply = await widget.api.generate(
        prompt:
            '''$brief
画面文字：${text.text.trim()}
保持蓝发、女仆装、鱼尾和统一角色设计，保持帧间一致性，smooth motion，consistent character，帧间一致性约束，画面铺满画布，不要白边。''',
        options: options,
        inputs: paths,
        cancelToken: token,
        operation: animated ? 'DeepSeek 动图表情包' : 'DeepSeek 静态表情包',
        onStage: (v) {
          if (mounted)
            setState(() {
              stage = v;
              progress = stageProgress(v) ?? progress;
            });
        },
      );
      setState(() {
        progress = 1;
        stage = '已生成，已保存到作品';
      });
      for (final bytes in reply.images) {
        await saveArtwork(
          widget.store,
          bytes,
          prompt: text.text.trim(),
          model: widget.store.imageApi.model,
          kind: animated ? 'DeepSeek 动图表情包' : 'DeepSeek 表情包',
          format: animated ? 'gif' : 'jpeg',
        );
      }
      if (mounted) {
        toast(context, '已保存到作品');
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) toast(context, describeError(e));
    } finally {
      timer?.cancel();
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
              title: 'DeepSeek 表情包',
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassIcon(
                    Icons.swap_horiz_rounded,
                    tooltip: '切换表情角色',
                    onTap: busy
                        ? null
                        : () async {
                            final picked = await glassSheet<StickerProfile>(
                              context,
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '选择表情角色',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ListTile(
                                    title: const Text('DeepSeek 大肥鱼娘'),
                                    onTap: () => Navigator.pop(context, null),
                                  ),
                                  for (final p in profiles)
                                    ListTile(
                                      title: Text(p.name),
                                      onTap: () => Navigator.pop(context, p),
                                    ),
                                ],
                              ),
                            );
                            if (picked != null) {
                              setState(() => selectedProfile = picked);
                              await widget.store.prefs.setString(
                                'last_sticker_profile',
                                picked.id,
                              );
                            }
                          },
                  ),
                  const SizedBox(width: 6),
                  GlassIcon(
                    Icons.person_add_alt_1_rounded,
                    tooltip: '创建表情角色',
                    onTap: busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StickerCharacterCreatorScreen(
                                store: widget.store,
                                api: widget.api,
                              ),
                            ),
                          ),
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
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 170,
                      height: 112,
                      child: ZoomableImage(
                        image: const AssetImage(
                          'assets/deepseek/fish_reference.jpg',
                        ),
                        child: ColoredBox(
                          color: Colors.white,
                          child: Image.asset(
                            'assets/deepseek/fish_reference.jpg',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '''${selectedProfile?.name ?? '大肥鱼娘'}
固定角色参考''',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
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
              labels: ['静态 1:1 · 4K', '动图 1:1 · 512'],
              selected: animated ? 1 : 0,
              onChanged: busy
                  ? (_) {}
                  : (v) => setState(() => animated = v == 1),
            ),
            const SizedBox(height: 18),
            Glass(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '动图模式',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GlassToggle(
                    value: animated,
                    onChanged: busy
                        ? (_) {}
                        : (v) => setState(() => animated = v),
                  ),
                ],
              ),
            ),
            if (animated) ...[
              const SizedBox(height: 10),
              Glass(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                child: Text(
                  '固定 8 帧 · 每帧 150 ms · smooth motion · consistent character · 帧间一致性',
                  style: TextStyle(
                    fontSize: 12,
                    color: muted(context),
                    height: 1.5,
                  ),
                ),
              ),
            ],
            if (busy) ...[
              const SizedBox(height: 18),
              TaskStatusCard(
                title: animated ? 'DeepSeek 动图ing' : 'DeepSeek 表情包ing',
                stage: stage,
                progress: progress,
                seconds: seconds,
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
