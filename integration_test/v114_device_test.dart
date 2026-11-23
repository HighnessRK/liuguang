import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:liuguang/core/appearance.dart';
import 'package:liuguang/core/models.dart';
import 'package:liuguang/core/store.dart';
import 'package:liuguang/main.dart';
import 'package:liuguang/screens/library.dart';
import 'package:liuguang/screens/settings.dart';
import 'package:liuguang/ui/glass.dart';
import 'package:liuguang/ui/navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('USB artwork corners, GIF toast and global materials', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'update_auto': false});
    final dir = await Directory.systemTemp.createTemp('liuguang_v114_');
    final store = AppStore()
      ..directory = dir
      ..prefs = await SharedPreferences.getInstance();
    for (final (id, width, height) in [
      ('wide', 500, 220),
      ('tall', 220, 580),
    ]) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(210, 147, 45));
      final path = '${dir.path}/$id.jpg';
      await File(path).writeAsBytes(img.encodeJpg(image));
      store.artworks.add(
        Artwork(
          id: id,
          path: path,
          prompt: '',
          model: '',
          kind: id,
          created: DateTime(2026),
          width: width,
          height: height,
        ),
      );
    }
    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder.hitTestable());
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
    }

    Finder heroClip(String id) => find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is Hero && widget.tag == 'artwork_$id',
      ),
      matching: find.byType(ClipRRect),
    );
    Future<void> openWorks() async => tap(find.text('作品').last);
    Future<void> checkGallery() async {
      for (final id in ['wide', 'tall']) {
        expect(
          tester.widget<ClipRRect>(heroClip(id)).borderRadius,
          artworkTileCorners,
        );
        await tap(find.text(id));
        expect(
          tester.widget<ClipRRect>(heroClip(id)).borderRadius,
          artworkDetailCorners,
        );
        final size = tester.getSize(heroClip(id));
        expect(
          size.aspectRatio,
          closeTo(id == 'wide' ? 500 / 220 : 220 / 580, .002),
        );
        await tap(find.byTooltip('返回'));
      }
    }

    Finder navBarGlass() => find.descendant(
      of: find.byType(LiquidNavigation),
      matching: find.byWidgetPredicate((w) => w is Glass && w.liveBackdrop),
    );
    try {
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      await openWorks();
      await checkGallery();
      await tap(find.byTooltip('原生 GIF 创作'));
      final toast = find.text('GIF生成测试中，暂不支持使用');
      expect(tester.widget<Text>(toast).style!.decoration, TextDecoration.none);
      expect(
        tester.getTopLeft(toast).dy,
        lessThan(tester.getTopLeft(find.byType(LiquidNavigation)).dy),
      );
      await tap(find.text('设置').last);
      await tap(find.text('个性化'));
      await tap(find.text('外观'));
      final appearance = find.byType(AppearanceSettings);
      final toggle = find
          .descendant(of: appearance, matching: find.byType(GlassToggle))
          .last;
      expect(find.text('液态玻璃材质'), findsNothing);
      await tap(toggle);
      expect(store.advancedMaterials, isTrue);
      expect(store.glassMaterial, StudioMaterial.liquid);
      expect(find.text('液态玻璃材质'), findsOneWidget);
      await back();
      await back();
      await openWorks();
      expect(navBarGlass(), findsOneWidget);
      await checkGallery();
      await tap(find.text('设置').last);
      await tap(find.text('个性化'));
      await tap(find.text('外观'));
      await tap(find.text('高斯模糊材质'));
      final saved = jsonDecode(store.prefs.getString('settings')!) as Map;
      expect(saved['glassMaterial'], 'gaussian');
      expect(saved['advancedMaterials'], isTrue);
      await back();
      await back();
      await openWorks();
      expect(
        find.descendant(
          of: navBarGlass(),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      await checkGallery();
      await tap(find.text('设置').last);
      await tap(find.text('个性化'));
      await tap(find.text('外观'));
      await tap(toggle);
      expect(find.text('高斯模糊材质'), findsNothing);
      expect(store.glassMaterial, StudioMaterial.gaussian);
      expect(store.advancedMaterials, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await dir.delete(recursive: true);
    }
  });
}
