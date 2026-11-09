import 'package:dio/dio.dart';
import 'package:liuguang/core/image_transport.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:liuguang/core/api.dart';
import 'package:liuguang/core/imaging.dart';
import 'package:liuguang/core/models.dart';
import 'package:liuguang/core/store.dart';
import 'package:liuguang/main.dart';
import 'package:liuguang/ui/glass.dart';

class ControlledImageApi extends StudioApi {
  int calls = 0;
  ControlledImageApi(super.store);
  @override
  Future<ImageReply> generate({
    required String prompt,
    required GenerationOptions options,
    List<String> inputs = const [],
    Uint8List? mask,
    CancelToken? cancelToken,
    String operation = '文生图',
    void Function(String)? onStage,
  }) async {
    calls++;
    onStage?.call('模型正在处理，请稍候');
    await cancelToken!.whenCancel;
    throw cancelToken.cancelError!;
  }
}

Uint8List buildLargeFixture(Uint8List bytes) {
  var source = img.decodeImage(bytes)!;
  source = img.copyCrop(
    source,
    x: 0,
    y: (source.height - source.width * 9 / 16).round() ~/ 2,
    width: source.width,
    height: (source.width * 9 / 16).round(),
  );
  return img.encodePng(img.copyResize(source, width: 7680, height: 4320));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android native bridge, image API, shader editor and export', (
    tester,
  ) async {
    final store = AppStore();
    await store.init();
    final userDirectory = store.directory;
    final temporary = await Directory.systemTemp.createTemp(
      'liuguang_device_test_',
    );
    store.directory = temporary;
    store.artworks = [];
    store.usage = [];
    store.messages = [];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final input = img.Image(width: 96, height: 64, numChannels: 4);
    for (final p in input) {
      p.setRgba(p.x * 2, p.y * 3, 90, 255);
    }
    final png = img.encodePng(input);
    final calls = <String>[];
    server.listen((request) async {
      calls.add(request.uri.path);
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/models')) {
        request.response.write(
          jsonEncode({
            'data': [
              {'id': 'device-image-test'},
              {'id': 'device-chat-test'},
            ],
          }),
        );
      } else if (request.uri.path.endsWith('/chat/completions')) {
        expect(
          request.headers.value('authorization'),
          'Bearer device-chat-key',
        );
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '保留原意的润色提示词'},
              },
            ],
            'usage': {'prompt_tokens': 8, 'completion_tokens': 6},
          }),
        );
      } else {
        expect(
          request.headers.value('authorization'),
          'Bearer device-image-key',
        );
        request.response.write(
          jsonEncode({
            'data': [
              {'b64_json': base64Encode(png)},
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 12},
          }),
        );
      }
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}/v1';
    store.imageApi = EndpointConfig(
      baseUrl: base,
      key: 'device-image-key',
      model: 'device-image-test',
      protocol: ApiProtocol.gptImage,
    );
    store.chatApi = EndpointConfig(
      baseUrl: base,
      key: 'device-chat-key',
      model: 'device-chat-test',
    );
    try {
      await store.secure.write(
        key: 'liuguang_integration_probe',
        value: 'keystore-roundtrip',
      );
      expect(
        await store.secure.read(key: 'liuguang_integration_probe'),
        'keystore-roundtrip',
      );
      final api = StudioApi(store);
      expect((await api.discover(store.imageApi)).length, 2);
      final generated = await api.generate(
        prompt: '设备联调测试',
        options: GenerationOptions(width: 96, height: 64),
      );
      expect(generated.images.single, png);
      final source = await store.writeImage(png, 'png');
      await api.generate(
        prompt: '蒙版编辑联调',
        options: GenerationOptions(width: 96, height: 64),
        inputs: [source, source],
        mask: png,
      );
      expect(
        await api.chat([ChatMessage('user', '测试')], polish: true),
        '保留原意的润色提示词',
      );
      final webp = (await native.invokeMethod<Uint8List>('encodeWebp', {
        'bytes': png,
        'quality': 80,
      }))!;
      expect(imageExtension(webp), 'webp');
      expect(img.decodeWebP(webp)!.width, 96);
      final webpPath = await store.writeImage(webp, 'webp');
      await saveToGallery(webpPath);
      final frames = await compute(encodeAnimation, {
        'frames': [png, png],
        'duration': 250,
        'colors': 128,
      });
      final gifPath = await store.writeImage(frames, 'gif');
      await saveToGallery(gifPath);
      expect(img.decodeGif(frames)!.numFrames, 2);
      await LiquidGlass.precache();
      final controlled = ControlledImageApi(store);
      await tester.pumpWidget(LiuguangApp(store: store, api: controlled));
      await tester.pumpAndSettle();
      expect(find.text('创作'), findsWidgets);
      expect(tester.takeException(), isNull);
      // Open the generated fixture through the same route used by the library.
      final dynamic home = tester.state(find.byType(StudioHome));
      home.edit(source);
      await tester.pumpAndSettle();
      expect(find.text('修图'), findsWidgets);
      await tester.tap(find.text('传奇二瞬'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始增强'));
      for (var i = 0; i < 40 && controlled.calls == 0; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(controlled.calls, 1);
      expect(find.byType(TaskStatusCard), findsOneWidget);
      expect(find.text('开始增强'), findsNothing);
      final disabledExport = tester.widget<GlassButton>(
        find.ancestor(of: find.text('导出'), matching: find.byType(GlassButton)),
      );
      expect(disabledExport.onTap, isNull);
      await tester.tap(find.text('传奇二瞬'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(controlled.calls, 1);
      await tester.tap(find.text('取消任务'));
      for (
        var i = 0;
        i < 40 && find.byType(TaskStatusCard).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.byType(TaskStatusCard), findsNothing);
      expect(find.text('开始增强'), findsOneWidget);
      await tester.tap(find.text('色彩平衡'));
      await tester.pumpAndSettle();
      final preview = find.byKey(const Key('editor-preview'));
      final previewBounds = tester.getRect(preview);
      final tools = find
          .ancestor(of: find.text('保持明度'), matching: find.byType(ListView))
          .first;
      await tester.drag(tools, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(tester.getRect(preview), previewBounds);
      await tester.drag(tools, const Offset(0, 160));
      await tester.pumpAndSettle();
      expect(find.text('保持明度'), findsOneWidget);
      expect(
        tester.widget<GlassCheckbox>(find.byType(GlassCheckbox).first).value,
        isTrue,
      );
      final slider = find.byType(GlassSlider).first;
      await tester.drag(slider, const Offset(55, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Include button padding in the target: the whole glass must be tappable.
      final exportButton = find.ancestor(
        of: find.text('导出'),
        matching: find.byType(GlassButton),
      );
      await tester.tapAt(tester.getTopLeft(exportButton) + const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('保存作品'), findsOneWidget);
      final saveButton = find.ancestor(
        of: find.text('保存作品'),
        matching: find.byType(GlassButton),
      );
      await tester.tapAt(tester.getCenter(saveButton));
      await tester.pumpAndSettle();
      for (var i = 0; i < 30 && store.artworks.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(store.artworks, isNotEmpty);
      expect(store.artworks.first.width, 96);
      expect(store.artworks.first.height, 64);
      expect(
        calls,
        containsAll([
          '/v1/models',
          '/v1/images/generations',
          '/v1/images/edits',
          '/v1/chat/completions',
        ]),
      );
      expect(store.usage.length, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      await store.secure.delete(key: 'liuguang_integration_probe');
      await server.close(force: true);
      store.directory = userDirectory;
      await temporary.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
  if (const bool.fromEnvironment('LIVE_PROVIDER_TEST')) {
    testWidgets(
      'live configured provider: portrait generation and 8K-source edit',
      (tester) async {
        final live = AppStore();
        await live.init();
        expect(live.imageApi.ready, isTrue, reason: '手机内须已保存可用的生图配置');
        expect(live.imageApi.model, 'gpt-image-2.6-sunburst');
        final api = StudioApi(live);
        String last = '';
        void stage(String value) {
          if (value != last) {
            debugPrint('LIVE_PROVIDER_STAGE $value');
            last = value;
          }
        }

        final portrait = await api.generate(
          prompt: '一张3:4竖幅的自然山景照片，湖泊与远山，天空在上方，构图完整，无文字。',
          options: GenerationOptions(width: 768, height: 1024, quality: 'low'),
          operation: 'V1.0.1 竖幅验证',
          onStage: stage,
        );
        final first = await saveArtwork(
          live,
          portrait.images.first,
          prompt: 'V1.0.1 竖幅验证示例',
          model: live.imageApi.model,
          kind: '验证示例',
        );
        debugPrint('LIVE_PROVIDER_PORTRAIT ${first.width}x${first.height}');
        expect(
          matchesRequestedAspect(first.width, first.height, 768, 1024),
          isTrue,
          reason: '服务端须实际返回3:4，客户端不旋转、裁切或拉伸来掩盖错误',
        );
        final asset = (await rootBundle.load('assets/mountain.jpg')).buffer
            .asUint8List();
        final large = await compute(buildLargeFixture, asset);
        final path = await live.writeImage(large, 'png');
        try {
          final edited = await api.generate(
            prompt: lensPrompt,
            options: GenerationOptions(
              width: 1024,
              height: 576,
              quality: 'low',
            ),
            inputs: [path],
            operation: 'V1.0.1 大图景深验证',
            onStage: stage,
          );
          final art = await saveArtwork(
            live,
            edited.images.first,
            prompt: 'V1.0.1 大图景深验证示例',
            model: live.imageApi.model,
            kind: '验证示例',
          );
          debugPrint('LIVE_PROVIDER_EDIT ${art.width}x${art.height}');
          expect(
            matchesRequestedAspect(art.width, art.height, 1024, 576),
            isTrue,
          );
        } finally {
          await File(path).delete();
        }
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );
  }
}
