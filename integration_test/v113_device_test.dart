import 'dart:async';
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
import 'package:liuguang/core/updates.dart' show AppLog;
import 'package:liuguang/main.dart';
import 'package:liuguang/screens/custom_sticker.dart';
import 'package:liuguang/screens/sticker_manager.dart';
import 'package:liuguang/ui/glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CharacterService implements HttpClientAdapter {
  final pending = Completer<void>();
  final calls = <List<dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancellation,
  ) async {
    expect(options.uri.host, 'fixture.invalid');
    final messages = List<dynamic>.from((options.data as Map)['messages']);
    calls.add(messages);
    expect(messages.first['role'], 'system');
    expect(messages.first['content'], contains(chineseResponseInstruction));
    if (calls.length == 1) await pending.future;
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {
            'message': {'content': '黄色小蛙，圆形肚皮和棕色手掌。'},
          },
        ],
      }),
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'USB V1.1.3 character preview, pending analysis, drag, Chinese requests',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('liuguang_v113_');
      final reference = File('${dir.path}/wide.jpg');
      final wide = img.Image(width: 1650, height: 660);
      img.fill(wide, color: img.ColorRgb8(223, 177, 35));
      await reference.writeAsBytes(img.encodeJpg(wide));
      SharedPreferences.setMockInitialValues({'update_auto': false});
      final store = AppStore()
        ..directory = dir
        ..prefs = await SharedPreferences.getInstance()
        ..chatApi = EndpointConfig(
          baseUrl: 'https://fixture.invalid/v1',
          key: 'fake',
          model: 'chat',
        )
        ..visionApi = EndpointConfig(model: 'vision');
      store.artworks.add(
        Artwork(
          id: 'turnaround',
          path: reference.path,
          prompt: '',
          model: 'fixture',
          kind: '三视图样本',
          created: DateTime(2026),
          width: 1650,
          height: 660,
        ),
      );
      final service = _CharacterService();
      final api = StudioApi(store, dio: Dio()..httpClientAdapter = service);
      await AppLog.init(dir);
      try {
        await tester.pumpWidget(LiuguangApp(store: store, api: api));
        await tester.pumpAndSettle();
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.push<StickerProfile>(
          MaterialPageRoute(
            builder: (_) =>
                StickerCharacterCreatorScreen(store: store, api: api),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '奶娃验证');
        await tester.ensureVisible(find.text('添加三视图'));
        await tester.tap(find.text('添加三视图'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('从作品选择'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('选择作品 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('完成选择'));
        await tester.pump(const Duration(milliseconds: 320));
        final preview = find.byType(StickerReferencePreview);
        final picture = find.descendant(
          of: preview,
          matching: find.byType(Image),
        );
        expect(tester.widget<Image>(picture).fit, BoxFit.contain);
        final pendingText = find.textContaining('正在识别三视图');
        final save = find.text('保存并开始制作');
        await tester.ensureVisible(save);
        await tester.pump(const Duration(milliseconds: 32));
        expect(
          tester.getRect(pendingText).bottom,
          lessThan(tester.getRect(save).top),
        );
        expect(
          tester
              .widget<GlassButton>(
                find.ancestor(of: save, matching: find.byType(GlassButton)),
              )
              .onTap,
          isNull,
        );
        expect(tester.takeException(), isNull);
        service.pending.complete();
        for (var i = 0; i < 90 && pendingText.evaluate().isNotEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 40));
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        await tester.pumpAndSettle();
        expect(pendingText, findsNothing);
        expect(find.textContaining(stickerProps), findsOneWidget);
        await tester.ensureVisible(save);
        await tester.tap(save);
        for (var i = 0; i < 60 && save.evaluate().isNotEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 35));
          await Future<void>.delayed(const Duration(milliseconds: 35));
        }
        await tester.pumpAndSettle();
        final character = readStickerProfiles(store).single;
        expect(character.name, '奶娃验证');
        expect(await File(character.references.single).exists(), isTrue);
        final reply = await api.chat([
          ChatMessage('user', 'Keep the name Sunny.'),
        ]);
        expect(reply, contains('黄色小蛙'));
        expect(service.calls.last.last['content'], 'Keep the name Sunny.');
        const builtin = StickerProfile(
          id: 'builtin',
          name: '内置验证',
          description: '',
          references: [],
        );
        nav.push<void>(
          MaterialPageRoute(
            builder: (_) => StickerManager(
              store: store,
              builtin: builtin,
              active: character,
              builtinImage: FileImage(reference),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final handles = find.byType(ReorderableDragStartListener);
        expect(handles, findsNWidgets(2));
        final target = tester.getCenter(handles.first);
        final gesture = await tester.startGesture(
          tester.getCenter(handles.last),
        );
        final start = tester.getCenter(handles.last);
        for (var step = 1; step <= 12; step++) {
          await gesture.moveTo(
            Offset.lerp(start, target + const Offset(0, 9), step / 12)!,
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(orderedStickerProfiles(store, builtin).first.id, character.id);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        AppLog.file = null;
        await dir.delete(recursive: true);
      }
    },
  );
}
