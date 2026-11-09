import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api.dart';
import '../core/imaging.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/glass.dart';
import 'editor.dart';

class LibraryScreen extends StatefulWidget {
  final AppStore store;
  final ValueChanged<String> onEdit, onReuse;
  const LibraryScreen({
    super.key,
    required this.store,
    required this.onEdit,
    required this.onReuse,
  });
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int filter = 0;
  String query = '';
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.store.artworks
        .where(
          (a) =>
              (filter != 1 || a.favorite) &&
              (filter != 2 || a.path.endsWith('.gif')) &&
              (a.prompt.toLowerCase().contains(query.toLowerCase()) ||
                  a.kind.contains(query)),
        )
        .toList();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 5, 22, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                PageHeader(
                  title: '作品',
                  action: GlassIcon(
                    Icons.gif_box_outlined,
                    tooltip: '制作 GIF',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GifComposer(store: widget.store),
                      ),
                    ),
                  ),
                ),
                GlassField(
                  controller: search,
                  hint: '搜索作品',
                  onChanged: (v) => setState(() => query = v),
                  suffix: const Icon(Icons.search_rounded, size: 20),
                ),
                const SizedBox(height: 16),
                GlassSegments(
                  labels: const ['全部作品', '收藏', 'GIF'],
                  selected: filter,
                  onChanged: (i) => setState(() => filter = i),
                ),
                SectionLabel('${items.length} 件作品', caption: '长按删除'),
              ],
            ),
          ),
        ),
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.collections_outlined,
              title: filter == 1 ? '把喜欢，留在这里' : '暂无作品',
              subtitle: '生成与导出的照片会保存在这里。\n也可以导入照片，开始下一次创作。',
              action: GlassButton(
                '导入照片',
                icon: Icons.add_rounded,
                onTap: () async {
                  try {
                    final file = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                    );
                    if (file != null) {
                      final art = await saveArtwork(
                        widget.store,
                        await file.readAsBytes(),
                        prompt: '导入的照片',
                        model: '本地',
                        kind: '导入',
                      );
                      if (mounted) {
                        widget.onEdit(art.path);
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      toast(context, describeError(e));
                    }
                  }
                },
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((context, i) {
                final art = items[i];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () async {
                    if (await confirm(context, '删除作品？', '仅删除应用内副本，相册照片保留。') &&
                        mounted) {
                      await widget.store.removeArtwork(art);
                      if (mounted) setState(() {});
                    }
                  },
                  onTap: () => openArtwork(
                    context,
                    widget.store,
                    art,
                    widget.onEdit,
                    onReuse: widget.onReuse,
                  ),
                  child: Glass(
                    padding: EdgeInsets.zero,
                    radius: 22,
                    blur: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(art.path),
                                fit: BoxFit.cover,
                                cacheWidth: 600,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                              Positioned(
                                top: 9,
                                right: 9,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () async {
                                    art.favorite = !art.favorite;
                                    await widget.store.saveCatalog();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: const BoxDecoration(
                                      color: Colors.black38,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      art.favorite
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                art.kind,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${art.width} × ${art.height}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: muted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }, childCount: items.length),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 15,
                childAspectRatio: .76,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }
}

Future<void> openArtwork(
  BuildContext context,
  AppStore store,
  Artwork art,
  ValueChanged<String> onEdit, {
  ValueChanged<String>? onReuse,
}) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) =>
        ArtworkDetail(store: store, art: art, onEdit: onEdit, onReuse: onReuse),
  ),
);

class ArtworkDetail extends StatefulWidget {
  final AppStore store;
  final Artwork art;
  final ValueChanged<String> onEdit;
  final ValueChanged<String>? onReuse;
  const ArtworkDetail({
    super.key,
    required this.store,
    required this.art,
    required this.onEdit,
    this.onReuse,
  });
  @override
  State<ArtworkDetail> createState() => _ArtworkDetailState();
}

