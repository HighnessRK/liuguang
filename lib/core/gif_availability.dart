import 'dart:convert';

import 'package:dio/dio.dart';

const gifUnavailableMessage = 'GIF 生成测试中，暂不支持使用';

Future<bool> fetchGifAvailability(String source, {Dio? client}) async {
  final github = source == 'github';
  final dio =
      client ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );
  try {
    final response = await dio.get<ResponseBody>(
      github
          ? 'https://api.github.com/repos/HighnessRK/liuguang/contents/config/gif-availability.json'
          : 'https://gitee.com/highnesssrk/liuguang/raw/main/config/gif-availability.json',
      queryParameters: {
        if (github) 'ref': 'main',
        'refresh': DateTime.now().millisecondsSinceEpoch ~/ 60000,
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Cache-Control': 'no-cache',
          if (github) 'Accept': 'application/vnd.github.raw+json',
        },
      ),
    );
    final bytes = <int>[];
    final stream = response.data?.stream;
    if (stream == null) return false;
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 1024) return false;
      bytes.addAll(chunk);
    }
    final config = jsonDecode(utf8.decode(bytes));
    return config is Map && config['enabled'] == true;
  } catch (_) {
    return false;
  } finally {
    if (client == null) dio.close(force: true);
  }
}
