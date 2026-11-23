import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/sticker_catalog.dart';
import '../core/store.dart';
import '../core/updates.dart';
import '../ui/glass.dart';
import 'custom_sticker.dart';

List<StickerProfile> orderedStickerProfiles(
  AppStore store,
  StickerProfile builtin,
) {
  final profiles = {
    for (final p in [builtin, ...readStickerProfiles(store)]) p.id: p,
  };
  return [
    for (final id
        in store.prefs.getStringList('sticker_profile_order') ??
            const <String>[])
      if (profiles.containsKey(id)) profiles.remove(id)!,
    ...profiles.values,
  ];
}

class StickerManager extends StatefulWidget {
  const StickerManager({
    super.key,
    required this.store,
    required this.builtin,
    required this.active,
    required this.builtinImage,
  });
  final AppStore store;
  final StickerProfile builtin, active;
  final ImageProvider builtinImage;

  @override
  State<StickerManager> createState() => _StickerManagerState();
}

class _StickerManagerState extends State<StickerManager> {
  late final catalog = StickerCatalog(widget.store);
  late final profiles = orderedStickerProfiles(widget.store, widget.builtin);
  final token = CancelToken();
  int tab = 0;
  Future<List<CloudSticker>>? remote;
  final downloading = <String>{};

  @override
  void dispose() {
    token.cancel();
    catalog.close();
    super.dispose();
  }

  void reorder(int from, int to) {
    if (from == to) return;
    setState(() => profiles.insert(to, profiles.removeAt(from)));
    widget.store.prefs.setStringList(
      'sticker_profile_order',
      profiles.map((p) => p.id).toList(),
    );
  }

  Future<void> download(CloudSticker item) async {
    if (!downloading.add(item.id)) return;
    setState(() {});
    try {
      final path = await catalog.download(item, token: token);
      final profile = StickerProfile(
        id: item.localId,
        name: item.name,
        description: withStickerProps(item.description),
        references: [path],
      );
      await saveStickerProfile(widget.store, profile);
      if (!mounted) return;
      setState(() {
        final existing = profiles.indexWhere((entry) => entry.id == profile.id);
        if (existing < 0) {
          profiles.add(profile);
        } else {
          profiles[existing] = profile;
        }
      });
      toast(context, '已下载「${item.name}」，可在我的角色中使用');
    } catch (_) {
      if (!mounted) return;
      AppLog.record('sticker_download_failure');
      toast(context, '角色下载未完成，请检查网络或刷新素材库后重试');
    } finally {
      if (mounted) setState(() => downloading.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: StudioBackground(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeader(
                    title: '表情角色管理',
                    action: GlassIcon(
                      Icons.arrow_back_rounded,
                      tooltip: '返回',
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  GlassSegments(
                    labels: const ['我的角色', '云端素材库'],
                    selected: tab,
                    onChanged: (i) {
                      if (i == tab) return;
                      if (widget.store.haptics) HapticFeedback.selectionClick();
                      setState(() {
                        tab = i;
                        if (i == 1) remote ??= catalog.load(token: token);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  if (tab == 0)
                    Text(
                      '拖动右侧手柄调整顺序，点按角色即可选用。',
                      style: TextStyle(color: muted(context), fontSize: 13),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '下载来源 · ${catalog.source == 'github' ? 'GitHub' : 'Gitee'}',
                            style: TextStyle(
                              color: muted(context),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        GlassIcon(
                          Icons.refresh_rounded,
                          tooltip: '刷新素材库',
                          onTap: () => setState(
                            () => remote = catalog.load(token: token),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: tab == 0 ? localList(context) : remoteList(context),
            ),
          ],
        ),
      ),
    ),
  );

  Widget localList(BuildContext context) => ReorderableListView.builder(
    buildDefaultDragHandles: false,
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    itemCount: profiles.length,
    onReorderItem: reorder,
    onReorderStart: (_) {
      if (widget.store.haptics) HapticFeedback.selectionClick();
    },
    proxyDecorator: (child, _, _) =>
        Material(color: Colors.transparent, child: child),
    itemBuilder: (context, index) {
      final item = profiles[index];
      final builtIn = item.id == widget.builtin.id;
      final active = item.id == widget.active.id;
      final art = builtIn
          ? widget.builtinImage
          : item.references.isEmpty
          ? null
          : FileImage(File(item.references.first));
      return Padding(
        key: ValueKey(item.id),
        padding: const EdgeInsets.only(bottom: 8),
        child: Glass(
          blur: false,
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          radius: 20,
          child: Row(
            children: [
              if (art != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image(
                    image: ResizeImage(art, width: 156, allowUpscaling: false),
                    width: 56,
                    height: 53,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(width: 56),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Tooltip(
                  message: '选用${item.name}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context, ('select', item)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          active
                              ? '当前使用'
                              : builtIn
                              ? '内置'
                              : item.id.startsWith('cloud-')
                              ? '已下载'
                              : '自定义',
                          style: TextStyle(
                            color: active ? accentInk(context) : muted(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!builtIn)
                PopupMenuButton<String>(
                  popUpAnimationStyle: AnimationStyle.noAnimation,
                  tooltip: '管理${item.name}',
                  onSelected: (action) =>
                      Navigator.pop(context, (action, item)),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text('编辑${item.name}')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('删除${item.name}'),
                    ),
                  ],
                ),
              ReorderableDragStartListener(
                index: index,
                child: Tooltip(
                  message: '拖动排序',
                  child: SizedBox(
                    width: 44,
                    height: 48,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: muted(context),
                      size: 21,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget remoteList(BuildContext context) => FutureBuilder<List<CloudSticker>>(
    future: remote,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: StudioProgress());
      }
      if (snapshot.hasError)
        return const EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '无法读取云端素材库',
          subtitle: '检查网络后，可点右上方的刷新重试。',
        );
      final entries = snapshot.data ?? const <CloudSticker>[];
      if (entries.isEmpty)
        return const EmptyState(
          icon: Icons.cloud_outlined,
          title: '素材库暂时为空',
          subtitle: '新角色发布后会在此显示。',
        );
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final item = entries[i];
          final all = profiles.where((p) => p.id == item.localId);
          final installed = all
              .where(
                (p) =>
                    p.references.isNotEmpty &&
                    p.references.every((path) => File(path).existsSync()),
              )
              .firstOrNull;
          return Glass(
            blur: false,
            radius: 20,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.cloud_download_outlined, color: accentInk(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '三视图与角色设定 · ${(item.length / 1024).ceil()} KB',
                        style: TextStyle(color: muted(context), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GlassButton(
                  installed == null ? '下载' : '使用',
                  small: true,
                  busy: downloading.contains(item.id),
                  onTap: installed == null
                      ? () => download(item)
                      : () => Navigator.pop(context, ('select', installed)),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
