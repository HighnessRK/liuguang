import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'api.dart';
import 'models.dart';
import 'store.dart';

const adjustmentNames = [
  '曝光',
  '鲜明度',
  '高光',
  '阴影',
  '对比度',
  '亮度',
  '黑点',
  '饱和度',
  '自然饱和度',
  '色温',
  '色调',
  '锐度',
  '暗角',
  '颗粒',
];

class Adjustments {
  List<double> values;
  List<double> balance;
  bool preserveLuminosity;
  Adjustments({
    List<double>? values,
    List<double>? balance,
    this.preserveLuminosity = true,
  }) : values = values ?? List.filled(14, 0),
       balance = balance ?? List.filled(9, 0);
  Adjustments clone() => Adjustments(
    values: [...values],
    balance: [...balance],
    preserveLuminosity: preserveLuminosity,
  );
  Map<String, dynamic> toJson() => {
    'values': values,
    'balance': balance,
    'preserve': preserveLuminosity,
  };
  factory Adjustments.fromJson(Map<String, dynamic> j) => Adjustments(
    values: List<double>.from(j['values']),
    balance: List<double>.from(j['balance']),
    preserveLuminosity: j['preserve'],
  );
  bool get isEmpty =>
      values.every((v) => v == 0) && balance.every((v) => v == 0);
}

