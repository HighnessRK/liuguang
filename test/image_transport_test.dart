import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:liuguang/core/api.dart';
import 'package:liuguang/core/image_transport.dart';
import 'package:liuguang/core/models.dart';
import 'package:liuguang/core/store.dart';

class TestStore extends AppStore {
  @override
  Future<void> addUsage(UsageRecord record) async {
    usage.add(record);
  }
}

class TaskAdapter implements HttpClientAdapter {
  final List<RequestOptions> calls = [];
  final Uint8List png;
  final bool disabled, failed;
  int polls = 0;
  TaskAdapter(this.png, {this.disabled = false, this.failed = false});
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    await stream?.drain<void>();
    dynamic value;
    var status = 200;
    if (failed) {
      status = 401;
      value = {
        'error': {'message': 'unauthorized'},
      };
    } else if (options.uri.path.endsWith('/async')) {
      if (disabled) {
        status = 400;
        value = {
          'error': {'message': 'async image tasks are not enabled'},
        };
      } else {
        value = {
          'id': 'imgtask_fixture',
          'poll_url': 'https://untrusted.example/never-send-auth',
        };
      }
    } else if (options.uri.path.contains('/tasks/')) {
      polls++;
      value = polls == 1
          ? {'status': 'processing'}
          : {
              'status': 'completed',
              'result': {
                'data': [
                  {'b64_json': base64Encode(png)},
                ],
                'usage': {'input_tokens': 8, 'output_tokens': 4},
              },
            };
    } else {
      value = {
        'data': [
          {'b64_json': base64Encode(png)},
        ],
      };
    }
    return ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final png = img.encodePng(img.Image(width: 48, height: 32, numChannels: 4));
  TestStore makeStore() => TestStore()
    ..imageApi = EndpointConfig(
      baseUrl: 'https://www.sui-xiang.net/v1',
      key: 'test-only-secret',
      model: 'gpt-image-2.6-sunburst',
    );
  test('8K upload becomes a bounded, decodable copy', () {
    final large = img.encodeJpg(
      img.Image(width: 7680, height: 4320),
      quality: 90,
    );
    final prepared = prepareImageInput({'bytes': large});
    final decoded = img.decodeImage(prepared['bytes'])!;
    expect(decoded.width, lessThanOrEqualTo(2048));
    expect(decoded.height, lessThanOrEqualTo(2048));
    expect(
      (prepared['bytes'] as Uint8List).length,
      lessThanOrEqualTo(3 * 1024 * 1024),
    );
    expect(decoded.width / decoded.height, closeTo(16 / 9, .01));
  });
  test('mask and input copies have identical dimensions and valid alpha', () {
    final mask = img.Image(width: 48, height: 32, numChannels: 4);
    img.fill(mask, color: img.ColorRgba8(255, 255, 255, 255));
    mask.setPixelRgba(10, 10, 0, 0, 0, 0);
    final result = prepareImageInput({
      'bytes': png,
      'mask': img.encodePng(mask),
      'maxEdge': 24,
    });
    final image = img.decodePng(result['bytes'])!,
        outputMask = img.decodePng(result['mask'])!;
    expect(image.width, outputMask.width);
    expect(image.height, outputMask.height);
    expect(outputMask.hasAlpha, isTrue);
  });
  test('invalid image data fails before any charged request', () async {
    final dir = await Directory.systemTemp.createTemp('invalid_input_');
    try {
      final path = File('${dir.path}/broken.png');
      await path.writeAsString('not image bytes');
      final adapter = TaskAdapter(png), store = makeStore();
      await expectLater(
        StudioApi(store, dio: Dio()..httpClientAdapter = adapter).generate(
          prompt: 'test',
          options: GenerationOptions(),
          inputs: [path.path],
        ),
        throwsA(isA<StudioException>()),
      );
      expect(adapter.calls, isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('portrait request uses width first, explicit composition, and one async task', () async {
    final adapter = TaskAdapter(png), store = makeStore();
    final stages = <String>[];
    final reply =
        await StudioApi(
          store,
          dio: Dio()..httpClientAdapter = adapter,
          pollInterval: const Duration(milliseconds: 1),
        ).generate(
          prompt: '用户原文',
          options: GenerationOptions(width: 768, height: 1024, quality: 'low'),
          onStage: stages.add,
        );
    final body = adapter.calls.first.data as Map;
    expect(body['size'], '768x1024');
    expect(body['prompt'], startsWith('用户原文'));
    expect(body['prompt'], contains('宽:高=3:4'));
    expect(body['complexity'], 'low');
    expect(adapter.calls.where((v) => v.method == 'POST').length, 1);
    expect(
      adapter.calls.every((v) => v.uri.host == 'www.sui-xiang.net'),
      isTrue,
    );
    expect(reply.images.single, png);
    expect(store.usage.single.inputTokens, 8);
    expect(stages, contains('模型正在处理，请稍候'));
    expect(matchesRequestedAspect(1024, 768, 768, 1024), isFalse);
  });
  test(
    'accepted tasks are not resubmitted after cancellation or auth failure',
    () async {
      final store = makeStore(),
          adapter = TaskAdapter(png),
          token = CancelToken();
      await expectLater(
        StudioApi(
          store,
          dio: Dio()..httpClientAdapter = adapter,
          pollInterval: const Duration(seconds: 3),
        ).generate(
          prompt: 'test',
          options: GenerationOptions(),
          cancelToken: token,
          onStage: (s) {
            if (s.startsWith('模型正在')) token.cancel();
          },
        ),
        throwsA(isA<StudioException>()),
      );
      expect(adapter.calls.length, 1);
      final failing = TaskAdapter(png, failed: true);
      await expectLater(
        StudioApi(
          store,
          dio: Dio()..httpClientAdapter = failing,
        ).generate(prompt: 'test', options: GenerationOptions()),
        throwsA(isA<StudioException>()),
      );
      expect(failing.calls.length, 1);
    },
  );
  test(
    'only explicit async-disabled response permits synchronous fallback',
    () async {
      final adapter = TaskAdapter(png, disabled: true), store = makeStore();
      final reply = await StudioApi(
        store,
        dio: Dio()..httpClientAdapter = adapter,
      ).generate(prompt: 'test', options: GenerationOptions());
      expect(reply.images.single, png);
      expect(adapter.calls.map((v) => v.uri.path), [
        '/v1/images/generations/async',
        '/v1/images/generations',
      ]);
    },
  );
}
