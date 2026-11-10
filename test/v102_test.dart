import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liuguang/core/api.dart';
import 'package:liuguang/core/appearance.dart';
import 'package:liuguang/core/imaging.dart';
import 'package:liuguang/core/materials.dart';
import 'package:liuguang/core/models.dart';
import 'package:liuguang/core/store.dart';
import 'package:liuguang/main.dart';
import 'package:liuguang/screens/editor.dart';
import 'package:liuguang/screens/materials.dart';
import 'package:liuguang/screens/personalization.dart';
import 'package:liuguang/screens/settings.dart';
import 'package:liuguang/ui/glass.dart';

class OfflineImageApi extends StudioApi {
  String? receivedPrompt;
  GenerationOptions? receivedOptions;
  int calls = 0;
  final Uint8List output;
  OfflineImageApi(super.store, this.output);
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
    receivedPrompt = prompt;
    receivedOptions = options;
    return ImageReply([output]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all material previews are bundled, decodable and have original prompt suffixes', () {
    expect(studioMaterials.length, 32);
    expect(studioMaterials.map((m) => m.id).toSet().length, 32);
    expect(studioMaterials.where((m) => m.category == '光透').length, 8);
    expect(studioMaterials.where((m) => m.category == '毛绒').length, 6);
    for (final m in studioMaterials) {
      final image = img.decodeWebP(File(m.preview).readAsBytesSync())!;
      expect(image.width, 256);
      expect(image.height, 256);
      expect(withMaterial('原始提示词，不修改', m.id), startsWith('原始提示词，不修改\n\n'));
    }
    expect(withMaterial('原文', null), '原文');
  });
  test('original-size finishing retains canvas and records native model resolution', () {
    final image = img.Image(width: 48, height: 32, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(110, 140, 170));
    final bytes = img.encodePng(image);
    final result = finishLensImage({
      'bytes': bytes,
      'style': 0,
      'strength': .72,
      'width': 601,
      'height': 401,
    });
    final finalImage = img.decodePng(result['bytes'])!;
    expect((finalImage.width, finalImage.height), (601, 401));
    expect((result['modelWidth'], result['modelHeight']), (48, 32));
    expect(finalImage.getPixel(250, 150).r, isNot(110));
    final zero = finishLensImage({'bytes': bytes, 'style': 0, 'strength': 0.0});
    expect(img.decodePng(zero['bytes'])!.getPixel(20, 20).r, 110);
    expect(originalPhotoRequest(7680, 4320).size, '4096x2304');
    final bounded = originalPhotoRequest(8000, 6000);
    expect(bounded.width * bounded.height, lessThanOrEqualTo(33554432));
    expect(bounded.width % 16, 0);
    expect(bounded.height % 16, 0);
    expect(AppStore().defaults.size, '4096x4096');
  });
  test('all adaptive launcher combinations have registered assets and only one default launcher', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    var count = 0;
    for (final g in launcherGlyphs.keys) {
      for (final c in launcherColors.keys) {
        for (final m in launcherMaterials.keys) {
          final id = '${g}_${c}_$m';
          expect(
            manifest,
            contains('android:name=".Launcher_$id" android:enabled="false"'),
          );
          expect(
            File('android/app/src/main/res/drawable/icon_$id.webp')
                .existsSync(),
            isTrue,
          );
          count++;
        }
      }
    }
    expect(count, 96);
    expect(
      RegExp(r'activity-alias[^>]*android:enabled="true"')
          .allMatches(manifest)
          .length,
      1,
    );
  });

  late AppStore store;
  late Directory directory;
  late String fixture;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('liuguang_v102_');
    fixture = '${directory.path}/source.png';
    final photo = img.Image(width: 96, height: 64, numChannels: 3);
    img.fill(photo, color: img.ColorRgb8(110, 140, 170));
    await File(fixture).writeAsBytes(img.encodePng(photo));
    store = AppStore()
      ..prefs = await SharedPreferences.getInstance()
      ..directory = directory;
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  testWidgets(
    'material browsing has optical and plush previews and survives mode switches',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('主体 · 场景 · 光线 · 风格'), findsNothing);
      expect(find.byTooltip('清空提示词'), findsOneWidget);
      await tester.ensureVisible(find.text('保留原有材质'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留原有材质'));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialPicker), findsOneWidget);
      expect(find.text('液态玻璃'), findsOneWidget);
      await tester.tap(find.text('毛绒'));
      await tester.pumpAndSettle();
      expect(find.text('长毛绒'), findsOneWidget);
      await tester.tap(find.text('长毛绒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用 · 长毛绒'));
      await tester.pumpAndSettle();
      expect(find.text('长毛绒'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('图生图'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('图生图'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MaterialSelection>(find.byType(MaterialSelection))
            .selected,
        'long_fur',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a whole palette changes global appearance and icon selection persists through native bridge',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('liuguang/native'),
        (call) async {
          if (call.method == 'setLauncherIcon') calls.add(call.arguments['id']);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('liuguang/native'),
          null,
        ),
      );
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      final nav = Navigator.of(tester.element(find.byType(StudioHome)));
      nav.push(
        MaterialPageRoute(builder: (_) => AppearanceSettings(store: store)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('青屿潮汐'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('青屿潮汐'));
      await tester.pumpAndSettle();
      expect(store.palette, 'lagoon');
      expect(store.accent, paletteById('lagoon').primary);
      expect(
        jsonDecode(store.prefs.getString('settings')!)['palette'],
        'lagoon',
      );
      nav.pop();
      await tester.pumpAndSettle();
      nav.push(
        MaterialPageRoute(
          builder: (_) => PersonalizationSettings(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('鸢尾星云'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('鸢尾星云'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('鸢尾星云'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('应用桌面图标'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('应用桌面图标'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用桌面图标'));
      await tester.pumpAndSettle();
      expect(calls, ['orbit_violet_glass']);
      expect(store.launcherIcon, calls.single);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'offline lens processing uses original canvas and separated mask controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      store.imageApi = EndpointConfig(
        baseUrl: 'https://offline.invalid/v1',
        key: 'fake-offline-key',
        model: 'fixture',
      );
      final api = OfflineImageApi(
        store,
        img.encodePng(img.Image(width: 48, height: 32, numChannels: 3)),
      );
      await tester.pumpWidget(LiuguangApp(store: store, api: api));
      await tester.pumpAndSettle();
      final dynamic home = tester.state(find.byType(StudioHome));
      home.edit(fixture);
      await tester.pump();
      final dynamic editor = tester.state(find.byType(EditorScreen));
      await tester.runAsync(() async {
        await editor.load(fixture);
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('传奇二瞬'));
      await tester.pumpAndSettle();
      final start = find.text('开始增强');
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(start);
        for (
          var i = 0;
          i < 200 && (store.artworks.isEmpty || editor.busy);
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      expect(api.receivedPrompt, contains('经典电影'));
      expect(
        (store.artworks.single.width, store.artworks.single.height),
        (48, 32),
      );
      expect(
        (store.artworks.single.modelWidth, store.artworks.single.modelHeight),
        (48, 32),
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await tester.tap(find.text('人像美化'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('AI 美化'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 美化'));
      await tester.pumpAndSettle();
      expect(find.text('开始 AI 美化'), findsOneWidget);
      await tester.runAsync(() async {
        await editor.cloudEdit(portrait: true);
      });
      await tester.pumpAndSettle();
      expect(api.calls, 2);
      expect(api.receivedPrompt, contains('保持原图人物身份'));
      expect(api.receivedOptions!.resolution, '4K');
      expect(store.artworks.first.kind, 'AI 人像美化');
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('局部修图'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('局部修图'));
      await tester.pumpAndSettle();
      final slider = find.byType(GlassSlider).first;
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final checkbox = find.byType(GlassCheckbox).first;
      expect(
        tester.getTopLeft(checkbox).dy - tester.getBottomLeft(slider).dy,
        greaterThanOrEqualTo(20),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      tester.binding.imageCache.clear();
      tester.binding.imageCache.clearLiveImages();
      // Hidden library thumbnails can still be finishing a Windows file read.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
    },
  );
}
