import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liuguang/core/models.dart';
import 'package:liuguang/core/imaging.dart';
import 'package:liuguang/core/store.dart';
import 'package:liuguang/main.dart';
import 'package:liuguang/screens/settings.dart';
import 'package:liuguang/screens/updates.dart';

void main() {
  test('source aspect snaps to supported ratios at only 1, 2 or 4K', () {
    for (final pair in [
      (1, 1),
      (3, 4),
      (4, 3),
      (2, 3),
      (3, 2),
      (9, 16),
      (16, 9),
    ]) {
      for (final k in [1, 2, 4]) {
        final o = matchedPhotoOptions(
          pair.$1 * 100,
          pair.$2 * 100,
          edge: k * 1024,
        );
        expect(o.aspectLabel, '${pair.$1}:${pair.$2}');
        expect(o.resolution, '${k}K');
        expect(o.width % 16, 0);
        expect(o.height % 16, 0);
      }
    }
    expect(matchedPhotoOptions(1600, 1067).size, '4096x2736');
  });
  test(
    'local portrait presets preserve canvas and zero strength preserves pixels',
    () {
      final source = img.Image(width: 87, height: 63, numChannels: 3);
      img.fill(source, color: img.ColorRgb8(170, 120, 100));
      final bytes = img.encodePng(source);
      for (var style = 0; style < portraitNames.length; style++) {
        final unchanged = beautifyPortrait({
          'bytes': bytes,
          'style': style,
          'strength': 0.0,
        });
        expect(img.decodePng(unchanged['bytes'])!.getPixel(20, 20).r, 170);
        final result = beautifyPortrait({
          'bytes': bytes,
          'style': style,
          'strength': .8,
        });
        expect((result['width'], result['height']), (87, 63));
        expect(img.decodePng(result['bytes'])!.getPixel(20, 20).r, isNot(170));
      }
    },
  );
  testWidgets(
    'privacy uses readable cards and licenses open inside the studio theme',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore()..prefs = await SharedPreferences.getInstance();
      LicenseRegistry.addLicense(() async* {
        yield const LicenseEntryWithLineBreaks([
          'studio-test-package',
        ], 'A complete test license.');
      });
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      final nav = Navigator.of(tester.element(find.byType(StudioHome)));
      nav.push(
        MaterialPageRoute(
          builder: (_) =>
              const SettingsDetail(title: '隐私与数据', children: [PrivacyInfo()]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InfoHero), findsOneWidget);
      expect(find.text('密钥只留本机'), findsOneWidget);
      nav.pop();
      await tester.pumpAndSettle();
      nav.push(MaterialPageRoute(builder: (_) => const StudioLicensesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('与开源同行'), findsOneWidget);
      expect(find.byType(LicensePage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'update notes use the same categorized chips as the version history',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore()..prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(LiuguangApp(store: store));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(StudioHome))).push(
        MaterialPageRoute(
          builder: (_) => const SettingsDetail(
            title: '更新预览',
            children: [ReleaseNotesView(notes: '新增：人像美化\n修复：尺寸错误\n优化：页面布局')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChangeTag), findsNWidgets(3));
      expect(changeTagColor('新增', false), isNot(changeTagColor('修复', false)));
      expect(tester.takeException(), isNull);
    },
  );
}
