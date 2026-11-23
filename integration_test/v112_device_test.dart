import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:liuguang/core/api.dart';
import 'package:liuguang/core/models.dart';
import 'package:liuguang/core/store.dart';
import 'package:liuguang/core/updates.dart';
import 'package:liuguang/main.dart';
import 'package:liuguang/screens/library.dart';
import 'package:liuguang/screens/updates.dart';
import 'package:liuguang/screens/usage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixtureService implements HttpClientAdapter {
  int imageCalls = 0;
  final png = img.encodePng(img.Image(width: 64, height: 64));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancellation,
  ) async {
    await stream?.drain<void>();
    final path = options.uri.path;
    final Object response;
    if (path.endsWith('/chat/completions')) {
      response = {
        'choices': [
          {
            'message': {'content': '角色轻轻挥手'},
          },
        ],
      };
    } else if (path.endsWith('/images/edits')) {
      imageCalls++;
      final fields = Map.fromEntries((options.data as FormData).fields);
      expect(fields['output_format'], 'gif');
      expect(fields['frame_count'], '8');
      expect(fields['frame_duration_ms'], '150');
      expect(fields['size'], '512x512');
      response = {
        'data': [
          {'b64_json': base64Encode(png)},
        ],
        'usage': {'input_tokens': 8, 'output_tokens': 4},
      };
    } else {
      throw StateError('Unexpected fixture route $path');
    }
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'USB V1.1.2 library, selection, hidden space and real GIF failure path',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('liuguang_v112_');
      final large = File('${dir.path}/large.jpg');
      await large.writeAsBytes(
        img.encodeJpg(img.Image(width: 4096, height: 4096)),
      );
      SharedPreferences.setMockInitialValues({
        'update_auto': false,
        'draft': '验证',
      });
      var allowGif = false;
      final store = AppStore(readGifAvailability: (_) async => allowGif)
        ..directory = dir
        ..prefs = await SharedPreferences.getInstance();
      final fixture = _FixtureService();
      final api = StudioApi(store, dio: Dio()..httpClientAdapter = fixture);
      store.imageApi = EndpointConfig(
        baseUrl: 'https://fixture.invalid/v1',
        key: 'fixture-credential',
        model: 'gpt-image-2.6-sunburst',
        protocol: ApiProtocol.gptImage,
      );
      store.chatApi = EndpointConfig(
        baseUrl: 'https://fixture.invalid/v1',
        key: 'fixture-credential',
        model: 'fixture-chat',
      );
      for (var i = 0; i < 10; i++) {
        store.artworks.add(
          Artwork(
            id: 'qa-$i',
            path: large.path,
            prompt: '验证',
            model: 'fixture',
            kind: '真机作品 $i',
            created: DateTime(2026).subtract(Duration(minutes: i)),
            width: 4096,
            height: 4096,
            hidden: i == 9,
            favorite: i == 0,
          ),
        );
      }
      await AppLog.init(dir);
      try {
        await tester.pumpWidget(LiuguangApp(store: store, api: api));
        await tester.pumpAndSettle();
        await _tap(tester, find.text('图生图'));
        await _tap(tester, find.text('文生图'));
        await _tap(tester, find.text('作品').last);
        await _tap(tester, find.text('收藏'));
        expect(find.text('1 件作品'), findsOneWidget);
        await _tap(tester, find.text('GIF'));
        await _tap(tester, find.text('全部作品'));
        final first = find.text('真机作品 0');
        await Scrollable.ensureVisible(tester.element(first), alignment: .45);
        await tester.pumpAndSettle();
        await tester.tap(first.hitTestable());
        await tester.pump(const Duration(milliseconds: 35));
        expect(find.byType(ArtworkDetail), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.byTooltip('查看大图'), findsOneWidget);
        await _tap(tester, find.byTooltip('返回'));
        final scroll = find
            .descendant(
              of: find.byType(LibraryScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        final scrollState = tester.state<ScrollableState>(scroll);
        final secondRow = find.text('真机作品 2');
        await Scrollable.ensureVisible(
          tester.element(secondRow),
          alignment: .45,
        );
        await tester.pumpAndSettle();
        final offset = scrollState.position.pixels;
        await tester.longPress(secondRow);
        await tester.pumpAndSettle();
        expect(scrollState.position.pixels, offset);
        for (final action in ['分享图', '全选', '删除', '隐藏']) {
          expect(find.text(action), findsOneWidget);
        }
        await _tap(tester, find.byTooltip('取消'));
        scrollState.position.jumpTo(0);
        await tester.pumpAndSettle();
        final scroller = find.byType(CustomScrollView).first;
        await tester.drag(scroller, const Offset(0, 140));
        await tester.pumpAndSettle();
        expect(find.text('隐藏空间'), findsNothing);
        await tester.drag(scroller, const Offset(0, 275));
        await tester.pumpAndSettle();
        expect(find.text('隐藏空间'), findsOneWidget);
        expect(find.text('真机作品 9'), findsOneWidget);
        await _tap(tester, find.text('创作').last);
        await _tap(tester, find.text('作品').last);
        expect(find.text('隐藏空间'), findsNothing);
        await _tap(tester, find.text('创作').last);
        await _tap(tester, find.text('表情包'));
        final animatedMode = find.text('动图 · 512 GIF');
        await tester.ensureVisible(animatedMode);
        await tester.pumpAndSettle();
        await tester.tap(animatedMode);
        await tester.pump(const Duration(milliseconds: 240));
        expect(find.text('GIF生成测试中，暂不支持使用'), findsOneWidget);
        expect(fixture.imageCalls, 0);
        allowGif = true;
        await store.refreshGifAvailability();
        await _tap(tester, animatedMode);
        await tester.enterText(find.byType(TextField).last, '真机验证文本');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final generate = find.text('生成表情包');
        await tester.ensureVisible(generate);
        await tester.tap(generate);
        for (
          var i = 0;
          i < 80 &&
              store.usage.every((entry) => !entry.operation.contains('动图'));
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await tester.pump(const Duration(milliseconds: 300));
        expect(fixture.imageCalls, 1);
        final usage = store.usage.singleWhere(
          (r) => r.operation.contains('动图'),
        );
        expect(usage.success, isFalse);
        expect(usage.images, 0);
        expect(usage.inputTokens, 8);
        expect(store.artworks, hasLength(10));
        expect(find.textContaining('服务端返回的文件不是可读取的 GIF'), findsOneWidget);
        final records = await AppLog.read();
        expect(records, contains('sticker_gif_failure'));
        expect(records, isNot(contains('fixture-credential')));
        expect(records, isNot(contains('真机验证文本')));
        expect(records, isNot(contains('application_start')));
        final navigation = Navigator.of(tester.element(generate));
        navigation.push<void>(
          MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
        );
        await tester.pumpAndSettle();
        await _tap(tester, find.text('GIF 表情包生成失败'));
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('发生了什么'), findsOneWidget);
        expect(find.textContaining('服务端返回的文件不是可读取的 GIF'), findsOneWidget);
        expect(find.textContaining('输入 8 · 输出 4'), findsOneWidget);
        navigation.pop();
        await tester.pumpAndSettle();
        navigation.pop();
        await tester.pumpAndSettle();
        navigation.push<void>(
          MaterialPageRoute(builder: (_) => UsageScreen(store: store)),
        );
        await tester.pumpAndSettle();
        final usageRow = find.text('大肥鱼娘动图表情包');
        await tester.scrollUntilVisible(
          usageRow,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await _tap(tester, usageRow);
        expect(find.textContaining('服务端返回的文件不是可读取的 GIF'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        AppLog.file = null;
        await dir.delete(recursive: true);
      }
    },
  );
}