double _clamp(double v) => v.clamp(0.0, 1.0);
double _smooth(double a, double b, double x) {
  final t = _clamp((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

// Original RGB/HSL implementation; same operations and order as adjustments.frag.
List<double> adjustPixel(
  double r,
  double g,
  double b,
  Adjustments a, {
  double x = .5,
  double y = .5,
}) {
  final v = a.values;
  final exposure = math.pow(2, v[0] * 2).toDouble();
  r *= exposure;
  g *= exposure;
  b *= exposure;
  var l = .2126 * r + .7152 * g + .0722 * b;
  final tone =
      v[2] * .35 * _smooth(.35, 1, l) +
      v[3] * .35 * (1 - _smooth(0, .65, l)) +
      v[1] * .2 * (1 - (2 * l - 1).abs());
  final contrast = 1 + v[4] * .8;
  r =
      ((r + tone - .5) * contrast +
          .5 +
          v[5] * .25 -
          v[6] * .2 * (1 - _clamp(l))) *
      (1 + v[9] * .16);
  g =
      ((g + tone - .5) * contrast +
          .5 +
          v[5] * .25 -
          v[6] * .2 * (1 - _clamp(l))) *
      (1 - v[10] * .12);
  b =
      ((b + tone - .5) * contrast +
          .5 +
          v[5] * .25 -
          v[6] * .2 * (1 - _clamp(l))) *
      (1 - v[9] * .16);
  l = .2126 * r + .7152 * g + .0722 * b;
  final chroma = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
  final sat = 1 + v[7] + v[8] * (1 - _clamp(chroma)) * .75;
  r = l + (r - l) * sat;
  g = l + (g - l) * sat;
  b = l + (b - l) * sat;
  final before =
      (math.max(r, math.max(g, b)) + math.min(r, math.min(g, b))) / 2;
  final weights = [
    1 - _smooth(0, .5, l),
    1 - (2 * _clamp(l) - 1).abs(),
    _smooth(.5, 1, l),
  ];
  for (var i = 0; i < 3; i++) {
    r += a.balance[i * 3] * weights[i] * .25;
    g += a.balance[i * 3 + 1] * weights[i] * .25;
    b += a.balance[i * 3 + 2] * weights[i] * .25;
  }
  r = _clamp(r);
  g = _clamp(g);
  b = _clamp(b);
  if (a.preserveLuminosity) {
    final maxC = math.max(r, math.max(g, b)),
        minC = math.min(r, math.min(g, b));
    final oldL = (maxC + minC) / 2;
    final delta = maxC - minC;
    final saturation = delta < .000001
        ? 0.0
        : delta / (1 - (2 * oldL - 1).abs()).clamp(.000001, 1);
    final newL = _clamp(before), newC = (1 - (2 * newL - 1).abs()) * saturation;
    if (delta > .000001) {
      r = (r - minC) / delta * newC + newL - newC / 2;
      g = (g - minC) / delta * newC + newL - newC / 2;
      b = (b - minC) / delta * newC + newL - newC / 2;
    } else {
      r = newL;
      g = newL;
      b = newL;
    }
  }
  final distance = math.sqrt(math.pow(x - .5, 2) + math.pow(y - .5, 2));
  final vignette = 1 - v[12] * .75 * _smooth(.15, .72, distance);
  final hash = math.sin(x * 1234.5 + y * 7654.3) * 43758.5453;
  final grain = (hash - hash.floor() - .5) * v[13] * .12;
  return [
    _clamp(r * vignette + grain),
    _clamp(g * vignette + grain),
    _clamp(b * vignette + grain),
  ];
}

Map<String, dynamic> processImage(Map<String, dynamic> job) {
  img.Decoder.defaultMaxPixels = 48000000;
  var source = img.decodeImage(job['bytes'] as Uint8List);
  if (source == null) {
    throw StudioException('无法解码该图片，请使用 PNG、JPEG、WebP 或 GIF');
  }
  if (source.width * source.height > 48000000) {
    throw StudioException('图片超过 4800 万像素，请先缩小');
  }
  source = img.bakeOrientation(source);
  final edge = job['maxEdge'] as int?;
  if (edge != null && (source.width > edge || source.height > edge)) {
    final scale = edge / math.max(source.width, source.height);
    source = img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }
  final a = Adjustments.fromJson(job['adjustments']);
  if (!a.isEmpty) {
    final original = a.values[11] != 0 ? source.clone() : null;
    for (final p in source) {
      var r = p.r.toDouble() / 255,
          g = p.g.toDouble() / 255,
          b = p.b.toDouble() / 255;
      if (original != null) {
        final left = original.getPixel(
          (p.x - 1).clamp(0, source.width - 1),
          p.y,
        );
        final right = original.getPixel(
          (p.x + 1).clamp(0, source.width - 1),
          p.y,
        );
        final up = original.getPixel(
          p.x,
          (p.y - 1).clamp(0, source.height - 1),
        );
        final down = original.getPixel(
          p.x,
          (p.y + 1).clamp(0, source.height - 1),
        );
        r += (r - (left.r + right.r + up.r + down.r) / 1020) * a.values[11] * 2;
        g += (g - (left.g + right.g + up.g + down.g) / 1020) * a.values[11] * 2;
        b += (b - (left.b + right.b + up.b + down.b) / 1020) * a.values[11] * 2;
      }
      final rgb = adjustPixel(
        r,
        g,
        b,
        a,
        x: (p.x + .5) / source.width,
        y: (p.y + .5) / source.height,
      );
      p.r = (rgb[0] * 255).round();
      p.g = (rgb[1] * 255).round();
      p.b = (rgb[2] * 255).round();
    }
  }
  if (job['crop'] != null) {
    final c = List<double>.from(job['crop']);
    final x = (c[0] * source.width).round().clamp(0, source.width - 1);
    final y = (c[1] * source.height).round().clamp(0, source.height - 1);
    source = img.copyCrop(
      source,
      x: x,
      y: y,
      width: (c[2] * source.width).round().clamp(1, source.width - x),
      height: (c[3] * source.height).round().clamp(1, source.height - y),
    );
  }
  if ((job['rotation'] ?? 0) != 0) {
    source = img.copyRotate(source, angle: job['rotation']);
  }
  if (job['flip'] == true) {
    source = img.flipHorizontal(source);
  }
  final format = job['format'] ?? 'png';
  final quality = (job['quality'] ?? 90) as int;
  final bytes = switch (format) {
    'jpeg' => img.encodeJpg(source, quality: quality),
    'gif' => img.encodeGif(source),
    _ => img.encodePng(source),
  };
  return {'bytes': bytes, 'width': source.width, 'height': source.height};
}

Future<Map<String, dynamic>> renderEdited(
  String path,
  Adjustments a, {
  String format = 'png',
  int quality = 90,
  List<double>? crop,
  int rotation = 0,
  bool flip = false,
  int? maxEdge,
}) async {
  final result = await compute(processImage, {
    'bytes': await File(path).readAsBytes(),
    'adjustments': a.toJson(),
    'format': format,
    'quality': quality,
    'crop': crop,
    'rotation': rotation,
    'flip': flip,
    'maxEdge': maxEdge,
  });
  if (format == 'webp') {
    result['bytes'] = await native.invokeMethod<Uint8List>('encodeWebp', {
      'bytes': result['bytes'],
      'quality': quality,
    });
  }
  return result;
}

Future<Artwork> saveArtwork(
  AppStore store,
  Uint8List bytes, {
  required String prompt,
  required String model,
  required String kind,
  int? modelWidth,
  int? modelHeight,
  String? format,
  int quality = 90,
}) async {
  var extension = imageExtension(bytes);
  final result = await compute(imageDimensions, bytes);
  // Preserve server's original bytes unless an explicit export format is requested.
  if (format != null &&
      format != extension &&
      !(format == 'jpeg' && extension == 'jpg')) {
    final converted = await compute(processImage, {
      'bytes': bytes,
      'adjustments': Adjustments().toJson(),
      'format': format,
      'quality': quality,
    });
    bytes = converted['bytes'];
    extension = format == 'jpeg' ? 'jpg' : format;
    if (format == 'webp') {
      bytes = (await native.invokeMethod<Uint8List>('encodeWebp', {
        'bytes': bytes,
        'quality': quality,
      }))!;
    }
  }
  final path = await store.writeImage(bytes, extension);
  final art = Artwork(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    path: path,
    prompt: prompt,
    model: model,
    kind: kind,
    created: DateTime.now(),
    width: result['width']!,
    height: result['height']!,
    modelWidth: modelWidth,
    modelHeight: modelHeight,
  );
  store.artworks.insert(0, art);
  await store.saveCatalog();
  return art;
}

Uint8List encodeAnimation(Map<String, dynamic> job) {
  img.Decoder.defaultMaxPixels = 48000000;
  final frames = (job['frames'] as List).cast<Uint8List>();
  final encoder = img.GifEncoder(repeat: 0, numColors: job['colors'] ?? 256);
  img.Image? first;
  for (final bytes in frames) {
    var frame = img.decodeImage(bytes);
    if (frame == null) {
      throw StudioException('GIF 中有一帧无法读取');
    }
    frame = img.bakeOrientation(frame);
    first ??= frame;
    if (frame.width != first.width || frame.height != first.height) {
      frame = img.copyResize(
        frame,
        width: first.width,
        height: first.height,
        maintainAspect: true,
        backgroundColor: img.ColorRgb8(0, 0, 0),
      );
    }
    encoder.addFrame(frame, duration: ((job['duration'] as int) / 10).round());
  }
  return encoder.finish()!;
}

Map<String, int> imageDimensions(Uint8List bytes) {
  img.Decoder.defaultMaxPixels = 48000000;
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null) {
    throw StudioException('无法识别图片格式，请使用 PNG、JPEG、WebP 或 GIF');
  }
  if (info.width * info.height > 48000000) {
    throw StudioException('图片超过 4800 万像素，请先缩小');
  }
  if (imageExtension(bytes) == 'jpg') {
    final frame = decoder!.decodeFrame(0);
    if (frame != null &&
        frame.exif.imageIfd.hasOrientation &&
        [5, 6, 7, 8].contains(frame.exif.imageIfd.orientation)) {
      return {'width': info.height, 'height': info.width};
    }
  }
  return {'width': info.width, 'height': info.height};
}

Uint8List localBokeh(Map<String, dynamic> job) {
  var source = img.decodeImage(job['bytes']);
  if (source == null) {
    throw StudioException('无法读取图片');
  }
  source = img.bakeOrientation(source);
  final strength = job['strength'] as double;
  var small = img.copyResize(source, width: math.min(640, source.width));
  small = img.gaussianBlur(small, radius: (strength * 18).round().clamp(1, 24));
  final blurred = img.copyResize(
    small,
    width: source.width,
    height: source.height,
    interpolation: img.Interpolation.linear,
  );
  final cx = job['x'] as double, cy = job['y'] as double;
  final radius = job['radius'] as double;
  for (final p in source) {
    final dx =
        (p.x / source.width - cx) *
        source.width /
        math.max(source.width, source.height);
    final dy =
        (p.y / source.height - cy) *
        source.height /
        math.max(source.width, source.height);
    final mix = _smooth(radius * .45, radius, math.sqrt(dx * dx + dy * dy));
    final q = blurred.getPixel(p.x, p.y);
    p.r = (p.r * (1 - mix) + q.r * mix).round();
    p.g = (p.g * (1 - mix) + q.g * mix).round();
    p.b = (p.b * (1 - mix) + q.b * mix).round();
  }
  return img.encodePng(source);
}

Uint8List compositeMasked(Map<String, dynamic> job) {
  final original = img.decodeImage(job['original']);
  var generated = img.decodeImage(job['generated']);
  final mask = img.decodeImage(job['mask']);
  if (original == null || generated == null || mask == null) {
    throw StudioException('无法合成局部修图结果');
  }
  if (mask.width != original.width || mask.height != original.height) {
    throw StudioException('蒙版尺寸与原图不一致');
  }
  if (generated.width != original.width ||
      generated.height != original.height) {
    generated = img.copyResize(
      generated,
      width: original.width,
      height: original.height,
      interpolation: img.Interpolation.linear,
    );
  }
  for (final p in original) {
    final weight = 1 - mask.getPixel(p.x, p.y).a / 255;
    if (weight <= 0) {
      continue;
    }
    final q = generated.getPixel(p.x, p.y);
    p.r = (p.r * (1 - weight) + q.r * weight).round();
    p.g = (p.g * (1 - weight) + q.g * weight).round();
    p.b = (p.b * (1 - weight) + q.b * weight).round();
  }
  return img.encodePng(original);
}

const lensPrompt =
    '对第一张原图进行具有明确电影影调的相机级景深增强。严格保持主体身份、面部、发丝、服饰、动作、物体数量、画面文字、拍摄视角和构图。建立有层次的黑位、柔和滚降的高光、丰富的中间调与立体局部反差，避免平淡灰雾和过曝；让肤色自然，色彩有明确但克制的冷暖分离。依据真实空间的遮挡关系推断深度，仅对离焦区域施加连续、渐进、符合光学的景深虚化，保护焦内主体与边缘。自然保留高光光斑、前景和背景的层次过渡，不制造剪纸轮廓。保留原始细节、纹理和动态范围，不擅自美颜、不添加元素。输出高质量图像。';

const lensToneNames = ['经典电影', '暖调人像', '冷峻青蓝'];

Adjustments lensTone(int style, double strength) {
  final s = strength.clamp(0.0, 1.0);
  final tone = Adjustments();
  tone.values[1] = .18 * s;
  tone.values[2] = -.24 * s;
  tone.values[3] = .12 * s;
  tone.values[4] = .30 * s;
  tone.values[6] = .16 * s;
  tone.values[7] = -.08 * s;
  tone.values[8] = .15 * s;
  tone.values[12] = .12 * s;
  tone.values[9] =
      (style == 1
          ? 0.20
          : style == 2
          ? -0.12
          : 0.05) *
      s;
  tone.balance[0] = -.09 * s;
  tone.balance[2] = .06 * s;
  tone.balance[6] = (style == 2 ? -0.025 : 0.08) * s;
  tone.balance[8] = -.07 * s;
  return tone;
}

Map<String, dynamic> finishLensImage(Map<String, dynamic> job) {
  final modelSize = imageDimensions(job['bytes'] as Uint8List);
  final toned = processImage({
    'bytes': job['bytes'],
    'format': 'png',
    'adjustments': lensTone(
      job['style'] as int,
      job['strength'] as double,
    ).toJson(),
  });
  var bytes = toned['bytes'] as Uint8List;
  if (job['width'] != null && job['height'] != null) {
    final width = job['width'] as int, height = job['height'] as int;
    if (width < 1 || height < 1 || width * height > 48000000) {
      throw StudioException('原尺寸超过本机处理范围');
    }
    final decoded = img.decodePng(bytes)!;
    if (decoded.width != width || decoded.height != height) {
      bytes = img.encodePng(
        img.copyResize(
          decoded,
          width: width,
          height: height,
          interpolation: img.Interpolation.cubic,
        ),
      );
    }
  }
  return {
    'bytes': bytes,
    'modelWidth': modelSize['width'],
    'modelHeight': modelSize['height'],
  };
}
