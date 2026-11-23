import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'api.dart';
import 'store.dart';

class CloudSticker {
  final String id, name, description, filename, hash;
  final int length, width, height;
  const CloudSticker(
    this.id,
    this.name,
    this.description,
    this.filename,
    this.hash,
    this.length,
    this.width,
    this.height,
  );
  String get localId => 'cloud-$id';
}

class StickerCatalog {
  StickerCatalog(AppStore store, {Dio? dio})
    : source = store.prefs.getString('update_source') ?? 'gitee',
      directory = store.directory,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  final String source;
  final Directory directory;
  final Dio _dio;
  String get base => source == 'github'
      ? 'https://raw.githubusercontent.com/HighnessRK/liuguang/main/community/stickers/'
      : 'https://gitee.com/highnesssrk/liuguang/raw/main/community/stickers/';

  Future<List<CloudSticker>> load({CancelToken? token}) async {
    final bytes = await _fetch('index.json', 512 * 1024, token, fresh: true);
    return parse(utf8.decode(bytes));
  }

  static List<CloudSticker> parse(String encoded) {
    final value = jsonDecode(encoded);
    if (value is! Map || value['schema'] != 1 || value['characters'] is! List) {
      throw StudioException('素材库索引格式无法读取');
    }
    final ids = <String>{};
    final entries = <CloudSticker>[];
    for (final row in value['characters'] as List) {
      if (row is! Map) continue;
      final id = row['id'], name = row['name'], desc = row['description'];
      final file = row['file'], sha = row['sha256'], length = row['bytes'];
      final w = row['width'], h = row['height'];
      if (id is! String ||
          !RegExp(r'^[a-z0-9-]{1,64}$').hasMatch(id) ||
          name is! String ||
          name.trim().isEmpty ||
          name.length > 80 ||
          desc is! String ||
          desc.trim().isEmpty ||
          desc.length > 10000 ||
          file is! String ||
          !RegExp(r'^[a-z0-9-]{1,64}\.webp$').hasMatch(file) ||
          sha is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
          length is! int ||
          length <= 0 ||
          length > 8 * 1024 * 1024 ||
          w is! int ||
          h is! int ||
          w <= 0 ||
          h <= 0 ||
          w > 4096 ||
          h > 4096 ||
          !ids.add(id))
        continue;
      entries.add(CloudSticker(id, name, desc, file, sha, length, w, h));
    }
    if (entries.isEmpty && (value['characters'] as List).isNotEmpty) {
      throw StudioException('素材库没有可读取的角色');
    }
    return entries;
  }

  Future<String> download(CloudSticker item, {CancelToken? token}) async {
    final bytes = await _fetch(item.filename, item.length, token);
    if (!await compute(_verifySticker, (bytes, item))) {
      throw StudioException('角色素材校验失败，请刷新素材库后重试');
    }
    if (token?.isCancelled == true) throw token!.cancelError!;
    final folder = await Directory('${directory.path}/sticker_refs')
        .create(recursive: true);
    final file = File(
      '${folder.path}/${item.localId}-${item.hash.substring(0, 12)}.webp',
    );
    final temp = await File('${file.path}.tmp')
        .writeAsBytes(bytes, flush: true);
    return (await temp.rename(file.path)).path;
  }

  Future<Uint8List> _fetch(
    String file,
    int limit,
    CancelToken? token, {
    bool fresh = false,
  }) async {
    final response = await _dio.get<ResponseBody>(
      '$base$file',
      queryParameters: fresh
          ? {'refresh': DateTime.now().millisecondsSinceEpoch ~/ 30000}
          : null,
      options: Options(responseType: ResponseType.stream),
      cancelToken: token,
    );
    final buffer = BytesBuilder(copy: false);
    await for (final part in response.data!.stream) {
      if (part.length + buffer.length > limit)
        throw StudioException('素材文件大小超出限制');
      buffer.add(part);
    }
    return buffer.takeBytes();
  }

  void close() => _dio.close(force: true);
}

bool _verifySticker((Uint8List, CloudSticker) job) {
  final (data, item) = job;
  if (data.length != item.length ||
      sha256.convert(data).toString() != item.hash)
    return false;
  final info = img.WebPDecoder().startDecode(data);
  return info != null && info.width == item.width && info.height == item.height;
}
