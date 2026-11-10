import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';
import '../ui/glass.dart';
import 'settings.dart' show SettingsDetail;

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
    if (!Platform.isAndroid) return fallback;
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

class PersonalizationSettings extends StatefulWidget {
  final AppStore store;
  const PersonalizationSettings({super.key, required this.store});
  @override
  State<PersonalizationSettings> createState() =>
      _PersonalizationSettingsState();
}

class _PersonalizationSettingsState extends State<PersonalizationSettings> {
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
    title: '个性化',
    children: [
      const SizedBox(height: 6),
      Center(child: LauncherPreview(id: selected, size: 112)),
      const SizedBox(height: 14),
      const Text(
        '琉光',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(
        selected == 'default' ? '当前为原始图标' : '让桌面也有自己的质感',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: muted(context)),
      ),
      const SectionLabel('图标造型'),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final entry in launcherGlyphs.entries)
            GestureDetector(
              onTap: saving ? null : () => choose(g: entry.key),
              child: Container(
                width: 72,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected != 'default' && glyph == entry.key
                      ? accent(context).withValues(alpha: .12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    LauncherPreview(
                      id: '${entry.key}_${color}_$material',
                      size: 54,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      entry.value,
                      style: TextStyle(fontSize: 12, color: ink(context)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const SectionLabel('图标颜色'),
      Glass(
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final entry in launcherColors.entries)
              Semantics(
                button: true,
                label: '图标颜色 ${entry.key}',
                selected: selected != 'default' && color == entry.key,
                child: GestureDetector(
                  onTap: saving ? null : () => choose(c: entry.key),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(entry.value),
                      shape: BoxShape.circle,
                    ),
                    child: selected != 'default' && color == entry.key
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
      const SectionLabel('图标材质'),
      Wrap(
        spacing: 12,
        runSpacing: 14,
        children: [
          for (final entry in launcherMaterials.entries)
            GestureDetector(
              onTap: saving ? null : () => choose(m: entry.key),
              child: Container(
                width: 140,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected != 'default' && material == entry.key
                      ? accent(context).withValues(alpha: .12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    LauncherPreview(
                      id: '${glyph}_${color}_${entry.key}',
                      size: 72,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      entry.value,
                      style: TextStyle(fontSize: 14, color: ink(context)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 26),
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
