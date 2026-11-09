
import 'package:dio/dio.dart';
import 'package:image/image.dart' as image;
import 'package:liuguang/core/api.dart';
import 'package:liuguang/core/models.dart';
import 'package:flutter/services.dart';
import 'package:liuguang/core/updates.dart' as uc;
import 'package:liuguang/screens/updates.dart' as us;
import 'package:flutter_miuix/miuix.dart' as mx;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liuguang/core/store.dart';
import 'package:liuguang/main.dart';
import 'package:liuguang/ui/navigation.dart';
import 'package:liuguang/ui/glass.dart';
import 'package:liuguang/screens/editor.dart';

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

class FakeUpdates extends uc.UpdateService {
  uc.ReleaseInfo answer = uc.ReleaseInfo(
    uc.appVersion,
    '唯一的说明',
    'gitee',
    'https://example.org',
    'https://example.org/app.apk',
    1,
  );
  FakeUpdates(super.store);
  @override
  Future<uc.ReleaseInfo?> check() async => answer;
}

void main() {
  late AppStore store;
  late Directory dir;
  late String fixture;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('liuguang_ui_');
    fixture = '${dir.path}/fixture.png';
    await File(fixture).writeAsBytes(
      image.encodePng(image.Image(width: 96, height: 64, numChannels: 4)),
    );
    store = AppStore()
      ..prefs = await SharedPreferences.getInstance()
      ..directory = dir;
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  testWidgets('small-screen navigation and both themes remain usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(LiuguangApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('创作'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('修图').last);
    await tester.pumpAndSettle();
    expect(find.text('修图'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('作品').last);
    await tester.pumpAndSettle();
    expect(find.text('作品'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
    expect(tester.takeException(), isNull);
    store.theme = 'dark';
    store.textScale = 1.2;
    store.refresh();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('模型连接'));
    await tester.pumpAndSettle();
    expect(find.text('模型连接'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('对话模型'));
    await tester.pumpAndSettle();
    expect(find.text('API Key'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'compact navigation follows a horizontal drag and settings are secondary',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      final nav = find.byType(LiquidNavigation);
      final glass = find
          .descendant(of: nav, matching: find.byType(Glass))
          .first;
      expect(tester.getSize(glass).width, closeTo(288.6, .1));
      expect(tester.getSize(glass).height, 60);
      final center = tester.getCenter(nav);
      await tester.dragFrom(
        Offset(center.dx - 100, center.dy),
        const Offset(215, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('模型连接'), findsOneWidget);
      expect(find.text('显示模式'), findsNothing);
      expect(find.text('我的'), findsNothing);
      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();
      expect(find.text('显示模式'), findsOneWidget);
      expect(find.text('主题色'), findsOneWidget);
      final track = find
          .descendant(
            of: find.byType(mx.MiuixSlider).first,
            matching: find.byType(CustomPaint),
          )
          .first;
      expect(tester.getSize(track).width, greaterThan(200));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('generation size uses a visible ratio and K tier', (
    tester,
  ) async {
    await tester.pumpWidget(LiuguangApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1K · 1:1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9:16'));
    await tester.tap(find.text('2K'));
    await tester.ensureVisible(find.text('应用规格'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用规格'));
    await tester.pumpAndSettle();
    expect(find.text('2K · 9:16'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'all field values, including IME and programmatic edits, hide hints',
    (tester) async {
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      final field = find.byType(TextField).first;
      final controller = tester.widget<TextField>(field).controller!;
      await tester.enterText(field, 'suix');
      await tester.pump();
      expect(
        tester
            .widget<InputDecorator>(find.byType(InputDecorator).first)
            .isEmpty,
        isFalse,
      );
      controller.value = const TextEditingValue(
        text: '中文输入',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      );
      await tester.pump();
      expect(
        tester
            .widget<InputDecorator>(find.byType(InputDecorator).first)
            .isEmpty,
        isFalse,
      );
      controller.text = '程序写入的值';
      await tester.pump();
      expect(
        tester
            .widget<InputDecorator>(find.byType(InputDecorator).first)
            .isEmpty,
        isFalse,
      );
      controller.clear();
      await tester.pump();
      expect(
        tester
            .widget<InputDecorator>(find.byType(InputDecorator).first)
            .isEmpty,
        isTrue,
      );
    },
  );
  testWidgets(
    'editing menu is Chinese and contains no share or system extensions',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            if (call.method == 'Clipboard.getData') return {'text': '粘贴示例'};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'example');
      await tester.pumpAndSettle();
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText).first)
          .renderEditable;
      await tester.longPressAt(
        editable.localToGlobal(
          editable.getLocalRectForCaret(const TextPosition(offset: 3)).center,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsWidgets);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Paste'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.text('分享'), findsNothing);
      expect(find.text('问AI'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'current release appears once and download only appears in an update modal',
    (tester) async {
      final service = FakeUpdates(store);
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(StudioHome))).push(
        MaterialPageRoute(
          builder: (_) => us.UpdatesScreen(store: store, service: service),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('检查更新'));
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('当前已是最新版本'), findsOneWidget);
      expect(find.byType(us.ReleaseCard), findsNothing);
      expect(find.text('下载并安装'), findsNothing);
      expect(find.text('V1.0.0 · 2026-11-09'), findsOneWidget);
      service.answer = uc.ReleaseInfo(
        '1.0.2',
        '更新',
        'gitee',
        '',
        'https://example.org/a.apk',
        1,
      );
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.byType(us.ReleaseCard), findsOneWidget);
      expect(find.text('下载并安装'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    },
  );
  testWidgets(
    'about page has grouped entries instead of long inline disclosures',
    (tester) async {
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('关于琉光'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关于琉光'));
      await tester.pumpAndSettle();
      expect(find.text('让灵感成像'), findsOneWidget);
      expect(find.text('隐私与数据'), findsOneWidget);
      expect(find.text('开源许可'), findsOneWidget);
      expect(find.text('开源致谢'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'AI task replaces controls, prevents repeated actions and supports cancellation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      store.imageApi = EndpointConfig(
        baseUrl: 'https://example.org/v1',
        key: 'test-only',
        model: 'fixture',
      );
      final api = ControlledImageApi(store);
      await tester.pumpWidget(LiuguangApp(store: store, api: api));
      await tester.pumpAndSettle();
      final dynamic home = tester.state(find.byType(StudioHome));
      home.edit(fixture);
      await tester.pump();
      await tester.runAsync(() async {
        final dynamic editor = tester.state(find.byType(EditorScreen));
        await editor.load(fixture);
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('传奇二瞬'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始增强'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('开始增强'));
        for (var i = 0; i < 100 && api.calls == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(api.calls, 1);
      expect(find.byType(TaskStatusCard), findsOneWidget);
      expect(find.text('开始增强'), findsNothing);
      final exportButton = find.ancestor(
        of: find.text('导出'),
        matching: find.byType(GlassButton),
      );
      expect(tester.widget<GlassButton>(exportButton).onTap, isNull);
      await tester.tap(find.text('传奇二瞬'));
      await tester.pump();
      expect(api.calls, 1);
      await tester.ensureVisible(find.text('取消任务'));
      await tester.pump();
      await tester.tap(find.text('取消任务'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(TaskStatusCard), findsNothing);
      expect(find.text('开始增强'), findsOneWidget);
    },
  );
}
