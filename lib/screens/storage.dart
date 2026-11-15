import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/imaging.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/glass.dart';
import 'settings.dart';

class StorageSettings extends StatefulWidget {
  final AppStore store;
  const StorageSettings({super.key, required this.store});
  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  int total = 0, works = 0, cache = 0, done = 0;
  bool busy = false, optimizing = false;
  late int quality = (widget.store.prefs.getInt('storage_quality') ?? 88).clamp(
    60,
    100,
  );
  final disposable = <File>[];
  @override
  void initState() {
    super.initState();
    scan();
  }

  Future<void> scan() async {
    setState(() => busy = true);
    final retained = widget.store.artworks
        .map((a) => File(a.path).absolute.path)
        .toSet();
    var t = 0, w = 0, c = 0;
    disposable.clear();
    try {
      await for (final entity in widget.store.directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final size = await entity.length();
        t += size;
        if (retained.contains(entity.absolute.path)) {
          w += size;
        } else if (entity.path.contains('share_cache') ||
            entity.path.contains('optimization_cache') ||
            entity.path.endsWith('.tmp')) {
          c += size;
          disposable.add(entity);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          total = t;
          works = w;
          cache = c;
          busy = false;
        });
      }
    }
  }

  Future<void> optimize() async {
    if (busy || optimizing) return;
    if (!await confirm(
      context,
      '预览作品压缩结果？',
      '以 WebP 重新编码静态作品，保留像素尺寸和提示词。GIF 动画跳过。先计算实际节省量，再确认是否替换；质量 $quality，可能产生细微画质变化。',
    )) {
      return;
    }
    setState(() {
      optimizing = true;
      done = 0;
    });
    final candidates = <(Artwork, Artwork)>[];
    var saved = 0;
    final folder = Directory(
      '${widget.store.directory.path}/optimization_cache',
    );
    try {
      await beginProcessing(local: true);
      await folder.create(recursive: true);
      final protectedPaths = <String>{
        ...widget.store.prefs.getStringList('creation_references') ?? [],
        widget.store.prefs.getString('creation_base') ?? '',
      };
      try {
        final checkpoint = jsonDecode(
          widget.store.prefs.getString('editor_checkpoint') ?? '{}',
        );
        if (checkpoint is Map && checkpoint['path'] is String) {
          protectedPaths.add(checkpoint['path']);
        }
        if (checkpoint is Map && checkpoint['comparisonPath'] is String) {
          protectedPaths.add(checkpoint['comparisonPath']);
        }
      } catch (_) {
        /* A corrupt editor checkpoint must not affect the artwork catalog. */
      }
      for (final art in widget.store.artworks.toList()) {
        if (art.path.toLowerCase().endsWith('.gif') ||
            protectedPaths.contains(art.path)) {
          continue;
        }
        final result = await renderEdited(
          art.path,
          Adjustments(),
          format: 'webp',
          quality: quality,
        );
        final oldSize = await File(art.path).length();
        final bytes = result['bytes'];
        if (bytes.length < oldSize) {
          final path =
              '${folder.path}/${art.id}-${DateTime.now().microsecondsSinceEpoch}.webp';
          await File(path).writeAsBytes(bytes, flush: true);
          final replacement = Artwork.fromJson({
            ...art.toJson(),
            'path': path,
            'parameters': {
              ...art.parameters,
              'storageQuality': quality,
              'storageFormat': 'webp',
            },
          });
          candidates.add((art, replacement));
          saved += oldSize - (bytes.length as int);
        }
        if (mounted) setState(() => done++);
      }
      if (!mounted) return;
      if (candidates.isEmpty) {
        toast(context, '当前作品已经很精简，无需替换');
        return;
      }
      final accepted = await confirm(
        context,
        '可节省 ${mb(saved)}',
        '${candidates.length} 件作品可减小体积，像素尺寸保持不变。确认后替换应用内文件，系统相册原片保留。',
      );
      if (!accepted) return;
      // Commit the new catalog before removing old app-owned files.
      final before = widget.store.artworks.toList();
      final remap = {for (final pair in candidates) pair.$1.id: pair.$2};
      widget.store.artworks = before.map((a) => remap[a.id] ?? a).toList();
      try {
        await widget.store.saveCatalog();
      } catch (_) {
        widget.store.artworks = before;
        rethrow;
      }
      var freed = 0;
      final canonicalRoot = await widget.store.directory.resolveSymbolicLinks();
      final prefix = '$canonicalRoot${Platform.pathSeparator}';
      for (final pair in candidates) {
        final original = File(pair.$1.path);
        if (protectedPaths.contains(pair.$1.path)) continue;
        try {
          final canonical = await original.resolveSymbolicLinks();
          final owned = Platform.isWindows
              ? canonical.toLowerCase().startsWith(prefix.toLowerCase())
              : canonical.startsWith(prefix);
          if (!owned) continue;
          final oldBytes = await original.length();
          await original.delete();
          freed += oldBytes - await File(pair.$2.path).length();
        } catch (_) {
          /* Catalog already points to the complete replacement. */
        }
      }
      if (mounted) {
        toast(
          context,
          '已优化 ${candidates.length} 件作品，净释放 ${mb(freed.clamp(0, 1 << 60))}',
        );
      }
    } catch (e) {
      if (mounted) toast(context, describeError(e));
    } finally {
      final retained = widget.store.artworks.map((a) => a.path).toSet();
      for (final pair in candidates) {
        if (!retained.contains(pair.$2.path)) {
          try {
            await File(pair.$2.path).delete();
          } catch (_) {}
        }
      }
      await endProcessing(local: true);
      if (mounted) {
        setState(() => optimizing = false);
        await scan();
      }
    }
  }

  String mb(int value) => '${(value / 1048576).toStringAsFixed(1)} MB';
  @override
  Widget build(BuildContext context) => SettingsDetail(
    title: '存储管理',
    children: [
      Glass(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in [
              ('应用数据', total),
              ('作品文件', works),
              ('可清理临时缓存', cache),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.$1,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      mb(item.$2),
                      style: TextStyle(fontSize: 14, color: muted(context)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      GlassButton(
        '清理分享与临时缓存',
        busy: busy,
        onTap: busy || optimizing
            ? null
            : () async {
                if (!await confirm(context, '清理临时缓存？', '不会删除作品、原图、Key 或设置。')) {
                  return;
                }
                for (final file in disposable.toList()) {
                  if (await file.exists()) await file.delete();
                }
                await scan();
              },
      ),
      const SectionLabel('作品体积优化'),
      Glass(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '保留分辨率 · 仅压缩静态作品',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ink(context),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '自动跳过 GIF、正在编辑或引用的图片，以及压缩后更大的文件。先预览节省量，再确认替换。',
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: muted(context),
              ),
            ),
            const SizedBox(height: 20),
            GlassSlider(
              label: 'WebP 编码质量',
              valueLabel: '$quality',
              value: quality.toDouble(),
              min: 60,
              max: 100,
              onChanged: optimizing
                  ? (_) {}
                  : (v) {
                      setState(() => quality = v.round());
                      widget.store.prefs.setInt('storage_quality', quality);
                    },
            ),
            const SizedBox(height: 20),
            GlassButton(
              optimizing ? '已检查 $done 件作品' : '计算可节省空间',
              busy: optimizing,
              icon: Icons.compress_rounded,
              onTap: busy || optimizing ? null : optimize,
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Text(
        '统计当前应用内作品与数据文件。系统相册、安装包和系统管理的缓存不计入此处。',
        style: TextStyle(fontSize: 12, height: 1.7, color: muted(context)),
      ),
    ],
  );
}
