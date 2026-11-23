import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liuguang/core/api.dart';
import 'package:liuguang/core/models.dart';
import 'package:liuguang/core/store.dart';
import 'package:liuguang/main.dart';
import 'package:liuguang/screens/library.dart';
import 'package:liuguang/ui/glass.dart';

class LocalModels extends StudioApi {
  final Completer<String> polished = Completer();
  final Completer<ImageReply> generated = Completer();
  String? generationOperation;
  LocalModels(super.store);
  @override
  Future<String> chat(
    List<ChatMessage> messages, {
    bool polish = false,
    void Function(String)? onText,
    CancelToken? cancelToken,
  }) async {
    return polish ? await polished.future : '角色轻轻挥手';
  }

  @override
  Future<ImageReply> generate({
    required String prompt,
    required GenerationOptions options,
    List<String> inputs = const [],
    Uint8List? mask,
    CancelToken? cancelToken,
    String operation = '文生图',
    void Function(String)? onStage,
    Future<void> Function(ImageReply)? onResult,
  }) async {
    generationOperation = operation;
    onStage?.call('正在生成 25%');
    final reply = await generated.future;
    await onResult?.call(reply);
    return reply;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'On-device polishing animation, role switch/delete, and generated artwork navigation',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp('liuguang_qa_');
      final file = File('${directory.path}/reference.jpg');
      await file.writeAsBytes(img.encodeJpg(img.Image(width: 96, height: 96)));
      SharedPreferences.setMockInitialValues({
        'draft': '一幅风景',
        'sticker_profiles': [
          jsonEncode({
            'id': 'qa',
            'name': '验证小猫',
            'description': '圆脸小猫',
            'references': [file.path],
          }),
        ],
      });
      final store = AppStore()
        ..directory = directory
        ..prefs = await SharedPreferences.getInstance();
      store.imageApi = EndpointConfig(
        baseUrl: 'https://example.invalid',
        key: 'test',
        model: 'test-image',
      );
      store.chatApi = EndpointConfig(
        baseUrl: 'https://example.invalid',
        key: 'test',
        model: 'test-chat',
      );
      final api = LocalModels(store);
      await tester.pumpWidget(LiuguangApp(store: store, api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('智能润色'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(AuroraBusyButton), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 180));
      api.polished.complete('一幅带自然柔光的风景');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('润色预览'), findsOneWidget);
      await tester.tap(find.text('应用润色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('表情包'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('表情角色管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('选用验证小猫'));
      await tester.pumpAndSettle();
      expect(find.text('验证小猫 · 固定角色参考'), findsOneWidget);
      await tester.tap(find.byTooltip('表情角色管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('管理验证小猫'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除验证小猫'));
      await tester.pumpAndSettle();
      expect(find.text('删除「验证小猫」？'), findsOneWidget);
      await tester.tap(find.text('确认').last);
      await tester.pumpAndSettle();
      expect(find.text('大肥鱼娘 · 固定角色参考'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '你好');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final generate = find.text('生成表情包');
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TaskStatusCard), findsOneWidget);
      api.generated.complete(ImageReply([await file.readAsBytes()]));
      for (
        var i = 0;
        i < 45 && find.byType(ArtworkDetail).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();
      expect(api.generationOperation, '大肥鱼娘表情包');
      expect(find.byType(ArtworkDetail), findsOneWidget);
      expect(store.artworks.single.prompt, '你好');
      await tester.pumpWidget(const SizedBox.shrink());
      await directory.delete(recursive: true);
    },
  );
}
