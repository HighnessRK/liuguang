import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liuguang/core/store.dart';
import 'package:liuguang/core/updates.dart';

class ReleaseAdapter implements HttpClientAdapter {
  RequestOptions? last;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    final values = [
      {'tag_name': 'v2.0.0', 'prerelease': true},
      {
        'tag_name': 'v1.1.0',
        'body': '更新说明',
        'assets': [
          {
            'name': 'liuguang.apk',
            'browser_download_url': 'https://example.org/liuguang.apk',
            'size': 123,
          },
        ],
      },
      {'tag_name': 'v1.0.0', 'assets': []},
    ];
    return ResponseBody.fromString(
      jsonEncode(values),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('version prefixes, missing components and numeric ordering', () {
    expect(compareVersions('v1.0', '1.0.0'), 0);
    expect(compareVersions('V1.10.0', '1.9.9'), greaterThan(0));
    expect(compareVersions('1.0.0', '2.0.0'), lessThan(0));
  });
  test('Gitee attachment variants remain downloadable', () {
    final release = ReleaseInfo.parse({
      'tag_name': 'v1.0.1',
      'attachments': [
        {'name': 'app.apk', 'download_url': 'https://gitee.com/file.apk'},
      ],
    }, 'gitee');
    expect(release.apk, 'https://gitee.com/file.apk');
  });
  test(
    'update source respects preferences, ignores previews and sends no auth',
    () async {
      SharedPreferences.setMockInitialValues({'update_source': 'gitee'});
      final store = AppStore()..prefs = await SharedPreferences.getInstance();
      final adapter = ReleaseAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final release = await UpdateService(store, client: dio).check();
      expect(release!.version, 'v1.1.0');
      expect(adapter.last!.uri.host, 'gitee.com');
      expect(
        adapter.last!.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    },
  );
  test(
    'diagnostics reject arbitrary content and retain bounded history',
    () async {
      final directory = await Directory.systemTemp.createTemp('liuguang_logs_');
      try {
        await AppLog.init(directory);
        await AppLog.record('api_key=should_not_appear');
        for (var i = 0; i < 305; i++) {
          await AppLog.record('test_event', status: i);
        }
        final content = await AppLog.read();
        expect(content, isNot(contains('should_not_appear')));
        expect(const LineSplitter().convert(content).length, 300);
        await AppLog.clear();
        expect(await AppLog.read(), isEmpty);
      } finally {
        AppLog.file = null;
        await directory.delete(recursive: true);
      }
    },
  );
}
