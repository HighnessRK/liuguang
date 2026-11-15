import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api.dart' show beginProcessing, endProcessing;
import '../core/models.dart';
import '../core/materials.dart';
import '../core/store.dart';
import '../ui/glass.dart';

Future<void> shareArtworkCard(
  BuildContext context,
  AppStore store,
  Artwork art,
) => shareArtworkCards(context, store, [art]);

Future<void> shareArtworkCards(
  BuildContext context,
  AppStore store,
  List<Artwork> artworks,
) async {
  if (artworks.isEmpty) return;
  int template = (store.prefs.getInt('share_template') ?? 0).clamp(0, 2);
  final hasLens = artworks.any(
    (a) => a.kind.contains('景深') || a.kind.contains('传奇'),
  );
  bool includePrompt =
      store.prefs.getBool(hasLens ? 'share_prompt_lens' : 'share_prompt') ??
      !hasLens;
  final accepted = await glassSheet<bool>(
    context,
    StatefulBuilder(
      builder: (ctx, update) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '作品分享图',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '${artworks.length} 件作品 · 3072 px 超清 · 本地排版',
            style: TextStyle(fontSize: 12, color: muted(ctx)),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  update(() => template = i);
                  store.prefs.setInt('share_template', i);
                },
                child: Glass(
                  radius: 20,
                  padding: const EdgeInsets.all(12),
                  tint: template == i
                      ? accent(ctx).withValues(alpha: .2)
                      : null,
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 72,
                        padding: EdgeInsets.all(i == 2 ? 10 : 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: LinearGradient(
                            colors: i == 1
                                ? const [Color(0xff162133), Color(0xff454059)]
                                : i == 2
                                ? const [Color(0xfffaf8f4), Color(0xffeeeae3)]
                                : const [Color(0xffcddcff), Color(0xfff6dbe7)],
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(i == 2 ? 0 : 5),
                          child: Image.file(
                            File(artworks.first.path),
                            cacheWidth: 160,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.image_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ['极光柔彩', '午夜光影', '纯白画廊'][i],
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                '柔彩画布 · 参数卡片 · 创作手记',
                                '宽幅影像 · 电影字幕 · 暗色质感',
                                '展览留白 · 档案编号 · 极简网格',
                              ][i],
                              style: TextStyle(fontSize: 12, color: muted(ctx)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        template == i
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: template == i ? accent(ctx) : muted(ctx),
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('包含提示词')),
              GlassToggle(
                value: includePrompt,
                onChanged: (v) {
                  update(() => includePrompt = v);
                  store.prefs.setBool(
                    hasLens ? 'share_prompt_lens' : 'share_prompt',
                    v,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          GlassButton(
            '生成超清分享图',
            primary: true,
            icon: Icons.ios_share_rounded,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ),
  );
  if (accepted != true || !context.mounted) return;
  final navigator = Navigator.of(context);
  final count = ValueNotifier<int>(0);
  final progress = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Glass(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('正在本地排版分享图'),
              const SizedBox(height: 8),
              ValueListenableBuilder(
                valueListenable: count,
                builder: (_, value, _) => Text(
                  '$value / ${artworks.length} · 无需模型额度',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  navigator.push(progress);
  final files = <XFile>[];
  try {
    await beginProcessing(local: true);
    for (final art in artworks) {
      final file = await renderArtworkCard(
        store,
        art,
        includePrompt: includePrompt,
        template: template,
      );
      files.add(XFile(file.path));
      count.value++;
    }
  } catch (e) {
    if (context.mounted) toast(context, '分享图生成失败：$e');
    files.clear();
  } finally {
    await endProcessing(local: true);
    if (progress.isActive) navigator.removeRoute(progress);
    count.dispose();
  }
  if (files.isNotEmpty) {
    await SharePlus.instance.share(ShareParams(files: files, text: '由琉光创作'));
  }
}

/// All typography is laid out before painting; legacy records never invent request parameters.
Future<File> renderArtworkCard(
  AppStore store,
  Artwork art, {
  required bool includePrompt,
  int template = 0,
}) async {
  final file = File(art.path);
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 3072,
    allowUpscaling: false,
  );
  final photo = (await codec.getNextFrame()).image;
  codec.dispose();
  ui.Picture? picture;
  ui.Image? output;
  final painters = <TextPainter>[];
  try {
    const width = 3072.0;
    final dark = template == 1, gallery = template == 2;
    final pad = gallery
        ? 210.0
        : dark
        ? 112.0
        : 144.0;
    final fg = dark ? const Color(0xfff4f3f9) : const Color(0xff202838);
    final secondary = dark ? const Color(0xffb6bfd3) : const Color(0xff697185);
    final accent = dark
        ? const Color(0xffcab5ee)
        : gallery
        ? const Color(0xff998465)
        : const Color(0xff6d70c4);
    final contentWidth = width - 2 * pad;
    TextPainter text(
      String value,
      double size, {
      Color? color,
      FontWeight weight = FontWeight.w400,
      double? maxWidth,
      double height = 1.5,
    }) {
      final p = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontSize: size,
            color: color ?? fg,
            fontWeight: weight,
            height: height,
          ),
        ),
      )..layout(maxWidth: maxWidth ?? contentWidth);
      painters.add(p);
      return p;
    }

    final date = art.created.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final time =
        '${date.year}.${two(date.month)}.${two(date.day)}  ${two(date.hour)}:${two(date.minute)}';
    final p = art.parameters;
    final extension = art.path.split('.').last.toUpperCase();
    final specs = <(String, String)>[
      ('实际画幅', '${art.width} × ${art.height} px'),
      (
        '文件',
        '$extension  /  ${(bytes.length / 1048576).toStringAsFixed(2)} MB',
      ),
      if (p['width'] != null && p['height'] != null)
        ('请求规格', '${p['width']} × ${p['height']} px'),
      if (p['quality'] != null)
        (
          '生成质量',
          {
                'high': '精细',
                'medium': '标准',
                'low': '快速',
                'auto': '自动',
              }[p['quality']] ??
              '${p['quality']}',
        ),
      if (p['references'] != null) ('参考图', '${p['references']} 张'),
      if (p['material'] is String && materialById(p['material']) != null)
        ('材质', materialById(p['material'])!.name),
      if (p['depth'] != null)
        ('景深虚化', '${((p['depth'] as num) * 100).round()}%'),
      if (p['tone'] != null) ('影调强度', '${((p['tone'] as num) * 100).round()}%'),
    ];
    final heading = text(art.kind, dark ? 116 : 100, weight: FontWeight.w600);
    final model = text(art.model, 44, color: secondary);
    final prompt = includePrompt && art.prompt.trim().isNotEmpty
        ? text(
            art.prompt,
            44,
            color: dark ? const Color(0xffdddde9) : secondary,
            maxWidth: contentWidth - 100,
            height: 1.75,
          )
        : null;
    final photoHeight = (contentWidth * photo.height / photo.width).clamp(
      900.0,
      5700.0,
    );
    final imageTop = dark ? pad + 130 : pad + 110 + heading.height + 72;
    final modelTop =
        imageTop + photoHeight + (dark ? heading.height + 140 : 80);
    final specsTop = modelTop + 76 + model.height;
    final rows = (specs.length / 2).ceil();
    final promptTop = specsTop + rows * 162 + 80;
    final footerTop =
        promptTop + (prompt != null ? 110 + prompt.height + 100 : 30);
    final height = footerTop + 180;
    if (height * width > 33554432) throw StateError('内容过长，请关闭提示词后重试');
    final recorder = ui.PictureRecorder();
    // Use a single recording canvas, separate from image decoding allocations.
    final c = Canvas(recorder);
    final bounds = Rect.fromLTWH(0, 0, width, height);
    c.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xff111a29), Color(0xff282235), Color(0xff0f1824)]
              : gallery
              ? const [Color(0xfffaf9f5), Color(0xfffaf9f5)]
              : const [Color(0xffdce7fc), Color(0xfff8e5ef), Color(0xffe5dffc)],
        ).createShader(bounds),
    );
    void draw(TextPainter p, double x, double y) => p.paint(c, Offset(x, y));
    void line(double y, {double alpha = .25}) => c.drawLine(
      Offset(pad, y),
      Offset(width - pad, y),
      Paint()
        ..color = secondary.withValues(alpha: alpha)
        ..strokeWidth = 2,
    );
    draw(
      text(
        gallery
            ? 'LIUGUANG  /  VISUAL ARCHIVE'
            : dark
            ? 'LIUGUANG   MOTION & STILL'
            : '琉光   /   CREATIVE JOURNAL',
        32,
        color: accent,
        weight: FontWeight.w600,
      ),
      pad,
      pad,
    );
    final stamp = text(time, 30, color: secondary);
    draw(stamp, width - pad - stamp.width, pad);
    draw(heading, pad, dark ? imageTop + photoHeight + 55 : pad + 88);
    final rect = Rect.fromLTWH(pad, imageTop, contentWidth, photoHeight);
    if (!gallery) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          rect.shift(const Offset(0, 18)),
          const Radius.circular(54),
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: dark ? .2 : .07)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 35),
      );
    }
    c.save();
    c.clipRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(
          gallery
              ? 0
              : dark
              ? 24
              : 58,
        ),
      ),
    );
    // Contain preserves the whole photograph, including extreme portrait formats.
    final fit = applyBoxFit(
      BoxFit.contain,
      Size(photo.width.toDouble(), photo.height.toDouble()),
      rect.size,
    );
    final destination = Alignment.center.inscribe(fit.destination, rect);
    c.drawRect(
      rect,
      Paint()
        ..color = dark
            ? const Color(0xff080e17)
            : Colors.white.withValues(alpha: .5),
    );
    c.drawImageRect(
      photo,
      Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
      destination,
      Paint()..filterQuality = FilterQuality.high,
    );
    c.restore();
    if (gallery) {
      line(imageTop - 34);
      draw(
        text(
          'PLATE  ${art.id.length > 6 ? art.id.substring(art.id.length - 6) : art.id}',
          28,
          color: accent,
        ),
        pad,
        imageTop + photoHeight + 22,
      );
    }
    draw(
      text('MODEL / 创作引擎', 27, color: accent, weight: FontWeight.w600),
      pad,
      modelTop,
    );
    draw(model, pad, modelTop + 48);
    if (template == 0) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            pad - 32,
            specsTop - 20,
            contentWidth + 64,
            rows * 162 + 20,
          ),
          const Radius.circular(42),
        ),
        Paint()..color = Colors.white.withValues(alpha: .5),
      );
    }
    for (var i = 0; i < specs.length; i++) {
      final x = pad + (i % 2) * (contentWidth / 2) + (template == 0 ? 22 : 0),
          y = specsTop + (i ~/ 2) * 162;
      draw(text(specs[i].$1.toUpperCase(), 28, color: secondary), x, y);
      draw(
        text(
          specs[i].$2,
          43,
          weight: FontWeight.w600,
          maxWidth: contentWidth / 2 - 60,
        ),
        x,
        y + 47,
      );
    }
    if (prompt != null) {
      line(promptTop - 30);
      draw(
        text(
          gallery
              ? '创作札记  /  PROMPT'
              : dark
              ? 'DIRECTOR’S NOTE  /  提示词'
              : '灵感手记  /  PROMPT',
          30,
          color: accent,
          weight: FontWeight.w600,
        ),
        pad,
        promptTop + 15,
      );
      draw(prompt, pad + (gallery ? 0 : 50), promptTop + 100);
    }
    line(footerTop);
    draw(text('琉光', 45, weight: FontWeight.w600), pad, footerTop + 45);
    draw(
      text('以想象为光 · 为每一帧留下故事', 28, color: secondary),
      pad + 160,
      footerTop + 60,
    );
    final code = text(
      '#${art.id.length > 10 ? art.id.substring(art.id.length - 10) : art.id}',
      27,
      color: secondary,
    );
    draw(code, width - pad - code.width, footerTop + 60);
    picture = recorder.endRecording();
    output = await picture.toImage(width.toInt(), height.ceil());
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('${store.directory.path}/share_cache');
    await folder.create(recursive: true);
    final result = File('${folder.path}/${art.id}-template$template.png');
    await result.writeAsBytes(data!.buffer.asUint8List());
    return result;
  } finally {
    for (final p in painters) {
      p.dispose();
    }
    photo.dispose();
    output?.dispose();
    picture?.dispose();
  }
}
