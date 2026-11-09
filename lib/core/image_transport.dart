import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Only the upload copy is reduced. Source files and local exports are intact.
/// PNG alpha and mask/source dimensions must remain aligned.
Map<String, dynamic> prepareImageInput(Map<String, dynamic> job) {
  img.Decoder.defaultMaxPixels = 48000000;
  final original = job['bytes'] as Uint8List;
  final decoded = img.decodeImage(original);
  if (decoded == null) throw FormatException('无法解码上传图片，请重新选择 PNG、JPEG 或 WebP');
  var image = img.bakeOrientation(decoded);
  final edge = (job['maxEdge'] ?? 2048) as int;
  final budget = (job['maxBytes'] ?? 3 * 1024 * 1024) as int;
  img.Image? mask;
  if (job['mask'] != null) {
    mask = img.decodePng(job['mask'] as Uint8List);
    if (mask == null ||
        mask.width != image.width ||
        mask.height != image.height) {
      throw FormatException('蒙版与底图尺寸不一致，请重新创建选区');
    }
  }
  final png =
      mask != null ||
      image.hasAlpha ||
      (original.length > 8 && original[0] == 137 && original[1] == 80);
  var width = image.width, height = image.height;
  if (width > edge || height > edge) {
    final scale = edge / (width > height ? width : height);
    width = (width * scale).round();
    height = (height * scale).round();
    image = img.copyResize(
      image,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );
  }
  Uint8List bytes = png
      ? img.encodePng(image)
      : img.encodeJpg(image, quality: 92);
  while (bytes.length > budget && image.width > 128 && image.height > 128) {
    image = img.copyResize(
      image,
      width: (image.width * .8).round(),
      height: (image.height * .8).round(),
      interpolation: img.Interpolation.average,
    );
    bytes = png ? img.encodePng(image) : img.encodeJpg(image, quality: 90);
  }
  if (bytes.length > budget) throw FormatException('图片仍超过上传限制，请缩小后重试');
  return {
    'bytes': bytes,
    'extension': png ? 'png' : 'jpg',
    'width': image.width,
    'height': image.height,
    if (mask != null)
      'mask': img.encodePng(
        img.copyResize(
          mask,
          width: image.width,
          height: image.height,
          interpolation: img.Interpolation.linear,
        ),
      ),
  };
}

bool matchesRequestedAspect(
  int width,
  int height,
  int requestedWidth,
  int requestedHeight,
) => (width / height / (requestedWidth / requestedHeight) - 1).abs() <= .03;
