import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as image;
import 'package:liuguang/core/api.dart';
import 'package:liuguang/core/models.dart';
import 'package:liuguang/core/appearance.dart';
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
import 'package:liuguang/screens/share_card.dart';
import 'package:liuguang/screens/create.dart';
import 'package:liuguang/screens/settings.dart';
import 'package:liuguang/screens/personalization.dart';
import 'package:liuguang/screens/storage.dart';
import 'package:liuguang/screens/usage.dart';
import 'package:liuguang/screens/materials.dart';
import 'package:liuguang/screens/library.dart';

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

class MotionFixtureApi extends StudioApi {
  int visionCalls = 0, generationCalls = 0;
  String? receivedPrompt, receivedPath;
  GenerationOptions? receivedOptions;
  MotionFixtureApi(super.store);
  @override
  Future<String> describeImage(
    String path, {
    CancelToken? cancelToken,
    String goal = 'depth',
  }) async {
    visionCalls++;
    receivedPath = path;
    expect(goal, 'gif');
    return '风轻拂树梢，湖水柔和起伏，固定镜头，无缝循环';
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
  }) async {
    generationCalls++;
    receivedPrompt = prompt;
    receivedOptions = options;
    final encoder = image.GifEncoder(repeat: 0);
    encoder.addFrame(image.Image(width: 96, height: 64), duration: 15);
    encoder.addFrame(
      image.fill(
        image.Image(width: 96, height: 64),
        color: image.ColorRgb8(20, 50, 80),
      ),
      duration: 15,
    );
    return ImageReply([Uint8List.fromList(encoder.finish()!)]);
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

  testWidgets(
    'glass button labels, icons and busy states share readable colors',
    (tester) async {
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(StudioHome));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsDetail(
            title: '按钮对比检查',
            children: [
              GlassButton(
                '可用主操作',
                primary: true,
                icon: Icons.add,
                onTap: () {},
              ),
              const GlassButton('禁用主操作', primary: true, icon: Icons.add),
              GlassButton('处理中主操作', primary: true, busy: true, onTap: () {}),
              GlassButton('次要操作', icon: Icons.add, onTap: () {}),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      for (final palette in studioPalettes) {
        store.accent = palette.primary;
        store.palette = palette.id;
        for (final dark in [false, true]) {
          for (final highContrast in [false, true]) {
            store.theme = dark ? 'dark' : 'light';
            store.highContrast = highContrast;
            store.refresh();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 450));
            for (final label in ['可用主操作', '禁用主操作', '处理中主操作', '次要操作']) {
              final button = find.ancestor(
                of: find.text(label),
                matching: find.byType(GlassButton),
              );
              final color = tester.widget<Text>(find.text(label)).style!.color!;
              final icon = find.descendant(
                of: button,
                matching: find.byType(Icon),
              );
              final spinner = find.descendant(
                of: button,
                matching: find.byType(CircularProgressIndicator),
              );
              if (icon.evaluate().isNotEmpty) {
                expect(tester.widget<Icon>(icon).color, color, reason: label);
              }
              if (spinner.evaluate().isNotEmpty) {
                expect(
                  tester.widget<CircularProgressIndicator>(spinner).color,
                  color,
                );
              }
              final ctx = tester.element(button);
              final surface = mx.MiuixTheme.of(ctx).colors.surface;
              final background = label == '次要操作'
                  ? surface
                  : Color.alphaBlend(
                      accent(ctx).withValues(
                        alpha: highContrast ? .96 : store.glassOpacity,
                      ),
                      surface,
                    );
              final a = color.computeLuminance(),
                  b = background.computeLuminance();
              final contrast = a > b
                  ? (a + .05) / (b + .05)
                  : (b + .05) / (a + .05);
              expect(
                contrast,
                greaterThanOrEqualTo(4.5),
                reason:
                    '$label palette=${palette.id} dark=$dark highContrast=$highContrast',
              );
            }
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'route snapshots only live during transitions and reduced motion bypasses them',
    (tester) async {
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      var context = tester.element(find.byType(StudioHome));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const SettingsDetail(title: '过渡检查', children: [Text('页面内容')]),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester
            .widgetList<SnapshotWidget>(
              find.byType(SnapshotWidget, skipOffstage: false),
            )
            .any((snapshot) => snapshot.controller.allowSnapshotting),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<SnapshotWidget>(find.byType(SnapshotWidget))
            .every((snapshot) => !snapshot.controller.allowSnapshotting),
        isTrue,
      );
      Navigator.of(tester.element(find.text('过渡检查'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester
            .widgetList<SnapshotWidget>(
              find.byType(SnapshotWidget, skipOffstage: false),
            )
            .any((snapshot) => snapshot.controller.allowSnapshotting),
        isTrue,
      );
      await tester.pumpAndSettle();
      store.reduceMotion = true;
      store.refresh();
      await tester.pumpAndSettle();
      context = tester.element(find.byType(StudioHome));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const SettingsDetail(title: '无动效检查', children: [Text('页面内容')]),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SnapshotWidget), findsNothing);
      expect(find.text('页面内容'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection has a green check, haptics and reversible toolbar animation',
    (tester) async {
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      store.haptics = true;
      store.artworks.add(
        Artwork(
          id: 'check-fixture',
          path: '$fixture.missing',
          prompt: 'offline',
          model: 'fixture',
          kind: '选择检查',
          created: DateTime(2026),
          width: 96,
          height: 64,
        ),
      );
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作品').last);
      await tester.pumpAndSettle();
      haptics.clear();
      expect(find.text('分享图'), findsNothing);
      await tester.ensureVisible(find.text('选择检查'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('选择检查'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final toolbar = find.byKey(const ValueKey('artwork-selection-toolbar'));
      final progress = tester.widget<SizeTransition>(toolbar).sizeFactor.value;
      expect(progress, greaterThan(0));
      expect(progress, lessThan(1));
      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
      final badge = tester.widget<Container>(
        find.byKey(const ValueKey('artwork-selected-check')),
      );
      expect(
        (badge.decoration as BoxDecoration).color,
        const Color(0xff16884b),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('artwork-selected-check')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        tester.widget<SizeTransition>(toolbar).sizeFactor.value,
        inExclusiveRange(0, 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('分享图'), findsNothing);
      store.haptics = false;
      store.reduceMotion = true;
      store.refresh();
      await tester.pumpAndSettle();
      haptics.clear();
      await tester.ensureVisible(find.text('选择检查'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('选择检查'));
      await tester.pump();
      expect(tester.widget<SizeTransition>(toolbar).sizeFactor.value, 1);
      expect(haptics, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'creation picks artworks only from the base or reference source chooser',
    (tester) async {
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('从作品选择图片'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('添加人物、构图或风格参考'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加人物、构图或风格参考'));
      await tester.pumpAndSettle();
      expect(find.text('从相册选择'), findsOneWidget);
      expect(find.text('从作品选择'), findsOneWidget);
      await tester.tap(find.text('从作品选择'));
      await tester.pumpAndSettle();
      expect(find.text('还没有作品，可先从相册添加'), findsOneWidget);
      expect(store.usage, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'vision is the third sibling connection tab and quantity plus remains reachable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(StudioHome));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConnectionScreen(store: store, api: StudioApi(store)),
        ),
      );
      await tester.pumpAndSettle();
      final segment = tester.widget<GlassSegments>(
        find.byType(GlassSegments).last,
      );
      expect(segment.labels, ['生图模型', '对话模型', '识图模型']);
      expect(find.text('识图模型配置'), findsNothing);
      await tester.tap(find.text('识图模型'));
      await tester.pumpAndSettle();
      expect(find.text('使用对话模型 API Key'), findsOneWidget);
      expect(find.text('模型 ID'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(ConnectionScreen))).pop();
      await tester.pumpAndSettle();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsDetail(
            title: '生成规格',
            children: [GenerationSettings(initial: store.defaults)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('增加数量'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      final plus = find.byTooltip('增加数量');
      final plusRect = tester.getRect(plus);
      expect(plusRect.left, greaterThan(0));
      expect(plusRect.right, lessThanOrEqualTo(390));
      expect(
        find.descendant(of: plus, matching: find.byIcon(Icons.add_rounded)),
        findsOneWidget,
      );
      await tester.tap(plus);
      await tester.pumpAndSettle();
      expect(store.defaults.count, 2);
      expect(find.text('2 张'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('export controls restore format quality and gallery preference', (
    tester,
  ) async {
    await store.prefs.setInt('export_format', 2);
    await store.prefs.setInt('export_quality', 79);
    await store.prefs.setBool('export_gallery', false);
    await tester.pumpWidget(LiuguangApp(store: store));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(StudioHome));
    glassSheet<void>(context, const ExportSheet());
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(ExportSheet));
    expect(state.format, 2);
    expect(state.quality, 79);
    expect(state.gallery, isFalse);
    state.setState(() {
      state.format = 1;
      state.quality = 85;
      state.gallery = true;
    });
    await tester.pumpAndSettle();
    expect(store.prefs.getInt('export_format'), 1);
    expect(store.prefs.getInt('export_quality'), 85);
    expect(store.prefs.getBool('export_gallery'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'secondary pages and spacing survive narrow layouts and larger system text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final screens = <Widget Function()>[
        () => ConnectionScreen(store: store, api: StudioApi(store)),
        () => AppearanceSettings(store: store),
        () => InteractionSettings(store: store),
        () => PersonalizationSettings(store: store),
        () => DesktopIconSettings(store: store),
        () => StorageSettings(store: store),
        () => UsageScreen(store: store),
        () => const SettingsDetail(title: '关于琉光', children: [AboutStudio()]),
        () => const SettingsDetail(title: '隐私与数据', children: [PrivacyInfo()]),
        () => const StudioLicensesScreen(),
        () => const MaterialPicker(),
        () => GifComposer(store: store),
        () => SettingsDetail(
          title: '生成规格',
          children: [GenerationSettings(initial: store.defaults)],
        ),
        () => us.UpdatesScreen(store: store, service: FakeUpdates(store)),
        () => SettingsDetail(
          title: '专业参数',
          children: [
            ProfessionalControls(
              options: GenerationOptions(
                advanced: {'seed': 42, 'steps': 30, 'guidance_scale': 7.5},
              ),
              onChanged: () {},
            ),
          ],
        ),
        () => const SettingsDetail(title: '导出', children: [ExportSheet()]),
      ];
      for (final theme in ['light', 'dark']) {
        store.theme = theme;
        store.textScale = 1.25;
        await tester.pumpWidget(LiuguangApp(store: store));
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(StudioHome));
        for (final make in screens) {
          final screen = make();
          debugPrint('Spacing QA: $theme ${screen.runtimeType}');
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => screen));
          await tester.pump(const Duration(milliseconds: 450));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
          await tester.runAsync(() async {
            if (screen is StorageSettings) {
              final dynamic state = tester.state(
                find.byType(StorageSettings, skipOffstage: false),
              );
              await state.scan();
            }
            if (screen is StudioLicensesScreen) {
              final dynamic state = tester.state(
                find.byType(StudioLicensesScreen, skipOffstage: false),
              );
              await state.future;
            }
          });
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$theme ${screen.runtimeType} top',
          );
          final vertical = find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          );
          if (vertical.evaluate().isNotEmpty) {
            final state = tester.state<ScrollableState>(vertical.last);
            for (
              var i = 0;
              i < 30 && state.position.pixels < state.position.maxScrollExtent;
              i++
            ) {
              state.position.jumpTo(
                (state.position.pixels + 450).clamp(
                  0,
                  state.position.maxScrollExtent,
                ),
              );
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '$theme ${screen.runtimeType} scroll $i',
              );
            }
          }
          Navigator.of(context).pop();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'GIF can derive motion from only an image and merge optional user direction',
    (tester) async {
      store.imageApi = EndpointConfig(
        baseUrl: 'http://127.0.0.1:1/v1',
        key: 'fixture-only',
        model: 'gpt-image-2.6-sunburst',
        protocol: ApiProtocol.gptImage,
      );
      store.defaults.format = 'gif';
      final api = MotionFixtureApi(store);
      await tester.pumpWidget(LiuguangApp(store: store, api: api));
      await tester.pumpAndSettle();
      final dynamic creation = tester.state(find.byType(CreateScreen));
      creation.references.add(fixture);
      creation.base = 'unused-base-do-not-read.png';
      await tester.runAsync(() async {
        await creation.generate();
        ScaffoldMessenger.of(tester.element(find.byType(StudioHome)))
            .removeCurrentSnackBar();
        creation.results.clear();
        creation.references.clear();
      });
      await tester.pumpAndSettle();
      expect(api.visionCalls, 1);
      expect(api.generationCalls, 1);
      expect(api.receivedPath, fixture);
      expect(api.receivedOptions!.size, '96x64');
      expect(api.receivedPrompt, contains('风轻拂树梢'));
      expect(store.artworks.single.prompt, contains('无缝循环'));
      creation.prompt.text = '只让湖面荡漾，树木静止';
      creation.references.add(fixture);
      await tester.runAsync(() async {
        await creation.generate();
        ScaffoldMessenger.of(tester.element(find.byType(StudioHome)))
            .removeCurrentSnackBar();
        creation.results.clear();
        creation.references.clear();
      });
      await tester.pumpAndSettle();
      expect(api.visionCalls, 2);
      expect(api.generationCalls, 2);
      expect(api.receivedPrompt, contains('只让湖面荡漾，树木静止'));
      expect(api.receivedPrompt, contains('以用户要求为优先'));
      expect(store.usage, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    },
  );

  testWidgets(
    'all six editor panels remain scrollable in both themes with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      final dynamic home = tester.state(find.byType(StudioHome));
      home.edit(fixture);
      home.editorPath = null;
      await tester.pump();
      await tester.runAsync(() async {
        final dynamic editor = tester.state(find.byType(EditorScreen));
        await editor.load(fixture);
      });
      await tester.pumpAndSettle();
      final dynamic editor = tester.state(find.byType(EditorScreen));
      for (final theme in ['light', 'dark']) {
        store.theme = theme;
        store.textScale = 1.25;
        store.refresh();
        await tester.pumpAndSettle();
        for (var tool = 0; tool < 6; tool++) {
          editor.setState(() => editor.tool = tool);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$theme editor tool $tool',
          );
          final vertical = find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          );
          final state = tester.state<ScrollableState>(vertical.last);
          for (
            var i = 0;
            i < 20 && state.position.pixels < state.position.maxScrollExtent;
            i++
          ) {
            state.position.jumpTo(
              (state.position.pixels + 250).clamp(
                0,
                state.position.maxScrollExtent,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$theme editor tool $tool scroll $i',
            );
          }
        }
      }
      expect(store.usage, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
    },
  );

  testWidgets(
    'library GIF entry enforces the model family and opens native creation',
    (tester) async {
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作品').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('原生 GIF 创作'));
      await tester.pumpAndSettle();
      expect(find.text('当前模型暂不支持 GIF'), findsOneWidget);
      expect(find.byType(GifComposer), findsNothing);
      store.imageApi.model = 'gpt-image-2.6-sunburst';
      store.refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('原生 GIF 创作'));
      await tester.pumpAndSettle();
      final dynamic home = tester.state(find.byType(StudioHome));
      expect(home.index, 0);
      expect(store.defaults.format, 'gif');
      expect(store.imageApi.protocol, ApiProtocol.gptImage);
      expect(store.usage, isEmpty);
      ScaffoldMessenger.of(tester.element(find.byType(StudioHome)))
          .removeCurrentSnackBar();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'storage optimization confirms replacement, protects referenced photos and keeps animation',
    (tester) async {
      final original = File('${dir.path}/compress-me.png');
      final protected = File('${dir.path}/keep-me.png');
      final bitmap = image.fill(
        image.Image(width: 96, height: 64),
        color: image.ColorRgb8(60, 100, 150),
      );
      final animation = File('${dir.path}/keep.gif');
      await tester.runAsync(() async {
        await original.writeAsBytes(image.encodePng(bitmap));
        await protected.writeAsBytes(image.encodePng(bitmap));
        await animation.writeAsBytes([71, 73, 70, 56, 57, 97]);
      });
      Artwork art(String id, String path) => Artwork(
        id: id,
        path: path,
        prompt: 'unchanged',
        model: 'offline',
        kind: '导入',
        created: DateTime(2026),
        width: 96,
        height: 64,
      );
      store.artworks.addAll([
        art('compact', original.path),
        art('protected', protected.path),
        art('animation', animation.path),
      ]);
      final webp = base64Decode(
        'UklGRlAAAABXRUJQVlA4IEQAAAAwBACdASpgAEAAPj0ejkUiIaEQtAAgA8S0gDsAAAwrs2bNmzZs2bNmiAAA/vCFD//8lP8Xfebv///9izlsCxAAAAAAAA==',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('liuguang/native'),
            (call) async => call.method == 'encodeWebp' ? webp : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('liuguang/native'),
              null,
            ),
      );
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      await store.prefs.setStringList('creation_references', [protected.path]);
      final context = tester.element(find.byType(StudioHome));
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => StorageSettings(store: store)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.runAsync(() async {
        final dynamic storage = tester.state(
          find.byType(StorageSettings, skipOffstage: false),
        );
        await storage.scan();
      });
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('计算可节省空间'));
      await tester.pumpAndSettle();
      final dynamic storageState = tester.state(find.byType(StorageSettings));
      late Future<void> operation;
      await tester.runAsync(() async {
        operation = storageState.optimize();
      });
      await tester.pumpAndSettle();
      expect(find.text('预览作品压缩结果？'), findsOneWidget);
      await tester.tap(find.text('确认'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(() async {
        final dynamic storage = tester.state(find.byType(StorageSettings));
        for (var i = 0; i < 250 && storage.done == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump(const Duration(milliseconds: 450));
      expect(
        find.textContaining('可节省 '),
        findsOneWidget,
        reason:
            'visible: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' / ')}; done=${storageState.done}, busy=${storageState.optimizing}',
      );
      expect(await tester.runAsync(() => original.exists()), isTrue);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.ensureVisible(find.text('确认'));
      await tester.tap(find.text('确认'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(
        () => operation.timeout(const Duration(seconds: 5)),
      );
      await tester.pumpAndSettle();
      final result = store.artworks.firstWhere((a) => a.id == 'compact');
      expect(result.path, endsWith('.webp'));
      expect(result.prompt, 'unchanged');
      await tester.runAsync(() async {
        expect(await original.exists(), isFalse);
        expect(await File(result.path).exists(), isTrue);
        expect(await protected.exists(), isTrue);
        expect(await animation.readAsBytes(), [71, 73, 70, 56, 57, 97]);
      });
      expect(
        store.artworks.firstWhere((a) => a.id == 'protected').path,
        protected.path,
      );
      expect(store.usage, isEmpty);
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
    },
  );
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
      await tester.tap(find.text('个性化'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();
      expect(find.text('显示模式'), findsOneWidget);
      expect(find.text('主题氛围'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('玻璃材质'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
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
    await tester.scrollUntilVisible(
      find.text('4K · 1:1'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('4K · 1:1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9:16'));
    await tester.tap(find.text('2K'));
    expect(find.text('应用规格'), findsNothing);
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
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
        '1.0.8',
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
      expect(find.byType(Dialog), findsOneWidget);
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
  testWidgets('close image resets editor and confirms unexported changes', (
    tester,
  ) async {
    await tester.pumpWidget(LiuguangApp(store: store));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(StudioHome));
    Future<void> open() async {
      home.edit(fixture);
      // Load file I/O explicitly inside runAsync instead of the fake asset zone.
      home.editorPath = null;
      await tester.pump();
      await tester.runAsync(() async {
        final dynamic editor = tester.state(find.byType(EditorScreen));
        await editor.load(fixture);
        editor.analyzeLens = false;
      });
      await tester.pumpAndSettle();
      home.editorPath = fixture;
    }

    await open();
    await tester.tap(find.byTooltip('关闭图片'));
    await tester.pumpAndSettle();
    expect(find.text('用示例照片体验'), findsOneWidget);
    expect(home.editorPath, isNull);
    await open();
    final dynamic editor = tester.state(find.byType(EditorScreen));
    editor.a.values[0] = .25;
    await tester.tap(find.byTooltip('关闭图片'));
    await tester.pumpAndSettle();
    expect(find.text('关闭当前图片？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(editor.image, isNotNull);
    await tester.tap(find.byTooltip('关闭图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('用示例照片体验'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    expect(File(fixture).existsSync(), isTrue);
    expect(store.artworks, isEmpty);
    expect(tester.takeException(), isNull);
  });
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
        editor.analyzeLens = false;
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
      await tester.ensureVisible(find.text('开始增强'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('开始增强'));
        for (var i = 0; i < 100 && api.calls < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(api.calls, 2);
      await tester.tap(find.byTooltip('关闭图片'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('取消任务并关闭图片？'), findsOneWidget);
      await tester.tap(find.text('确认'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('用示例照片体验'), findsOneWidget);
      expect(find.byType(TaskStatusCard), findsNothing);
      expect(api.calls, 2);
      expect(store.artworks, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'long press selects inline without a popup and sharing is a peer action',
    (tester) async {
      store.artworks.add(
        Artwork(
          id: 'menu-fixture',
          path: '$fixture.missing',
          prompt: 'offline',
          model: 'fixture',
          kind: '本地菜单样例',
          created: DateTime(2026),
          width: 96,
          height: 64,
        ),
      );
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作品').last);
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.ensureVisible(find.text('本地菜单样例'));
        await tester.pumpAndSettle();
        await tester.longPress(find.text('本地菜单样例'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('分享图'), findsOneWidget);
        expect(find.text('全选'), findsOneWidget);
        expect(find.text('删除所选'), findsOneWidget);
        expect(find.text('已选 1 件'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('本地菜单样例'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('本地菜单样例'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享图'));
      await tester.pumpAndSettle();
      expect(find.text('极光柔彩'), findsOneWidget);
      expect(find.text('午夜光影'), findsOneWidget);
      expect(find.text('纯白画廊'), findsOneWidget);
      expect(find.textContaining('3072 px 超清 · 本地排版'), findsOneWidget);
      expect(store.usage, isEmpty);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'three offline sharing templates export distinct 3072 pixel PNG files',
    (tester) async {
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      final art = Artwork(
        id: 'template-fixture',
        path: fixture,
        prompt: '晨光中的山脉',
        model: 'offline',
        kind: '景深增强',
        created: DateTime(2026),
        width: 96,
        height: 64,
      );
      final lengths = <int>[];
      await tester.runAsync(() async {
        for (var i = 0; i < 3; i++) {
          final file = await renderArtworkCard(
            store,
            art,
            includePrompt: i != 1,
            template: i,
          );
          final bytes = await file.readAsBytes();
          if (Platform.environment['LIUGUANG_VISUAL_QA'] == '1') {
            await Directory('tools/.cache').create(recursive: true);
            await file.copy('tools/.cache/share-template-$i.png');
          }
          final decoder = image.PngDecoder();
          final dimensions = decoder.startDecode(bytes)!;
          expect(dimensions.width, 3072);
          expect(dimensions.height, greaterThan(2000));
          lengths.add(bytes.length);
        }
      });
      expect(lengths.toSet().length, 3);
      expect(store.usage, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
