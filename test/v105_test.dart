import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:flutter_test/flutter_test.dart';
import 'package:liuguang/core/api.dart';
import 'package:liuguang/core/models.dart';
import 'package:liuguang/core/store.dart';

class _Store extends AppStore {
  @override
  Future<void> addUsage(UsageRecord record) async {
    usage.add(record);
  }
}

void main() {
  test(
    'advanced image parameters are opt-in, bounded and persisted with artwork',
    () {
      final defaults = GenerationOptions();
      final config = EndpointConfig(model: 'provider-model');
      expect(
        imagePayload(config, defaults, 'original').containsKey('seed'),
        isFalse,
      );
      final advanced = GenerationOptions(
        advanced: {
          'seed': 42,
          'steps': 30,
          'guidance_scale': 7.5,
          'sampler': 'provider_sampler',
        },
      );
      final restored = GenerationOptions.fromJson(advanced.toJson());
      final payload = imagePayload(config, restored, 'original');
      expect(payload['seed'], 42);
      expect(payload['steps'], 30);
      expect(payload['guidance_scale'], 7.5);
      expect(payload['sampler'], 'provider_sampler');
      expect(payload['prompt'], contains('original'));
      advanced.advanced['model'] = 'override';
      expect(
        () => imagePayload(config, advanced, 'original'),
        throwsA(isA<StudioException>()),
      );
      final art = Artwork(
        id: 'metadata',
        path: 'local.png',
        prompt: 'real prompt',
        model: 'fixture',
        kind: '文生图',
        created: DateTime(2026),
        width: 4096,
        height: 3072,
        parameters: restored.toJson(),
      );
      final saved = Artwork.fromJson(art.toJson());
      expect(saved.parameters['advanced']['seed'], 42);
      final old = Map<String, dynamic>.from(art.toJson())..remove('parameters');
      expect(Artwork.fromJson(old).parameters, isEmpty);
    },
  );

  test('native GIF is restricted to the exact model family', () {
    for (final id in [
      'gpt-image-2.6',
      'gpt-image-2.6-flare',
      'gpt-image-2.6-sunburst',
      'provider/gpt-image-2.6-sunburst',
    ]) {
      expect(supportsNativeGif(id), isTrue);
    }
    for (final id in [
      'gpt-image-2',
      'gpt-image-2.60',
      'gpt-image-2.5',
      'fake-gpt-image-2.6',
    ]) {
      expect(supportsNativeGif(id), isFalse);
    }
  });
  test('unsupported native GIF is rejected before sending a request', () async {
    final store = _Store()
      ..imageApi = EndpointConfig(
        baseUrl: 'http://127.0.0.1:1/v1',
        key: 'fake',
        model: 'gpt-image-2',
        protocol: ApiProtocol.gptImage,
      );
    await expectLater(
      StudioApi(store).generate(
        prompt: '动图',
        options: GenerationOptions(format: 'gif'),
      ),
      throwsA(
        isA<StudioException>().having(
          (e) => e.message,
          'message',
          contains('当前模型暂不支持 GIF'),
        ),
      ),
    );
    expect(store.usage, isEmpty);
  });
  test('native GIF bytes and animation frames are preserved', () async {
    final encoder = img.GifEncoder(repeat: 0);
    encoder.addFrame(img.Image(width: 64, height: 64), duration: 15);
    encoder.addFrame(
      img.fill(
        img.Image(width: 64, height: 64),
        color: img.ColorRgb8(255, 0, 0),
      ),
      duration: 15,
    );
    final gif = encoder.finish()!;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join());
      expect(payload['output_format'], 'gif');
      expect(payload['size'], '64x64');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'data': [
            {'b64_json': base64Encode(gif)},
          ],
        }),
      );
      await request.response.close();
    });
    final store = _Store()
      ..imageApi = EndpointConfig(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        key: 'fake',
        model: 'gpt-image-2.6-sunburst',
        protocol: ApiProtocol.gptImage,
      );
    try {
      final reply = await StudioApi(store).generate(
        prompt: '轻轻动起来',
        options: GenerationOptions(width: 64, height: 64, format: 'gif'),
      );
      expect(reply.images.single, orderedEquals(gif));
      expect(img.decodeGif(reply.images.single)!.numFrames, 2);
    } finally {
      await server.close(force: true);
    }
  });
  test('streamed text splits Unicode safely and records usage', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body['stream'], isTrue);
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      for (final part in ['自然', '光线']) {
        request.response.write(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': part},
              },
            ],
          })}\n\n',
        );
      }
      request.response.write(
        'data: ${jsonEncode({
          'choices': [],
          'usage': {'prompt_tokens': 3, 'completion_tokens': 4},
        })}\n\ndata: [DONE]\n\n',
      );
      await request.response.close();
    });
    final store = _Store()
      ..chatApi = EndpointConfig(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        key: 'fake',
        model: 'fixture',
      );
    final updates = <String>[];
    try {
      final result = await StudioApi(store)
          .chat([ChatMessage('user', 'test')], onText: updates.add);
      expect(result, '自然光线');
      expect(updates, ['自然', '自然光线']);
      expect(store.usage.single.outputTokens, 4);
    } finally {
      await server.close(force: true);
    }
  });
}
