import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart' as lgr;

import '../core/api.dart';
import '../core/imaging.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/glass.dart';

class EditorScreen extends StatefulWidget {
  final AppStore store;
  final StudioApi api;
  final String? initialPath;
  final VoidCallback onSettings;
  const EditorScreen({
    super.key,
    required this.store,
    required this.api,
    this.initialPath,
    required this.onSettings,
  });
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _Snapshot {
  final String path;
  final Adjustments a;
  _Snapshot(this.path, Adjustments adjustments) : a = adjustments.clone();
}

class _Stroke {
  final List<Offset> points;
  final double width;
  final bool erase;
  _Stroke(this.points, this.width, this.erase);
}

class _EditorScreenState extends State<EditorScreen> {
  String? path;
  ui.Image? image;
  ui.FragmentShader? shader;
  Adjustments a = Adjustments();
  final List<_Snapshot> undo = [], redo = [];
  int tool = 0, adjustment = 0, balanceRange = 1;
  bool busy = false,
      compare = false,
      eraser = false,
      loading = false,
      feather = true;
  String activity = '';
  bool manualLens = false;
  int taskSeconds = 0;
  Timer? taskTicker;
  void beginTask(String stage) {
    taskTicker?.cancel();
    setState(() {
      busy = true;
      activity = stage;
      taskSeconds = 0;
    });
    taskTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !busy) {
        taskTicker?.cancel();
        return;
      }
      setState(() => taskSeconds++);
    });
  }

  CancelToken? token;
  final editPrompt = TextEditingController();
  List<_Stroke> strokes = [];
  double brush = .075;
  int cloudEdge = 4096;
  bool portraitAI = false;
  int portraitStyle = 0;
  double portraitStrength = .55;
  int lensStyle = 0;
  double lensStrength = .72;
  Rect crop = const Rect.fromLTWH(0, 0, 1, 1);
  int cropRatio = 0;
  double focusX = .5, focusY = .45, focusRadius = .34, bokehStrength = .5;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      shader = (await ui.FragmentProgram.fromAsset('shaders/adjustments.frag'))
          .fragmentShader();
    } catch (e) {
      if (mounted) {
        toast(context, '实时调色着色器加载失败：$e');
      }
    }
    if (widget.initialPath != null) {
      await load(widget.initialPath!);
    }
    if (Platform.isAndroid && widget.initialPath == null) {
      try {
        final lost = await ImagePicker().retrieveLostData();
        if (!lost.isEmpty && lost.files?.isNotEmpty == true && mounted) {
          await load(lost.files!.first.path);
        }
      } catch (_) {
        /* The next manual import can recover from picker interruption. */
      }
    }
  }

  Future<void> load(String value, {bool reset = true}) async {
    if (mounted) {
      setState(() => loading = true);
    }
    try {
      final codec = await ui.instantiateImageCodec(
        await File(value).readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final old = image;
      setState(() {
        path = value;
        image = frame.image;
        if (reset) {
          a = Adjustments();
          undo.clear();
          redo.clear();
          strokes = [];
          crop = const Rect.fromLTWH(0, 0, 1, 1);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    } catch (e) {
      if (mounted) {
        toast(context, '无法读取图片：$e');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> pick() async {
    if (busy) {
      return;
    }
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file != null) {
        await load(file.path);
      }
    } catch (e) {
      if (mounted) {
        toast(context, '无法打开图片：$e');
      }
    }
  }

  void remember() {
    if (path == null) {
      return;
    }
    undo.add(_Snapshot(path!, a));
    if (undo.length > 35) {
      undo.removeAt(0);
    }
    redo.clear();
  }

  Future<void> restore(bool forward) async {
    final from = forward ? redo : undo, to = forward ? undo : redo;
    if (from.isEmpty || busy) {
      return;
    }
    final snapshot = from.removeLast();
    to.add(_Snapshot(path!, a));
    if (path != snapshot.path) {
      await load(snapshot.path, reset: false);
    }
    if (mounted) {
      setState(() {
        a = snapshot.a.clone();
        strokes = [];
      });
    }
  }

  @override
  void dispose() {
    token?.cancel();
    taskTicker?.cancel();
    image?.dispose();
    shader?.dispose();
    editPrompt.dispose();
    super.dispose();
  }

  Future<void> export() async {
    if (path == null || busy) {
      return;
    }
    final choice = await glassSheet<Map<String, dynamic>>(
      context,
      const ExportSheet(),
    );
    if (choice == null || !mounted) {
      return;
    }
    beginTask('正在导出原始分辨率…');
    try {
      final result = await renderEdited(
        path!,
        a,
        format: choice['format'],
        quality: choice['quality'],
      );
      final art = await saveArtwork(
        widget.store,
        result['bytes'],
        prompt: '本地修图 · 调色与影调',
        model: '本地处理',
        kind: '修图',
      );
      if (choice['gallery'] == true) {
        await saveToGallery(art.path);
      }
      if (mounted) {
        toast(context, choice['gallery'] == true ? '已保存到作品和系统相册' : '已保存到作品');
      }
    } catch (e) {
      if (mounted) {
        toast(context, describeError(e));
      }
    } finally {
      if (mounted) {
        taskTicker?.cancel();
        setState(() => busy = false);
      }
    }
  }

  Future<void> geometry({
    int rotation = 0,
    bool flip = false,
    bool applyCrop = false,
  }) async {
    if (path == null || busy) {
      return;
    }
    beginTask('正在处理构图…');
    try {
      final result = await renderEdited(
        path!,
        a,
        rotation: rotation,
        flip: flip,
        crop: applyCrop ? [crop.left, crop.top, crop.width, crop.height] : null,
      );
      final next = await widget.store.writeImage(result['bytes'], 'png');
      remember();
      await load(next, reset: false);
      if (mounted) {
        setState(() {
          a = Adjustments();
          crop = const Rect.fromLTWH(0, 0, 1, 1);
          cropRatio = 0;
          strokes = [];
        });
      }
    } catch (e) {
      if (mounted) {
        toast(context, describeError(e));
      }
    } finally {
      if (mounted) {
        taskTicker?.cancel();
        setState(() => busy = false);
      }
    }
  }

  Future<Uint8List> maskBytes() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    for (final s in strokes) {
      final paint = Paint()
        ..color = Colors.white
        ..blendMode = s.erase ? BlendMode.srcOver : BlendMode.clear
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.width * image!.width;
      if (feather) {
        paint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(1, s.width * image!.width * .08),
        );
      }
      final p = Path()
        ..moveTo(
          s.points.first.dx * image!.width,
          s.points.first.dy * image!.height,
        );
      if (s.points.length == 1) {
        p.lineTo(
          s.points.first.dx * image!.width + .01,
          s.points.first.dy * image!.height,
        );
      }
      for (final point in s.points.skip(1)) {
        p.lineTo(point.dx * image!.width, point.dy * image!.height);
      }
      canvas.drawPath(p, paint);
    }
    final picture = recorder.endRecording();
    final mask = await picture.toImage(image!.width, image!.height);
    picture.dispose();
    final rgba = (await mask.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    var selected = false;
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] < 250) {
        selected = true;
        break;
      }
    }
    if (!selected) {
      mask.dispose();
      throw StudioException('当前没有有效选区，请重新涂抹');
    }
    final bytes = (await mask.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    mask.dispose();
    return bytes;
  }

  Future<void> cloudEdit({bool lens = false, bool portrait = false}) async {
    if (path == null || busy) {
      return;
    }
    if (!widget.store.imageApi.ready) {
      widget.onSettings();
      return;
    }
    if (!lens && !portrait && !strokes.any((s) => !s.erase)) {
      toast(context, '先涂抹需要修改的区域');
      return;
    }
    if (!lens && !portrait && editPrompt.text.trim().isEmpty) {
      toast(context, '请描述选区需要怎样修改');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final model = widget.store.imageApi.model;
    final originalWidth = image!.width, originalHeight = image!.height;
    final requestOptions = matchedPhotoOptions(
      originalWidth,
      originalHeight,
      edge: cloudEdge,
    );

    final toneStyle = lensStyle, toneStrength = lensStrength;
    beginTask(lens ? '正在准备增强副本' : '正在准备选区');
    token = CancelToken();
    try {
      final normalized = await renderEdited(
        path!,
        a,
        maxEdge: lens || portrait ? 2048 : null,
        format: lens || portrait ? 'jpeg' : 'png',
        quality: 92,
      );
      if (token!.isCancelled) throw token!.cancelError!;
      final source = await widget.store.writeImage(
        normalized['bytes'],
        imageExtension(normalized['bytes']),
      );
      final mask = lens || portrait ? null : await maskBytes();
      final instruction = portrait
          ? '人像美化：${portraitNames[portraitStyle]}，强度 ${(portraitStrength * 100).round()}%。保持原图人物身份、年龄、肤色特征、五官比例、发丝、动作、服装、背景与构图。仅作自然皮肤质感、瑕疵淡化和光影优化，保留毛孔与真实肌理，避免塑料皮肤，不新增人物或改变身形。${["温和柔肤与淡化细小瑕疵", "均衡人脸曝光，通透提亮而不过曝", "温暖肤色与柔和人像补光", "自然改善气色，克制的红润肤色", "细腻黑白人像，保留丰富灰阶与立体光影"][portraitStyle]}。'
          : lens
          ? '$lensPrompt\n影调方向：${lensToneNames[toneStyle]}，影调强度 ${(toneStrength * 100).round()}%，明暗层次鲜明、色彩分离自然，避免平淡灰雾。'
          : '${editPrompt.text}\n\n仅修改蒙版透明区域。保持其余区域的主体、人物身份、构图与光照，不添加额外元素。';
      final response = await widget.api.generate(
        prompt: instruction,
        options: GenerationOptions(
          width: requestOptions.width,
          height: requestOptions.height,
          count: 1,
          quality: 'high',
          format: 'png',
          moderation: widget.store.defaults.moderation,
        ),
        inputs: [source],
        mask: mask,
        cancelToken: token,
        operation: portrait
            ? 'AI 人像美化'
            : lens
            ? '云端景深增强'
            : '局部修图',
        onStage: (stage) {
          if (mounted && activity != stage) setState(() => activity = stage);
        },
      );
      Uint8List result = response.images.first;
      int? modelWidth, modelHeight;
      if (lens) {
        if (mounted) setState(() => activity = '正在精修影调与保存画布');
        final finished = await compute(finishLensImage, {
          'bytes': result,
          'style': toneStyle,
          'strength': toneStrength,
        });
        result = finished['bytes'];
        modelWidth = finished['modelWidth'];
        modelHeight = finished['modelHeight'];
      }
      if (mask != null) {
        result = await compute(compositeMasked, {
          'original': normalized['bytes'],
          'generated': result,
          'mask': mask,
        });
      }
      if (token?.isCancelled == true) throw token!.cancelError!;
      if (mounted) setState(() => activity = '正在保存结果');
      final art = await saveArtwork(
        widget.store,
        result,
        prompt: instruction,
        model: model,
        kind: portrait
            ? 'AI 人像美化'
            : lens
            ? '景深增强'
            : '局部修图',
        modelWidth: modelWidth,
        modelHeight: modelHeight,
      );
      remember();
      await load(art.path, reset: false);
      if (mounted) {
        setState(() {
          a = Adjustments();
          strokes = [];
        });
        toast(context, '已完成并保存到作品，可撤销返回原图');
      }
    } catch (e) {
      if (mounted) {
        toast(context, describeError(e));
      }
    } finally {
      token = null;
      if (mounted) {
        taskTicker?.cancel();
        setState(() => busy = false);
      }
    }
  }

  Future<void> applyBokeh() async {
    if (path == null || busy) {
      return;
    }
    beginTask('正在柔化离焦区域…');
    try {
      final normalized = await renderEdited(path!, a);
      final bytes = await compute(localBokeh, {
        'bytes': normalized['bytes'],
        'strength': bokehStrength,
        'x': focusX,
        'y': focusY,
        'radius': focusRadius,
      });
      final next = await widget.store.writeImage(bytes, 'png');
      remember();
      await load(next, reset: false);
      if (mounted) {
        setState(() => a = Adjustments());
      }
    } catch (e) {
      if (mounted) {
        toast(context, describeError(e));
      }
    } finally {
      if (mounted) {
        taskTicker?.cancel();
        setState(() => busy = false);
      }
    }
  }

  Future<void> applyPortrait() async {
    if (path == null || busy) return;
    beginTask('正在本机精修人像…');
    try {
      final original = await renderEdited(path!, a);
      final result = await compute(beautifyPortrait, {
        'bytes': original['bytes'],
        'style': portraitStyle,
        'strength': portraitStrength,
      });
      final next = await widget.store.writeImage(result['bytes'], 'png');
      remember();
      await load(next, reset: false);
      if (mounted) setState(() => a = Adjustments());
    } catch (e) {
      if (mounted) toast(context, describeError(e));
    } finally {
      taskTicker?.cancel();
      if (mounted) setState(() => busy = false);
    }
  }

  Widget portraitControls() => Glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '人像美化',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          portraitAI ? '通过生图模型精修 · 保留人物身份' : '本机处理 · 自然肤色与细腻肌理',
          style: TextStyle(fontSize: 14, color: muted(context)),
        ),
        const SizedBox(height: 22),
        GlassSegments(
          labels: const ['本机处理', 'AI 美化'],
          selected: portraitAI ? 1 : 0,
          onChanged: (i) => setState(() => portraitAI = i == 1),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            for (var i = 0; i < portraitNames.length; i++)
              GlassButton(
                portraitNames[i],
                small: true,
                primary: portraitStyle == i,
                onTap: () => setState(() => portraitStyle = i),
              ),
          ],
        ),
        const SizedBox(height: 24),
        GlassSlider(
          label: '美化强度',
          value: portraitStrength,
          min: 0,
          max: 1,
          onChanged: (v) => setState(() => portraitStrength = v),
        ),
        const SizedBox(height: 24),
        GlassButton(
          portraitAI ? '开始 AI 美化' : '应用人像美化',
          primary: true,
          onTap: busy
              ? null
              : portraitAI
              ? () => cloudEdit(portrait: true)
              : applyPortrait,
        ),
        if (portraitAI) cloudSpecifications(),
        const SizedBox(height: 16),
        Text(
          '柔肤依据肤色保护边缘，不改变五官与身形；可撤销，导出为副本。',
          style: TextStyle(fontSize: 12, height: 1.7, color: muted(context)),
        ),
      ],
    ),
  );

  void ratio(int i) {
    final ratios = [
      image!.width / image!.height,
      1.0,
      4 / 3,
      3 / 2,
      16 / 9,
      9 / 16,
    ];
    final desired = ratios[i], original = image!.width / image!.height;
    final w = desired > original ? 1.0 : desired / original,
        h = desired > original ? original / desired : 1.0;
    setState(() {
      cropRatio = i;
      crop = Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
    });
  }

  @override
  Widget build(BuildContext context) {
    final header = PageHeader(
      title: '修图',
      action: GlassIcon(
        Icons.add_photo_alternate_outlined,
        tooltip: '导入图片',
        onTap: busy ? null : pick,
      ),
    );
    if (image == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 112),
        children: [
          header,
          EmptyState(
            icon: Icons.tune_rounded,
            title: '导入照片',
            subtitle: '实时调色 · 局部修图 · 光学景深\n每一处修改，都保留撤销的余地。',
            action: Column(
              children: [
                GlassButton(
                  '从相册导入',
                  primary: true,
                  icon: Icons.add_rounded,
                  onTap: busy ? null : pick,
                ),
                const SizedBox(height: 14),
                GlassButton(
                  '传奇二瞬 · 景深增强',
                  icon: Icons.auto_awesome_rounded,
                  onTap: () {
                    setState(() => tool = 4);
                    pick();
                  },
                ),
                const SizedBox(height: 14),
                GlassButton(
                  '用示例照片体验',
                  small: true,
                  onTap: () async {
                    await load(await widget.store.demoImage());
                  },
                ),
              ],
            ),
          ),
          if (loading) const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, bounds) => Column(
        children: [
          if (bounds.maxHeight > 450)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: header,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: photoPreview((bounds.maxHeight * .28).clamp(90.0, 248.0)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                GlassIcon(
                  Icons.undo_rounded,
                  tooltip: '撤销',
                  onTap: busy || undo.isEmpty ? null : () => restore(false),
                ),
                const SizedBox(width: 8),
                GlassIcon(
                  Icons.redo_rounded,
                  tooltip: '重做',
                  onTap: busy || redo.isEmpty ? null : () => restore(true),
                ),
                const Spacer(),
                GlassButton(
                  '导出',
                  primary: true,
                  small: true,
                  icon: Icons.ios_share_rounded,
                  onTap: busy ? null : export,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              height: 82,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final i in [4, 5, 0, 1, 2, 3])
                    SizedBox(
                      width: 64,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: busy ? null : () => setState(() => tool = i),
                          child: Glass(
                            radius: 18,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            tint: tool == i ? accent(context) : null,
                            opacity: tool == i ? .65 : null,
                            child: Column(
                              children: [
                                Icon(
                                  [
                                    Icons.tune_rounded,
                                    Icons.palette_outlined,
                                    Icons.crop_rounded,
                                    Icons.brush_outlined,
                                    Icons.auto_awesome_rounded,
                                    Icons.face_retouching_natural,
                                  ][i],
                                  size: 22,
                                  color: tool == i
                                      ? primaryOn(context)
                                      : ink(context),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  [
                                    '调色',
                                    '色彩平衡',
                                    '裁切',
                                    '局部修图',
                                    '传奇二瞬',
                                    '人像美化',
                                  ][i],
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: tool == i
                                        ? primaryOn(context)
                                        : ink(context),
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
          const SizedBox(height: 16),
          Expanded(
            child: ClipRect(
              child: lgr.LiquidGlassLayer(
                settings: glassSettings(context),
                child: ListView(
                  key: ValueKey(busy ? 'editor-task' : 'editor-tool-$tool'),
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  children: [
                    if (busy)
                      TaskStatusCard(
                        title: token != null ? 'AI 正在处理' : '正在处理照片',
                        stage: activity,
                        seconds: taskSeconds,
                        onCancel: token == null || token!.isCancelled
                            ? null
                            : () {
                                token?.cancel();
                                setState(() => activity = '正在取消任务');
                              },
                      )
                    else
                      IgnorePointer(
                        ignoring: busy,
                        child: switch (tool) {
                          0 => adjustmentControls(),
                          1 => balanceControls(),
                          2 => cropControls(),
                          3 => maskControls(),
                          5 => portraitControls(),
                          _ => lensControls(),
                        },
                      ),
                    const SizedBox(height: 16),
                    Text(
                      '修改以副本保存，原图保留。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: muted(context)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget photoPreview(double height) => SizedBox(
    key: const Key('editor-preview'),
    height: height,
    child: Glass(
      padding: const EdgeInsets.all(7),
      radius: 28,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final ratio = image!.width / image!.height,
                      h = math.min(
                        constraints.maxHeight,
                        constraints.maxWidth / ratio,
                      ),
                      w = h * ratio;
                  return Center(
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: tool == 4 && manualLens && !busy
                            ? (d) => setState(() {
                                focusX = (d.localPosition.dx / w).clamp(0, 1);
                                focusY = (d.localPosition.dy / h).clamp(0, 1);
                              })
                            : null,
                        onPanStart: busy
                            ? null
                            : (d) {
                                if (tool == 3) {
                                  setState(
                                    () => strokes.add(
                                      _Stroke(
                                        [
                                          Offset(
                                            (d.localPosition.dx / w).clamp(
                                              0,
                                              1,
                                            ),
                                            (d.localPosition.dy / h).clamp(
                                              0,
                                              1,
                                            ),
                                          ),
                                        ],
                                        brush,
                                        eraser,
                                      ),
                                    ),
                                  );
                                }
                              },
                        onPanUpdate: busy
                            ? null
                            : (d) => setState(() {
                                if (tool == 3 && strokes.isNotEmpty) {
                                  strokes.last.points.add(
                                    Offset(
                                      (d.localPosition.dx / w).clamp(0, 1),
                                      (d.localPosition.dy / h).clamp(0, 1),
                                    ),
                                  );
                                }
                                if (tool == 2) {
                                  crop = Rect.fromLTWH(
                                    (crop.left + d.delta.dx / w).clamp(
                                      0,
                                      1 - crop.width,
                                    ),
                                    (crop.top + d.delta.dy / h).clamp(
                                      0,
                                      1 - crop.height,
                                    ),
                                    crop.width,
                                    crop.height,
                                  );
                                }
                                if (tool == 4) {
                                  focusX = (d.localPosition.dx / w).clamp(0, 1);
                                  focusY = (d.localPosition.dy / h).clamp(0, 1);
                                }
                              }),
                        child: CustomPaint(
                          size: Size(w, h),
                          painter: _PhotoPainter(
                            image!,
                            compare ? Adjustments() : a,
                            shader,
                          ),
                          foregroundPainter: _OverlayPainter(
                            tool == 4 && !manualLens ? -1 : tool,
                            strokes,
                            crop,
                            Offset(focusX, focusY),
                            focusRadius,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 7),
            child: Row(
              children: [
                Text(
                  '${image!.width} × ${image!.height}',
                  style: TextStyle(color: muted(context), fontSize: 12),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => setState(() => compare = true),
                  onTapUp: (_) => setState(() => compare = false),
                  onTapCancel: () => setState(() => compare = false),
                  child: Row(
                    children: [
                      Icon(
                        Icons.compare_rounded,
                        size: 15,
                        color: muted(context),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        compare ? '原图' : '按住对比',
                        style: TextStyle(fontSize: 12, color: muted(context)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget adjustmentControls() => Column(
    children: [
      Glass(
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  adjustmentNames[adjustment],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    remember();
                    setState(() => a.values[adjustment] = 0);
                  },
                  child: Text(
                    '重置',
                    style: TextStyle(fontSize: 12, color: muted(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GlassSlider(
              value: a.values[adjustment],
              min: adjustment >= 11 ? 0 : -1,
              label: '调整强度',
              onChangeStart: (_) => remember(),
              onChanged: (v) => setState(() => a.values[adjustment] = v),
            ),
            const SizedBox(height: 13),
            SizedBox(
              height: 76 + MediaQuery.textScalerOf(context).scale(18),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: adjustmentNames.length,
                separatorBuilder: (_, _) => const SizedBox(width: 11),
                itemBuilder: (_, i) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => adjustment = i),
                  child: SizedBox(
                    width: math.max(
                      72,
                      MediaQuery.textScalerOf(context).scale(60),
                    ),
                    child: Column(
                      children: [
                        Glass(
                          radius: 99,
                          padding: const EdgeInsets.all(15),
                          tint: i == adjustment ? accent(context) : null,
                          child: Icon(
                            _adjustIcon(i),
                            size: 22,
                            color: i == adjustment
                                ? primaryOn(context)
                                : muted(context),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          adjustmentNames[i],
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            color: i == adjustment
                                ? accentInk(context)
                                : muted(context),
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
      const SectionLabel('影调预设', caption: '从一种感觉开始'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final name in ['原生', '通透', '胶片', '电影', '黑白', '暖阳'])
            GlassButton(
              name,
              small: true,
              onTap: () {
                remember();
                setState(() => a = _preset(name));
              },
            ),
        ],
      ),
    ],
  );

  Widget balanceControls() => Glass(
    blur: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '色彩平衡',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        GlassSegments(
          labels: const ['阴影', '中间调', '高光'],
          selected: balanceRange,
          onChanged: (v) => setState(() => balanceRange = v),
        ),
        const SizedBox(height: 24),
        for (var c = 0; c < 3; c++) ...[
          GlassSlider(
            value: a.balance[balanceRange * 3 + c],
            semanticLabel: ['青色到红色', '洋红到绿色', '黄色到蓝色'][c],
            leftColor: [
              const Color(0xff00cce5),
              const Color(0xffe600be),
              const Color(0xffffd600),
            ][c],
            rightColor: [
              const Color(0xffef383c),
              const Color(0xff13bd62),
              const Color(0xff316bff),
            ][c],
            onChangeStart: (_) => remember(),
            onChanged: (v) =>
                setState(() => a.balance[balanceRange * 3 + c] = v),
          ),
          const SizedBox(height: 22),
        ],
        Row(
          children: [
            GlassCheckbox(
              value: a.preserveLuminosity,
              onChanged: (v) {
                remember();
                setState(() => a.preserveLuminosity = v ?? true);
              },
              activeColor: accentInk(context),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('保持明度', style: TextStyle(fontSize: 14))),
            const SizedBox(width: 16),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                remember();
                setState(() => a.balance = List.filled(9, 0));
              },
              child: Text(
                '重置',
                style: TextStyle(fontSize: 12, color: muted(context)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '独立调整三段明暗的色彩。保持明度可保护颜色调整前的 HSL 亮度。',
          style: TextStyle(fontSize: 12, height: 1.7, color: muted(context)),
        ),
      ],
    ),
  );

  Widget cropControls() => Glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '裁切与旋转',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 6; i++)
              GlassButton(
                ['原图', '1:1', '4:3', '3:2', '16:9', '9:16'][i],
                small: true,
                primary: cropRatio == i,
                onTap: () => ratio(i),
              ),
          ],
        ),
        const SizedBox(height: 20),
        GlassSlider(
          label: '裁切宽度',
          min: .1,
          max: 1,
          value: crop.width,
          onChanged: (v) => setState(
            () => crop = Rect.fromLTWH(
              crop.left.clamp(0, 1 - v),
              crop.top,
              v,
              crop.height,
            ),
          ),
        ),
        GlassSlider(
          label: '裁切高度',
          min: .1,
          max: 1,
          value: crop.height,
          onChanged: (v) => setState(
            () => crop = Rect.fromLTWH(
              crop.left,
              crop.top.clamp(0, 1 - v),
              crop.width,
              v,
            ),
          ),
        ),
        Text(
          '在图片上拖动取景框。',
          style: TextStyle(fontSize: 12, color: muted(context)),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                '旋转 90°',
                small: true,
                icon: Icons.rotate_right_rounded,
                onTap: () => geometry(rotation: 90),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: GlassButton(
                '水平翻转',
                small: true,
                icon: Icons.flip_rounded,
                onTap: () => geometry(flip: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassButton(
          '应用裁切',
          primary: true,
          onTap: () => geometry(applyCrop: true),
        ),
      ],
    ),
  );

  Widget cloudSpecifications() {
    final o = matchedPhotoOptions(image!.width, image!.height, edge: cloudEdge);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: GlassButton(
        '输出规格 · ${o.resolution} · ${o.aspectLabel}',
        small: true,
        icon: Icons.aspect_ratio_rounded,
        onTap: () async {
          final edge = await glassSheet<int>(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '输出规格',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Text(
                  '按原图自动匹配 ${o.aspectLabel} 比例',
                  style: TextStyle(color: muted(context), fontSize: 14),
                ),
                const SizedBox(height: 24),
                for (final k in [1, 2, 4]) ...[
                  GlassButton(
                    '${k}K',
                    primary: o.resolution == '${k}K',
                    onTap: () => Navigator.pop(context, k * 1024),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          );
          if (edge != null && mounted) {
            setState(() => cloudEdge = edge);
          }
        },
      ),
    );
  }

  Widget maskControls() => Glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '局部重绘',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(
          '涂抹画面中的修改区域。生成后仅合成选区，区域外像素保留。',
          style: TextStyle(fontSize: 14, height: 1.7, color: muted(context)),
        ),
        const SizedBox(height: 17),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                eraser ? '橡皮擦' : '画笔',
                small: true,
                icon: eraser
                    ? Icons.auto_fix_normal_rounded
                    : Icons.brush_outlined,
                onTap: () => setState(() => eraser = !eraser),
              ),
            ),
            const SizedBox(width: 8),
            GlassButton(
              '撤笔',
              small: true,
              onTap: () => setState(() {
                if (strokes.isNotEmpty) {
                  strokes.removeLast();
                }
              }),
            ),
            const SizedBox(width: 8),
            GlassButton(
              '清空',
              small: true,
              onTap: () => setState(() => strokes = []),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GlassSlider(
          value: brush,
          label: '画笔大小',
          min: .01,
          max: .25,
          onChanged: (v) => setState(() => brush = v),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: accent(context).withValues(alpha: .055),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              GlassCheckbox(
                value: feather,
                onChanged: (v) => setState(() => feather = v ?? true),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('柔化选区边缘', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final type in ['换装', '换天气', '消除', '修复'])
              GlassButton(
                type,
                small: true,
                onTap: () {
                  editPrompt.text = switch (type) {
                    '换装' => '将选区内的服装替换为黑色剪裁合身的西装，保持人物身份、体态与姿势，匹配原图光照。',
                    '换天气' => '将选区中的天空变为晴朗蓝天与自然云层，匹配画面光照和透视。',
                    '消除' => '自然移除选区中的对象，依据周围纹理、透视与光照无痕修复背景。',
                    _ => '修复选区的瑕疵与破损，恢复自然纹理、细节与光照。',
                  };
                },
              ),
          ],
        ),
        const SizedBox(height: 24),
        GlassField(
          controller: editPrompt,
          hint: '描述选区如何变化…',
          minLines: 3,
          maxLines: 6,
        ),
        const SizedBox(height: 18),
        GlassButton(
          '重新生成选区',
          primary: true,
          icon: Icons.auto_awesome_rounded,
          onTap: busy ? null : () => cloudEdit(),
        ),
        cloudSpecifications(),
        const SizedBox(height: 12),
        Text(
          '需要服务端支持 Images 编辑接口和透明 PNG 蒙版。',
          style: TextStyle(fontSize: 12, height: 1.7, color: muted(context)),
        ),
      ],
    ),
  );

  Widget lensControls() => Glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '传奇二瞬',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        GlassSegments(
          labels: const ['AI 增强', '手动虚化'],
          selected: manualLens ? 1 : 0,
          onChanged: busy ? (_) {} : (i) => setState(() => manualLens = i == 1),
        ),
        const SizedBox(height: 20),
        if (!manualLens) ...[
          Text(
            '电影级明暗层次 · 自然景深',
            style: TextStyle(fontSize: 14, color: muted(context)),
          ),
          const SizedBox(height: 18),
          GlassSegments(
            labels: lensToneNames,
            selected: lensStyle,
            onChanged: (i) => setState(() => lensStyle = i),
          ),
          const SizedBox(height: 22),
          GlassSlider(
            label: '影调强度',
            value: lensStrength,
            min: 0,
            max: 1,
            onChanged: (v) => setState(() => lensStrength = v),
          ),
          const SizedBox(height: 22),
          GlassButton(
            '开始增强',
            primary: true,
            icon: Icons.auto_awesome_rounded,
            onTap: busy ? null : () => cloudEdit(lens: true),
          ),
          const SizedBox(height: 12),
          cloudSpecifications(),
          const SizedBox(height: 12),
          Text(
            '上传兼容尺寸的处理副本，原图保留。',
            style: TextStyle(fontSize: 12, color: muted(context)),
          ),
        ] else ...[
          Text(
            '点选照片中的焦点，实时查看清晰范围。',
            style: TextStyle(fontSize: 14, color: muted(context)),
          ),
          const SizedBox(height: 18),
          GlassSlider(
            value: focusRadius,
            min: .08,
            max: .65,
            label: '清晰范围',
            onChanged: (v) => setState(() => focusRadius = v),
          ),
          const SizedBox(height: 12),
          GlassSlider(
            value: bokehStrength,
            min: .05,
            max: 1,
            label: '虚化强度',
            onChanged: (v) => setState(() => bokehStrength = v),
          ),
          const SizedBox(height: 18),
          GlassButton('应用虚化', primary: true, onTap: busy ? null : applyBokeh),
        ],
      ],
    ),
  );
}

class _PhotoPainter extends CustomPainter {
  final ui.Image image;
  final Adjustments a;
  final ui.FragmentShader? shader;
  _PhotoPainter(this.image, Adjustments adjustments, this.shader)
    : a = adjustments.clone();
  @override
  void paint(Canvas canvas, Size size) {
    if (shader == null || a.isEmpty) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint(),
      );
      return;
    }
    shader!
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, image.width.toDouble())
      ..setFloat(3, image.height.toDouble());
    for (var i = 0; i < 14; i++) {
      shader!.setFloat(4 + i, a.values[i]);
    }
    for (var i = 0; i < 9; i++) {
      shader!.setFloat(18 + i, a.balance[i]);
    }
    shader!
      ..setFloat(27, a.preserveLuminosity ? 1 : 0)
      ..setImageSampler(0, image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PhotoPainter old) =>
      image != old.image ||
      shader != old.shader ||
      !listEquals(a.values, old.a.values) ||
      !listEquals(a.balance, old.a.balance) ||
      a.preserveLuminosity != old.a.preserveLuminosity;
}

class _OverlayPainter extends CustomPainter {
  final int tool;
  final List<_Stroke> strokes;
  final Rect crop;
  final Offset focus;
  final double radius;
  _OverlayPainter(this.tool, this.strokes, this.crop, this.focus, this.radius);
  @override
  void paint(Canvas canvas, Size size) {
    if (tool == 3) {
      canvas.saveLayer(Offset.zero & size, Paint());
      for (final s in strokes) {
        final p = Path()
          ..moveTo(
            s.points.first.dx * size.width,
            s.points.first.dy * size.height,
          );
        if (s.points.length == 1) {
          p.lineTo(
            s.points.first.dx * size.width + .01,
            s.points.first.dy * size.height,
          );
        }
        for (final point in s.points.skip(1)) {
          p.lineTo(point.dx * size.width, point.dy * size.height);
        }
        canvas.drawPath(
          p,
          Paint()
            ..color = const Color(0x8cb4f8bf)
            ..blendMode = s.erase ? BlendMode.clear : BlendMode.srcOver
            ..strokeWidth = s.width * size.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke,
        );
      }
      canvas.restore();
    }
    if (tool == 2) {
      final rect = Rect.fromLTWH(
        crop.left * size.width,
        crop.top * size.height,
        crop.width * size.width,
        crop.height * size.height,
      );
      final outside = Path()
        ..addRect(Offset.zero & size)
        ..addRect(rect)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(outside, Paint()..color = Colors.black54);
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      for (var i = 1; i < 3; i++) {
        canvas.drawLine(
          Offset(rect.left + rect.width * i / 3, rect.top),
          Offset(rect.left + rect.width * i / 3, rect.bottom),
          Paint()..color = Colors.white38,
        );
        canvas.drawLine(
          Offset(rect.left, rect.top + rect.height * i / 3),
          Offset(rect.right, rect.top + rect.height * i / 3),
          Paint()..color = Colors.white38,
        );
      }
    }
    if (tool == 4) {
      final center = Offset(focus.dx * size.width, focus.dy * size.height);
      canvas.drawCircle(
        center,
        radius * math.max(size.width, size.height),
        Paint()
          ..color = Colors.white54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.drawCircle(center, 5, Paint()..color = const Color(0xffc3efbc));
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => true;
}

class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key});
  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  int format = 0, quality = 92;
  bool gallery = true;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '导出',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      const SectionLabel('导出格式'),
      GlassSegments(
        labels: const ['PNG', 'JPEG', 'WebP', 'GIF'],
        selected: format,
        onChanged: (v) => setState(() => format = v),
      ),
      if (format == 1 || format == 2) ...[
        const SizedBox(height: 25),
        GlassSlider(
          value: quality / 100,
          min: .1,
          max: 1,
          label: '压缩质量',
          onChanged: (v) => setState(() => quality = (v * 100).round()),
        ),
      ],
      const SizedBox(height: 16),
      Row(
        children: [
          GlassCheckbox(
            value: gallery,
            onChanged: (v) => setState(() => gallery = v ?? true),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('同时保存到系统相册', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        format == 3 ? '单张照片导出为静态 GIF。多帧动画可在作品页制作。' : '保留当前图片原始分辨率，保存为新副本。',
        style: TextStyle(fontSize: 12, color: muted(context), height: 1.8),
      ),
      const SizedBox(height: 25),
      GlassButton(
        '保存作品',
        primary: true,
        icon: Icons.download_rounded,
        onTap: () => Navigator.pop(context, {
          'format': ['png', 'jpeg', 'webp', 'gif'][format],
          'quality': quality,
          'gallery': gallery,
        }),
      ),
    ],
  );
}

IconData _adjustIcon(int i) => [
  Icons.exposure_rounded,
  Icons.wb_sunny_outlined,
  Icons.highlight_rounded,
  Icons.tonality_rounded,
  Icons.contrast_rounded,
  Icons.brightness_6_outlined,
  Icons.circle_outlined,
  Icons.palette_outlined,
  Icons.color_lens_outlined,
  Icons.thermostat_rounded,
  Icons.water_drop_outlined,
  Icons.details_rounded,
  Icons.vignette_rounded,
  Icons.grain_rounded,
][i];
Adjustments _preset(String name) {
  final a = Adjustments();
  switch (name) {
    case '通透':
      a.values[0] = .12;
      a.values[1] = .25;
      a.values[2] = -.2;
      a.values[3] = .2;
      a.values[8] = .2;
    case '胶片':
      a.values[4] = -.16;
      a.values[6] = -.15;
      a.values[7] = -.12;
      a.values[9] = .17;
      a.values[13] = .3;
      a.balance[2] = .15;
      a.balance[6] = .12;
    case '电影':
      a.values[4] = .16;
      a.values[2] = -.2;
      a.values[7] = -.15;
      a.values[12] = .3;
      a.balance[1] = .1;
      a.balance[2] = .17;
      a.balance[6] = .2;
    case '黑白':
      a.values[7] = -1;
      a.values[4] = .16;
      a.values[12] = .2;
    case '暖阳':
      a.values[9] = .35;
      a.values[0] = .08;
      a.values[3] = .12;
      a.values[8] = .15;
  }
  return a;
}
