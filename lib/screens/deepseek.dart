import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api.dart';
import '../core/imaging.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/glass.dart';

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
  CancelToken? token;
  String stage = '等待生成';
  @override
  void dispose() {
    token?.cancel();
    text.dispose();
    super.dispose();
  }

  Future<String> referencePath() async {
    final data = await rootBundle.load('assets/deepseek/fish_reference.jpg');
    final dir = await getTemporaryDirectory();
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
      stage = '对话模型正在理解表情文本';
      progress = .08;
    });
    token = CancelToken();
    try {
      final brief = await widget.api.chat([
        ChatMessage(
          'user',
          '''请把以下表情包文字设计成画面指令，保留大肥鱼娘基本形象，明确动作、道具、表情、构图和文字位置。只输出生图模型可执行的中文提示词。
${text.text.trim()}''',
        ),
      ], cancelToken: token);
      final path = await referencePath();
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
              advanced: {'frame_count': 9, 'frame_duration_ms': 200},
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
画面文字：${text.text.trim()}
保持蓝发、女仆装、鱼尾、统一角色设计，画面铺满画布，不要白边。''',
        options: options,
        inputs: [path],
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
              title: 'DeepSeek 表情包',
              action: GlassIcon(
                Icons.arrow_back_rounded,
                tooltip: '返回',
                onTap: () => Navigator.pop(context),
              ),
            ),
            Glass(
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/deepseek/fish_reference.jpg',
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      '''大肥鱼娘
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
            Row(
              children: [
                const Expanded(child: Text('动图模式')),
                GlassToggle(
                  value: animated,
                  onChanged: busy
                      ? (_) {}
                      : (v) => setState(() => animated = v),
                ),
              ],
            ),
            if (animated)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '帧数由对话模型决定，范围 2–16，默认 9；帧间隔范围 20–2000 ms，默认 200 ms。',
                  style: TextStyle(fontSize: 12, color: muted(context)),
                ),
              ),
            if (busy) ...[
              const SizedBox(height: 18),
              TaskStatusCard(
                title: animated ? 'DeepSeek 动图ing' : 'DeepSeek 表情包ing',
                stage: stage,
                progress: progress,
                seconds: 0,
                onCancel: () => token?.cancel(),
              ),
            ],
            const SizedBox(height: 18),
            GlassButton(
              '生成表情包',
              primary: true,
              icon: Icons.auto_awesome_rounded,
              onTap: busy ? null : generate,
            ),
          ],
        ),
      ),
    ),
  );
}
