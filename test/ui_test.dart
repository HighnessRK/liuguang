import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liuguang/core/store.dart';
import 'package:liuguang/main.dart';
import 'package:liuguang/ui/navigation.dart';
import 'package:liuguang/ui/glass.dart';

void main() {
  late AppStore store;
  late Directory dir;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('liuguang_ui_');
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
}
