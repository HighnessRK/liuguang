import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:liuguang/core/api.dart';
import 'package:liuguang/core/imaging.dart';
import 'package:liuguang/core/models.dart';
import 'package:liuguang/core/store.dart';

class MemoryStore extends AppStore {
  @override
  Future<void> addUsage(UsageRecord record) async {
    usage.insert(0, record);
  }

  @override
  Future<void> saveCatalog() async {
    notifyListeners();
  }
}

void main() {
  test('base addresses normalize paths without doubling API routes', () {
    expect(
      apiUri('https://example.com/v1/', 'models').toString(),
      'https://example.com/v1/models',
    );
    expect(
      apiUri('https://example.com/custom/images/edits', 'models').path,
      '/custom/models',
    );
    expect(
      () => apiUri('example.com', 'models'),
      throwsA(isA<StudioException>()),
    );
    expect(
      () => apiUri('https://example.com/v1?key=secret', 'models'),
      throwsA(isA<StudioException>()),
    );
  });
  test(
    'original prompt remains byte-identical; moderation is a separate appendix',
    () {
      const original = '  主体：三个人\n禁止改变服装。🌙  ';
      expect(effectivePrompt(original, 'auto'), original);
      expect(
        effectivePrompt(original, 'strict').startsWith('$original\n\n'),
        isTrue,
      );
      final c = EndpointConfig(
        model: 'gpt-image-test',
        protocol: ApiProtocol.gptImage,
      );
      final p = imagePayload(
        c,
        GenerationOptions(format: 'gif', moderation: 'low'),
        original,
      );
      expect(p['output_format'], 'png');
      expect(p['moderation'], 'low');
      expect(p.containsKey('output_compression'), isFalse);
      expect(
        imagePayload(
          c,
          GenerationOptions(format: 'jpeg', compression: 75),
          original,
        )['output_compression'],
        75,
      );
    },
  );
  test('secrets are excluded from serializable configuration', () {
    final c = EndpointConfig(
      key: 'private-token',
      baseUrl: 'https://example.com/v1',
    );
    expect(jsonEncode(c.toJson()).contains('private-token'), isFalse);
    expect(c.snapshot().key, 'private-token');
  });
  test(
    'color balance preserves HSL lightness in shadows, midtones and highlights',
    () {
      final a = Adjustments();
      a.balance = [.8, -.6, .4, -.4, .5, -.3, .2, -.7, .9];
      expect(a.preserveLuminosity, isTrue);
      for (final pixel in [
        [.1, .2, .3],
        [.4, .65, .5],
        [.8, .7, .9],
        [.5, .5, .5],
      ]) {
        final adjusted = adjustPixel(pixel[0], pixel[1], pixel[2], a);
        double lightness(List<double> c) =>
            (c.reduce(math.max) + c.reduce(math.min)) / 2;
        expect(lightness(adjusted), closeTo(lightness(pixel), .000001));
      }
    },
  );
  test(
    'neutral adjustments and crop retain source pixels and exact dimensions',
    () {
      final source = img.Image(width: 20, height: 16, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(20, 80, 145, 255));
      final rendered = processImage({
        'bytes': img.encodePng(source),
        'adjustments': Adjustments().toJson(),
        'crop': [.25, .25, .5, .5],
        'rotation': 90,
      });
      expect(rendered['width'], 8);
      expect(rendered['height'], 10);
      final result = img.decodeImage(rendered['bytes'])!;
      expect(result.getPixel(2, 2).r, 20);
      expect(result.getPixel(2, 2).b, 145);
    },
  );
  test('masked composition preserves every pixel outside the mask', () {
    final original = img.Image(width: 12, height: 10, numChannels: 4);
    final generated = img.Image(width: 12, height: 10, numChannels: 4);
    final mask = img.Image(width: 12, height: 10, numChannels: 4);
    img.fill(original, color: img.ColorRgba8(31, 70, 100, 255));
    img.fill(generated, color: img.ColorRgba8(220, 10, 50, 255));
    img.fill(mask, color: img.ColorRgba8(255, 255, 255, 255));
    mask.setPixelRgba(6, 5, 255, 255, 255, 0);
    mask.setPixelRgba(7, 5, 255, 255, 255, 128);
    final result = img.decodePng(
      compositeMasked({
        'original': img.encodePng(original),
        'generated': img.encodePng(generated),
        'mask': img.encodePng(mask),
      }),
    )!;
    for (final p in result) {
      if (p.x == 6 && p.y == 5) {
        expect(p.r, 220);
      } else if (p.x == 7 && p.y == 5) {
        expect(p.r, inInclusiveRange(124, 126));
      } else {
        expect([p.r, p.g, p.b, p.a], [31, 70, 100, 255]);
      }
    }
  });
  test(
    'GIF encoder creates a real looping animation with correct frame durations',
    () {
      final a = img.Image(width: 24, height: 16);
      img.fill(a, color: img.ColorRgb8(250, 30, 20));
      final b = img.Image(width: 16, height: 24);
      img.fill(b, color: img.ColorRgb8(20, 30, 250));
      final bytes = encodeAnimation({
        'frames': [img.encodePng(a), img.encodePng(b)],
        'duration': 300,
        'colors': 128,
      });
      expect(ascii.decode(bytes.sublist(0, 6)), startsWith('GIF8'));
      final result = img.decodeGif(bytes)!;
      expect(result.numFrames, 2);
      expect(result.width, 24);
      expect(result.height, 16);
      expect(result.frames.first.frameDuration, 300);
    },
  );

  group('real HTTP adapter against local mock server', () {
    late HttpServer server;
    late MemoryStore store;
    late StudioApi api;
    late Directory directory;
    late List<Map<String, dynamic>> requests;
    final png = img.encodePng(img.Image(width: 8, height: 8));
    setUp(() async {
      requests = [];
      directory = await Directory.systemTemp.createTemp('liuguang_test_');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      store = MemoryStore()..directory = directory;
      final base = 'http://127.0.0.1:${server.port}/v1';
      store.imageApi = EndpointConfig(
        baseUrl: base,
        key: 'image-only-secret',
        model: 'gpt-image-test',
        protocol: ApiProtocol.gptImage,
      );
      store.chatApi = EndpointConfig(
        baseUrl: base,
        key: 'chat-only-secret',
        model: 'chat-test',
        inputPrice: 1,
        outputPrice: 2,
      );
      api = StudioApi(store);
      server.listen((request) async {
        final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        requests.add({
          'path': request.uri.path,
          'authorization': request.headers.value('authorization'),
          'body': utf8.decode(body, allowMalformed: true),
          'type': request.headers.contentType?.mimeType,
        });
        request.response.headers.contentType = ContentType.json;
        switch (request.uri.path) {
          case '/v1/models':
            request.response.write(
              jsonEncode({
                'data': [
                  {'id': 'chat-test'},
                  {'id': 'gpt-image-test'},
                  {'id': 'embedding-test'},
                ],
              }),
            );
          case '/v1/images/generations':
          case '/v1/images/edits':
            request.response.write(
              jsonEncode({
                'data': [
                  {'b64_json': base64Encode(png)},
                ],
                'usage': {'input_tokens': 12, 'output_tokens': 20},
              }),
            );
          case '/v1/chat/completions':
            request.response.write(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '润色后的画面描述'},
                  },
                ],
                'usage': {'prompt_tokens': 100, 'completion_tokens': 50},
              }),
            );
          case '/image.png':
            request.response.headers.contentType = ContentType('image', 'png');
            request.response.add(png);
          default:
            request.response.statusCode = 401;
            request.response.write(
              jsonEncode({
                'error': {'message': 'invalid credential'},
              }),
            );
        }
        await request.response.close();
      });
    });
    tearDown(() async {
      api.dio.close(force: true);
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    test(
      'discovery lists every returned model without capability filtering',
      () async {
        expect(await api.discover(store.imageApi), [
          'chat-test',
          'embedding-test',
          'gpt-image-test',
        ]);
        expect(requests.single['authorization'], 'Bearer image-only-secret');
      },
    );
    test(
      'image request carries dimensions, format, quantity and server usage',
      () async {
        final reply = await api.generate(
          prompt: '一束花',
          options: GenerationOptions(
            width: 1536,
            height: 1024,
            format: 'jpeg',
            count: 2,
          ),
        );
        final body = jsonDecode(requests.single['body']);
        expect(body['size'], '1536x1024');
        expect(body['n'], 2);
        expect(body['output_format'], 'jpeg');
        expect(reply.images.single, png);
        expect(store.usage.single.inputTokens, 12);
        expect(store.usage.single.success, isTrue);
      },
    );
    test(
      'edit multipart preserves first base image, multiple references and mask',
      () async {
        final first = File('${directory.path}/base.png');
        await first.writeAsBytes(png);
        final second = File('${directory.path}/ref.png');
        await second.writeAsBytes(png);
        await api.generate(
          prompt: '修改选区',
          options: GenerationOptions(),
          inputs: [first.path, second.path],
          mask: png,
        );
        expect(requests.single['path'], '/v1/images/edits');
        final body = requests.single['body'] as String;
        expect(body, contains('name="image[]"; filename="input_0.png"'));
        expect(body, contains('filename="input_1.png"'));
        expect(body, contains('name="mask"; filename="mask.png"'));
        expect(requests.single['type'], 'multipart/form-data');
      },
    );
    test(
      'chat uses its own key and calculates configured token cost',
      () async {
        expect(
          await api.chat([ChatMessage('user', '一束花')], polish: true),
          '润色后的画面描述',
        );
        expect(requests.single['authorization'], 'Bearer chat-only-secret');
        expect(store.usage.single.estimatedCost, closeTo(.0002, .0000001));
        expect(store.usage.single.operation, '提示词润色');
      },
    );
    test('remote image download never sends either API key', () async {
      final result = await api.extractImages({
        'data': [
          {'url': 'http://127.0.0.1:${server.port}/image.png'},
        ],
      }, null);
      expect(result.single, png);
      expect(requests.single['authorization'], isNull);
    });
    test(
      'failed request is recorded with unknown usage and real status',
      () async {
        store.imageApi.baseUrl = 'http://127.0.0.1:${server.port}/wrong';
        await expectLater(
          api.generate(prompt: 'test', options: GenerationOptions()),
          throwsA(isA<StudioException>()),
        );
        expect(store.usage.single.success, isFalse);
        expect(store.usage.single.inputTokens, isNull);
        expect(store.usage.single.error, contains('HTTP 401'));
      },
    );
    test('cancellation makes no automatic retry', () async {
      final token = CancelToken()..cancel('test');
      await expectLater(
        api.generate(
          prompt: 'test',
          options: GenerationOptions(),
          cancelToken: token,
        ),
        throwsA(isA<StudioException>()),
      );
      expect(requests, isEmpty);
      expect(store.usage.single.success, isFalse);
    });
  });
}
