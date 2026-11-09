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
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('创作'), findsWidgets);
      expect(tester.takeException(), isNull);
      // Open the generated fixture through the same route used by the library.
      final dynamic home = tester.state(find.byType(StudioHome));
      home.edit(source);
      await tester.pumpAndSettle();
      expect(find.text('修图'), findsWidgets);
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
}
