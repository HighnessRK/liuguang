import 'dart:convert';

enum ApiProtocol { images, gptImage, dalle, chatImage }

class EndpointConfig {
  String baseUrl;
  String key;
  String model;
  List<String> models;
  ApiProtocol protocol;
  double inputPrice;
  double outputPrice;
  double imagePrice;
  EndpointConfig({
    this.baseUrl = '',
    this.key = '',
    this.model = '',
    List<String>? models,
    this.protocol = ApiProtocol.images,
    this.inputPrice = 0,
    this.outputPrice = 0,
    this.imagePrice = 0,
  }) : models = models ?? [];
  bool get ready => baseUrl.isNotEmpty && key.isNotEmpty && model.isNotEmpty;
  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'model': model,
    'models': models,
    'protocol': protocol.name,
    'inputPrice': inputPrice,
    'outputPrice': outputPrice,
    'imagePrice': imagePrice,
  };
  factory EndpointConfig.fromJson(Map<String, dynamic> j) => EndpointConfig(
    baseUrl: j['baseUrl'] ?? '',
    model: j['model'] ?? '',
    models: List<String>.from(j['models'] ?? []),
    protocol: ApiProtocol.values.firstWhere(
      (p) => p.name == j['protocol'],
      orElse: () => ApiProtocol.images,
    ),
    inputPrice: (j['inputPrice'] as num?)?.toDouble() ?? 0,
    outputPrice: (j['outputPrice'] as num?)?.toDouble() ?? 0,
    imagePrice: (j['imagePrice'] as num?)?.toDouble() ?? 0,
  );
  EndpointConfig snapshot() => EndpointConfig.fromJson(toJson())..key = key;
}

GenerationOptions photoOutputOptions(int width, int height) {
  final scale = 1024 / (width > height ? width : height);
  return GenerationOptions(
    width: ((width * scale / 16).round() * 16).clamp(64, 8192),
    height: ((height * scale / 16).round() * 16).clamp(64, 8192),
  );
}

class GenerationOptions {
  int width, height, count, compression;
  String quality, format, moderation;
  GenerationOptions({
    this.width = 1024,
    this.height = 1024,
    this.count = 1,
    this.compression = 90,
    this.quality = 'high',
    this.format = 'png',
    this.moderation = 'auto',
  });
  String get size => '${width}x$height';
  String get aspectLabel {
    const ratios = [(1, 1), (3, 4), (4, 3), (2, 3), (3, 2), (9, 16), (16, 9)];
    final sorted = ratios.toList()
      ..sort(
        (a, b) => (width / height - a.$1 / a.$2).abs().compareTo(
          (width / height - b.$1 / b.$2).abs(),
        ),
      );
    return '${sorted.first.$1}:${sorted.first.$2}';
  }

  String get displaySize => '$width × $height';
  String get resolution =>
      '${((width > height ? width : height) / 1024).round()}K';
  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'count': count,
    'compression': compression,
    'quality': quality,
    'format': format,
    'moderation': moderation,
  };
  factory GenerationOptions.fromJson(Map<String, dynamic> j) =>
      GenerationOptions(
        width: j['width'] ?? 1024,
        height: j['height'] ?? 1024,
        count: j['count'] ?? 1,
        compression: j['compression'] ?? 90,
        quality: j['quality'] ?? 'high',
        format: j['format'] ?? 'png',
        moderation: j['moderation'] ?? 'auto',
      );
}

class Artwork {
  final String id, path, prompt, model, kind;
  final DateTime created;
  final int width, height;
  bool favorite;
  Artwork({
    required this.id,
    required this.path,
    required this.prompt,
    required this.model,
    required this.kind,
    required this.created,
    required this.width,
    required this.height,
    this.favorite = false,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'prompt': prompt,
    'model': model,
    'kind': kind,
    'created': created.toIso8601String(),
    'width': width,
    'height': height,
    'favorite': favorite,
  };
  factory Artwork.fromJson(Map<String, dynamic> j) => Artwork(
    id: j['id'],
    path: j['path'],
    prompt: j['prompt'],
    model: j['model'],
    kind: j['kind'],
    created: DateTime.parse(j['created']),
    width: j['width'],
    height: j['height'],
    favorite: j['favorite'] ?? false,
  );
}

class UsageRecord {
  final String id, model, operation;
  final DateTime time;
  final int milliseconds, images;
  final int? inputTokens, outputTokens;
  final bool success;
  final double? estimatedCost;
  final String? error;
  UsageRecord({
    required this.id,
    required this.model,
    required this.operation,
    required this.time,
    required this.milliseconds,
    this.images = 0,
    this.inputTokens,
    this.outputTokens,
    required this.success,
    this.estimatedCost,
    this.error,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'model': model,
    'operation': operation,
    'time': time.toIso8601String(),
    'milliseconds': milliseconds,
    'images': images,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'success': success,
    'estimatedCost': estimatedCost,
    'error': error,
  };
  factory UsageRecord.fromJson(Map<String, dynamic> j) => UsageRecord(
    id: j['id'],
    model: j['model'],
    operation: j['operation'],
    time: DateTime.parse(j['time']),
    milliseconds: j['milliseconds'],
    images: j['images'] ?? 0,
    inputTokens: j['inputTokens'],
    outputTokens: j['outputTokens'],
    success: j['success'],
    estimatedCost: (j['estimatedCost'] as num?)?.toDouble(),
    error: j['error'],
  );
}

class ChatMessage {
  final String role, text;
  ChatMessage(this.role, this.text);
  Map<String, String> toJson() => {'role': role, 'content': text};
  factory ChatMessage.fromJson(Map<String, dynamic> j) =>
      ChatMessage(j['role'], j['content']);
}

String prettyJson(Object value) =>
    const JsonEncoder.withIndent('  ').convert(value);