class _ArtworkDetailState extends State<ArtworkDetail> {
  bool busy = false;
  Future<void> action(Future<void> Function() run) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await run();
    } catch (e) {
      if (mounted) {
        toast(context, describeError(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final art = widget.art;
    return Scaffold(
      body: StudioBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Row(
                children: [
                  GlassIcon(
                    Icons.arrow_back_rounded,
                    tooltip: '返回',
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  GlassIcon(
                    art.favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    tooltip: '收藏',
                    onTap: () {
                      setState(() => art.favorite = !art.favorite);
                      widget.store.saveCatalog();
                    },
                  ),
                  const SizedBox(width: 9),
                  GlassIcon(
                    Icons.delete_outline_rounded,
                    tooltip: '删除作品',
                    onTap: () async {
                      if (await confirm(
                        context,
                        '删除这件作品？',
                        '将删除应用内的作品副本，系统相册中已保存的图片会保留。',
                      )) {
                        await widget.store.removeArtwork(art);
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 22),
              ClipRRect(
                borderRadius: BorderRadius.circular(27),
                child: SizedBox(
                  height: 380,
                  child: InteractiveViewer(
                    minScale: .5,
                    maxScale: 6,
                    child: Image.file(File(art.path), fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      '继续修图',
                      primary: true,
                      icon: Icons.tune_rounded,
                      onTap: () {
                        Navigator.pop(context);
                        widget.onEdit(art.path);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  GlassIcon(
                    Icons.ios_share_rounded,
                    tooltip: '分享',
                    onTap: () => action(() async {
                      await SharePlus.instance.share(
                        ShareParams(files: [XFile(art.path)], text: '由琉光创作'),
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GlassButton(
                busy ? '处理中…' : '保存到系统相册',
                icon: Icons.download_rounded,
                busy: busy,
                onTap: () => action(() async {
                  await saveToGallery(art.path);
                  if (context.mounted) {
                    toast(context, '已保存到 Pictures/琉光');
                  }
                }),
              ),
              const SizedBox(height: 12),
              GlassButton(
                '转换格式与压缩',
                small: true,
                onTap: () async {
                  final choice = await glassSheet<Map<String, dynamic>>(
                    context,
                    const ExportSheet(),
                  );
                  if (choice == null) {
                    return;
                  }
                  await action(() async {
                    final rendered = await renderEdited(
                      art.path,
                      Adjustments(),
                      format: choice['format'],
                      quality: choice['quality'],
                    );
                    final saved = await saveArtwork(
                      widget.store,
                      rendered['bytes'],
                      prompt: art.prompt,
                      model: '本地转换',
                      kind: '导出',
                    );
                    if (choice['gallery'] == true) {
                      await saveToGallery(saved.path);
                    }
                    if (context.mounted) {
                      toast(context, '格式转换完成，已另存副本');
                    }
                  });
                },
              ),
              const SectionLabel('作品信息'),
              Glass(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _meta(context, '分辨率', '${art.width} × ${art.height}'),
                    _meta(
                      context,
                      '格式',
                      art.path.split('.').last.toUpperCase(),
                    ),
                    _meta(context, '模型', art.model),
                    _meta(
                      context,
                      '时间',
                      art.created.toLocal().toString().split('.').first,
                    ),
                  ],
                ),
              ),
              SectionLabel(
                '提示词',
                action: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: art.prompt));
                    toast(context, '已复制');
                  },
                  child: Text(
                    '复制',
                    style: TextStyle(fontSize: 14, color: accentInk(context)),
                  ),
                ),
              ),
              Glass(
                child: SelectableText(
                  art.prompt,
                  style: const TextStyle(fontSize: 14, height: 1.9),
                ),
              ),
              if (widget.onReuse != null) ...[
                const SizedBox(height: 16),
                GlassButton(
                  '再次使用这段提示词',
                  small: true,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onReuse!(art.prompt);
                  },
                ),
              ],
              const SizedBox(height: 25),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _meta(BuildContext context, String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 64,
        child: Text(
          label,
          style: TextStyle(fontSize: 14, color: muted(context)),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontSize: 14),
          textAlign: TextAlign.right,
        ),
      ),
    ],
  ),
);

class GifComposer extends StatefulWidget {
  final AppStore store;
  const GifComposer({super.key, required this.store});
  @override
  State<GifComposer> createState() => _GifComposerState();
}

class _GifComposerState extends State<GifComposer> {
  List<String> frames = [];
  int duration = 500, colors = 256;
  bool busy = false;
  Future<void> pick() async {
    try {
      final files = await ImagePicker().pickMultiImage(limit: 12);
      if (mounted) {
        setState(() {
          frames.addAll(files.map((f) => f.path));
          if (frames.length > 12) {
            frames.removeRange(12, frames.length);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        toast(context, '$e');
      }
    }
  }

  Future<void> compose() async {
    if (frames.length < 2 || busy) {
      return;
    }
    setState(() => busy = true);
    try {
      final data = <Uint8List>[];
      for (final path in frames) {
        data.add(await File(path).readAsBytes());
      }
      final gif = await compute(encodeAnimation, {
        'frames': data,
        'duration': duration,
        'colors': colors,
      });
      final art = await saveArtwork(
        widget.store,
        gif,
        prompt: 'GIF 动画 · ${frames.length} 帧 · $duration ms/帧',
        model: '本地合成',
        kind: 'GIF',
      );
      await saveToGallery(art.path);
      if (mounted) {
        toast(context, 'GIF 已保存到作品与相册');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        toast(context, describeError(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: StudioBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GlassIcon(
                Icons.arrow_back_rounded,
                tooltip: '返回',
                onTap: () => Navigator.pop(context),
              ),
            ),
            const PageHeader(title: '制作 GIF'),
            Text(
              '添加 2–12 张照片，拖动调整帧顺序。不同尺寸会等比适配到第一帧画布，留白使用黑色。',
              style: TextStyle(
                fontSize: 14,
                color: muted(context),
                height: 1.8,
              ),
            ),
            const SizedBox(height: 16),
            GlassButton(
              '添加动画帧',
              icon: Icons.add_photo_alternate_outlined,
              onTap: busy ? null : pick,
            ),
            if (widget.store.artworks.isNotEmpty) ...[
              const SizedBox(height: 12),
              GlassButton(
                '从作品中添加',
                small: true,
                onTap: busy
                    ? null
                    : () async {
                        final path = await glassSheet<String>(
                          context,
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final art in widget.store.artworks.take(30))
                                ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(art.path),
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  title: Text(
                                    art.prompt,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => Navigator.pop(context, art.path),
                                ),
                            ],
                          ),
                        );
                        if (path != null && frames.length < 12 && mounted) {
                          setState(() => frames.add(path));
                        }
                      },
              ),
            ],
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: frames.length,
              onReorderItem: (old, next) => setState(() {
                frames.insert(next, frames.removeAt(old));
              }),
              itemBuilder: (_, i) => ListTile(
                key: ValueKey('$i-${frames[i]}'),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.file(
                    File(frames[i]),
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  ),
                ),
                title: Text(
                  '第 ${i + 1} 帧',
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: busy
                      ? null
                      : () => setState(() => frames.removeAt(i)),
                ),
              ),
            ),
            const SectionLabel('播放节奏'),
            Glass(
              child: GlassSlider(
                value: duration / 2000,
                min: .05,
                max: 1,
                label: '每帧 $duration ms',
                onChanged: (v) =>
                    setState(() => duration = (v * 2000 / 10).round() * 10),
              ),
            ),
            const SectionLabel('色彩精度'),
            GlassSegments(
              labels: const ['128 色 · 更小', '256 色 · 更细腻'],
              selected: colors == 128 ? 0 : 1,
              onChanged: (v) => setState(() => colors = v == 0 ? 128 : 256),
            ),
            const SizedBox(height: 24),
            GlassButton(
              '合成并保存 GIF',
              primary: true,
              busy: busy,
              icon: Icons.gif_rounded,
              onTap: frames.length < 2 ? null : compose,
            ),
            const SizedBox(height: 25),
          ],
        ),
      ),
    ),
  );
}
