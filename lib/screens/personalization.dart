import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';
import '../ui/glass.dart';
import 'settings.dart' show SettingsDetail, AppearanceSettings, settingRow;

const launcherGlyphs = {
  'spark': '星芒',
  'aperture': '光圈',
  'orb': '琉珠',
  'orbit': '光轨',
};
const launcherColors = {
  'blue': 0xff5d86e2,
  'violet': 0xff9a72d5,
  'rose': 0xffd07b9e,
  'teal': 0xff59afa7,
  'amber': 0xffd3a365,
  'graphite': 0xff647589,
};
const launcherMaterials = {
  'glass': '液态玻璃',
  'frost': '细雾磨砂',
  'ceramic': '温润陶瓷',
  'plush': '柔软毛绒',
};
const _channel = MethodChannel('liuguang/native');
final _previews = <String, Future<Uint8List?>>{};

class LauncherPreview extends StatelessWidget {
  final String id;
  final double size;
  const LauncherPreview({super.key, required this.id, this.size = 64});
  @override
  Widget build(BuildContext context) {
    final parts = id.split('_');
    final color = Color(launcherColors[parts.length == 3 ? parts[1] : 'blue']!);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.white, .42)!],
        ),
      ),
      child: Icon(
        switch (parts.first) {
          'aperture' => Icons.camera_rounded,
          'orb' => Icons.blur_circular_rounded,
          'orbit' => Icons.all_inclusive_rounded,
          _ => Icons.auto_awesome_rounded,
        },
        size: size * .48,
        color: Colors.white,
      ),
    );
    if (!Platform.isAndroid) {
      return curatedIcons.containsKey(id) && id != 'default'
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size * .24),
              child: Image.asset(
                'assets/icons/$id.webp',
                width: size,
                height: size,
              ),
            )
          : fallback;
    }
    return FutureBuilder<Uint8List?>(
      future: _previews.putIfAbsent(
        id,
        () => _channel
            .invokeMethod<Uint8List>('launcherIconPreview', {'id': id})
            .catchError((_) => null),
      ),
      builder: (_, snapshot) => snapshot.data == null
          ? fallback
          : Image.memory(
              snapshot.data!,
              width: size,
              height: size,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            ),
    );
  }
}

class DesktopIconSettings extends StatefulWidget {
  final AppStore store;
  const DesktopIconSettings({super.key, required this.store});
  @override
  State<DesktopIconSettings> createState() => _PersonalizationSettingsState();
}

class _PersonalizationSettingsState extends State<DesktopIconSettings> {
  late String selected = widget.store.launcherIcon;
  String glyph = 'spark', color = 'blue', material = 'glass';
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final parts = selected.split('_');
    if (parts.length == 3) {
      glyph = parts[0];
      color = parts[1];
      material = parts[2];
    }
  }

  void choose({String? g, String? c, String? m}) => setState(() {
    glyph = g ?? glyph;
    color = c ?? color;
    material = m ?? material;
    selected = '${glyph}_${color}_$material';
  });
  Future<void> apply() async {
    setState(() => saving = true);
    try {
      await _channel.invokeMethod('setLauncherIcon', {'id': selected});
      widget.store.launcherIcon = selected;
      await widget.store.saveSettings();
      if (mounted) toast(context, '桌面图标已更新，系统桌面可能稍后刷新');
    } catch (_) {
      if (mounted) toast(context, '图标未能应用，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsDetail(
    title: '桌面图标',
    children: [
      LayoutBuilder(
        builder: (context, c) => Wrap(
          spacing: 14,
          runSpacing: 18,
          children: [
            for (final entry in curatedIcons.entries)
              SizedBox(
                width: (c.maxWidth - 14) / 2,
                child: GestureDetector(
                  onTap: saving
                      ? null
                      : () => setState(() => selected = entry.key),
                  child: Glass(
                    blur: false,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        LauncherPreview(id: entry.key, size: 72),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.value,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            if (selected == entry.key)
                              Icon(
                                Icons.check_circle_rounded,
                                color: accent(context),
                                size: 20,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      GlassButton(
        '应用桌面图标',
        primary: true,
        busy: saving,
        onTap: saving || selected == widget.store.launcherIcon ? null : apply,
      ),
      const SizedBox(height: 14),
      GlassButton(
        '恢复默认图标',
        small: true,
        onTap: saving
            ? null
            : () {
                setState(() => selected = 'default');
                apply();
              },
      ),
    ],
  );
}

const curatedIcons = {
  'default': '经典琉光',
  'orb_blue_glass': '极光之环',
  'orbit_teal_glass': '青屿流光',
  'orb_amber_glass': '日落鎏金',
  'orbit_violet_glass': '鸢尾星云',
  'orb_rose_glass': '蔷薇月色',
  'orbit_graphite_glass': '冰川月白',
  'spark_teal_glass': '森境微光',
  'spark_amber_glass': '赤陶余晖',
};

class PersonalizationSettings extends StatelessWidget {
  final AppStore store;
  const PersonalizationSettings({super.key, required this.store});
  @override
  Widget build(BuildContext context) => SettingsDetail(
    title: '个性化',
    children: [
      Glass(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            settingRow(
              context,
              Icons.palette_outlined,
              '外观',
              '主题氛围、深浅模式与玻璃材质',
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AppearanceSettings(store: store),
                ),
              ),
            ),
            Divider(height: 1, color: muted(context).withValues(alpha: .1)),
            settingRow(
              context,
              Icons.apps_rounded,
              '桌面图标',
              '选择完整图标设计',
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DesktopIconSettings(store: store),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
