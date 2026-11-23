import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api.dart';
import '../core/imaging.dart';
import '../core/gif_availability.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/updates.dart';
import '../ui/glass.dart';
import 'editor.dart';
import 'share_card.dart';

Future<List<String>> pickArtworkPaths(
  BuildContext context,
  AppStore store, {
  int limit = 1,
}) async {
  final items = store.visibleArtworks
      .where((art) => File(art.path).existsSync())
      .toList();
  final selected = <String>{};
  return await glassSheet<List<String>>(
        context,
        StatefulBuilder(
          builder: (sheet, update) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel('选择作品', caption: limit > 1 ? '最多 $limit 张' : null),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('暂无可用作品'),
                )
              else
                SizedBox(
                  height: 280,
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final art = items[i];
                      final checked = selected.contains(art.path);
                      return Glass(
                        blur: false,
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: ZoomableImage(
                                image: FileImage(File(art.path)),
                                child: Image.file(
                                  File(art.path),
                                  width: 48,
                                  height: 48,
                                  cacheWidth: 144,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                art.kind,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GlassIcon(
                              checked
                                  ? Icons.check_circle_rounded
                                  : Icons.add_circle_outline_rounded,
                              tooltip: limit == 1 ? '导入作品' : '选择作品 ${i + 1}',
                              onTap: () {
                                if (limit == 1) {
                                  Navigator.pop(sheet, [art.path]);
                                  return;
                                }
                                update(() {
                                  if (checked) {
                                    selected.remove(art.path);
                                  } else if (selected.length < limit) {
                                    selected.add(art.path);
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              if (limit > 1) ...[
                const SizedBox(height: 14),
                GlassButton(
                  '完成选择',
                  primary: true,
                  onTap: selected.isEmpty
                      ? null
                      : () => Navigator.pop(sheet, selected.toList()),
                ),
              ],
            ],
          ),
        ),
      ) ??
      [];
}

class LibraryScreen extends StatefulWidget {
  final AppStore store;
  final bool active;
  final VoidCallback? onGif;
  final ValueChanged<String> onEdit, onReuse;
  const LibraryScreen({
    super.key,
    required this.store,
    required this.onEdit,
    required this.onReuse,
    this.active = true,
    this.onGif,
  });
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  final selected = <String>{};
  final pull = ValueNotifier<double>(0);
  bool pullingFromTop = false;
  static const pullDistance = 185.0;
  int filter = 0;
  bool hiddenSpace = false;
  String query = '';
  double overscroll = 0;
  final search = TextEditingController();
  late final selectionAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 195),
    reverseDuration: const Duration(milliseconds: 145),
  );
  late final selectionCurve = CurvedAnimation(
    parent: selectionAnimation,
    curve: studioEaseOut,
    reverseCurve: studioEaseOut,
  );

  void updateSelection(VoidCallback change, {bool longPress = false}) {
    if (longPress && widget.store.haptics) HapticFeedback.mediumImpact();
    setState(change);
    final target = selected.isEmpty ? 0.0 : 1.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      selectionAnimation.value = target;
    } else if (selected.isEmpty) {
      selectionAnimation.reverse();
    } else {
      selectionAnimation.forward();
    }
  }

  void openSpace(bool hidden) {
    AppLog.record(hidden ? 'hidden_space_enter' : 'hidden_space_exit');
    pull.value = 0;
    updateSelection(() {
      selected.clear();
      hiddenSpace = hidden;
      query = '';
      search.clear();
      filter = 0;
    });
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      pullingFromTop = false;
      overscroll = 0;
      pull.value = 0;
      if (hiddenSpace) {
        hiddenSpace = false;
        query = '';
        filter = 0;
        selected.clear();
        selectionAnimation.value = 0;
        search.clear();
      }
    }
  }

  @override
  void dispose() {
    pull.dispose();
    selectionCurve.dispose();
    selectionAnimation.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    final items =
        widget.store.artworks
            .where(
              (a) =>
                  (a.hidden == hiddenSpace) &&
                  (filter != 1 || a.favorite) &&
                  (filter != 2 || a.path.endsWith('.gif')) &&
                  (a.prompt.toLowerCase().contains(query.toLowerCase()) ||
                      a.kind.contains(query)),
            )
            .toList()
          ..sort((a, b) => b.created.compareTo(a.created));
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth != 0 || hiddenSpace || selected.isNotEmpty)
                return false;
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                pullingFromTop = notification.metrics.extentBefore < 1;
              } else if (notification is ScrollUpdateNotification &&
                  notification.dragDetails != null &&
                  notification.metrics.extentBefore > 1) {
                pullingFromTop = false;
                overscroll = 0;
                pull.value = 0;
              } else if (notification is OverscrollNotification &&
                  pullingFromTop &&
                  notification.dragDetails != null &&
                  notification.overscroll < 0) {
                overscroll -= notification.overscroll;
                pull.value = (overscroll / pullDistance).clamp(0, 1);
              } else if (notification is ScrollEndNotification) {
                final open = pullingFromTop && overscroll >= pullDistance;
                pullingFromTop = false;
                overscroll = 0;
                pull.value = 0;
                if (open)
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && widget.active) {
                      if (widget.store.haptics) HapticFeedback.lightImpact();
                      openSpace(true);
                    }
                  });
              }
              return false;
            },
            child: TweenAnimationBuilder<double>(
              key: ValueKey(hiddenSpace),
              tween: Tween(begin: hiddenSpace ? 0.0 : 1.0, end: 1),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 190),
              curve: studioEaseOut,
              builder: (_, value, child) => Transform.translate(
                offset: Offset(0, 18 * (1 - value)),
                child: child,
              ),
              child: CustomScrollView(
                physics: const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 5, 22, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          PageHeader(
                            title: hiddenSpace ? '隐藏空间' : '作品',
                            action: hiddenSpace
                                ? GlassIcon(
                                    Icons.arrow_back_rounded,
                                    tooltip: '返回普通空间',
                                    onTap: () => openSpace(false),
                                  )
                                : GlassIcon(
                                    Icons.gif_box_outlined,
                                    tooltip: '原生 GIF 创作',
                                    unavailable: !StudioScope.of(context)
                                        .gifEnabled,
                                    onTap: () {
                                      if (!widget.store.gifEnabled) {
                                        toast(context, gifUnavailableMessage);
                                        return;
                                      }
                                      if (!supportsNativeGif(
                                        widget.store.imageApi.model,
                                      )) {
                                        toast(context, '当前模型暂不支持 GIF');
                                        return;
                                      }
                                      widget.onGif?.call();
                                    },
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
                            onChanged: (i) {
                              if (i == filter) return;
                              if (widget.store.haptics) {
                                HapticFeedback.selectionClick();
                              }
                              setState(() => filter = i);
                            },
                          ),
                          SectionLabel('${items.length} 件作品'),
                        ],
                      ),
                    ),
                  ),
                  if (items.isEmpty)
                    SliverToBoxAdapter(
                      child: EmptyState(
                        icon: Icons.collections_outlined,
                        title: hiddenSpace
                            ? '暂无隐藏作品'
                            : filter == 1
                            ? '把喜欢，留在这里'
                            : '暂无作品',
                        subtitle: hiddenSpace
                            ? '在作品页长按选择，再移入隐藏空间。'
                            : '生成与导出的照片会保存在这里。\n也可以导入照片，开始下一次创作。',
                        action: hiddenSpace
                            ? null
                            : GlassButton(
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
                            onLongPress: () => updateSelection(
                              () => selected.add(art.id),
                              longPress: true,
                            ),
                            onTap: () {
                              if (selected.isNotEmpty) {
                                updateSelection(() {
                                  if (!selected.add(art.id))
                                    selected.remove(art.id);
                                });
                                return;
                              }
                              openArtwork(
                                context,
                                widget.store,
                                art,
                                widget.onEdit,
                                onReuse: widget.onReuse,
                              );
                            },
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
                                        _ArtworkHero(
                                          art: art,
                                          fit: BoxFit.cover,
                                        ),
                                        if (selected.contains(art.id))
                                          Positioned(
                                            left: 10,
                                            top: 10,
                                            child: Semantics(
                                              label: '已选中',
                                              selected: true,
                                              child: Container(
                                                key: const ValueKey(
                                                  'artwork-selected-check',
                                                ),
                                                width: 30,
                                                height: 30,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xff16884b,
                                                  ),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white,
                                                    width: 2,
                                                  ),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Color(0x55000000),
                                                      blurRadius: 6,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.check_rounded,
                                                  color: Colors.white,
                                                  size: 22,
                                                ),
                                              ),
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
                                                    : Icons
                                                          .favorite_border_rounded,
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
                                    padding: const EdgeInsets.fromLTRB(
                                      13,
                                      12,
                                      13,
                                      12,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 15,
                              childAspectRatio: .76,
                            ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                  SliverToBoxAdapter(
                    child: SizedBox(height: StudioTabInset.of(context) + 20),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: ValueListenableBuilder<double>(
              valueListenable: pull,
              builder: (context, value, _) => value == 0
                  ? const SizedBox.shrink()
                  : Center(
                      child: Transform.translate(
                        offset: Offset(0, value * 48),
                        child: Glass(
                          blur: false,
                          radius: 24,
                          tint: Theme.of(context).colorScheme.surface,
                          opacity: .96,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  value: value,
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(value >= 1 ? '松开进入隐藏空间' : '继续下拉'),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: StudioTabInset.of(context),
          child: AnimatedBuilder(
            animation: selectionAnimation,
            builder: (_, child) => Offstage(
              offstage: selectionAnimation.isDismissed,
              child: IgnorePointer(ignoring: selected.isEmpty, child: child),
            ),
            child: GlassMotionScope(
              staticSurface: true,
              child: SlideTransition(
                key: const ValueKey('artwork-selection-toolbar'),
                position: Tween(
                  begin: const Offset(0, .25),
                  end: Offset.zero,
                ).animate(selectionCurve),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Glass(
                      radius: 26,
                      tint: Theme.of(context).colorScheme.surface,
                      opacity: isDark(context) ? .88 : .92,
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 17,
                                  color: accentInk(context),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '已选 ${selected.length} 件',
                                    style: TextStyle(
                                      color: ink(context),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '取消',
                                  color: muted(context),
                                  iconSize: 20,
                                  onPressed: () =>
                                      updateSelection(selected.clear),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              _SelectionAction(
                                '分享图',
                                Icons.ios_share_rounded,
                                () => shareArtworkCards(
                                  context,
                                  widget.store,
                                  widget.store.artworks
                                      .where((a) => selected.contains(a.id))
                                      .toList(),
                                ),
                              ),
                              _SelectionAction(
                                '全选',
                                Icons.select_all_rounded,
                                () => updateSelection(
                                  () => selected.addAll(items.map((a) => a.id)),
                                ),
                              ),
                              _SelectionAction(
                                '删除',
                                Icons.delete_outline_rounded,
                                () async {
                                  final batch = widget.store.artworks
                                      .where((a) => selected.contains(a.id))
                                      .toList();
                                  if (!await confirm(
                                    context,
                                    '删除 ${batch.length} 件作品？',
                                    '仅删除应用内副本，相册照片保留。',
                                  ))
                                    return;
                                  for (final art in batch) {
                                    await widget.store.removeArtwork(art);
                                  }
                                  if (mounted) updateSelection(selected.clear);
                                },
                                destructive: true,
                              ),
                              _SelectionAction(
                                hiddenSpace ? '还原' : '隐藏',
                                hiddenSpace
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                () async {
                                  await widget.store.setArtworkHidden(
                                    selected,
                                    !hiddenSpace,
                                  );
                                  if (mounted) updateSelection(selected.clear);
                                },
                                tooltip: hiddenSpace ? '还原到普通空间' : '移入隐藏空间',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectionAction extends StatelessWidget {
  const _SelectionAction(
    this.label,
    this.icon,
    this.onTap, {
    this.tooltip,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : ink(context);
    return Expanded(
      child: Tooltip(
        message: tooltip ?? label,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 21),
              const SizedBox(height: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ImageProvider _artworkImage(Artwork art, int maxEdge) {
  final original = FileImage(File(art.path));
  if (math.max(art.width, art.height) <= maxEdge) return original;
  return ResizeImage(
    original,
    width: art.width >= art.height ? maxEdge : null,
    height: art.height > art.width ? maxEdge : null,
    allowUpscaling: false,
  );
}

const artworkTileCorners = BorderRadius.vertical(top: Radius.circular(22));
const artworkDetailCorners = BorderRadius.all(Radius.circular(24));

class _ArtworkHero extends StatelessWidget {
  const _ArtworkHero({
    required this.art,
    required this.fit,
    this.detail = false,
  });

  final Artwork art;
  final BoxFit fit;
  final bool detail;

  Widget image(ImageProvider provider, BoxFit fit, {Widget? fallback}) => Image(
    image: provider,
    fit: fit,
    gaplessPlayback: true,
    frameBuilder: fallback == null
        ? null
        : (context, child, frame, _) => frame == null ? fallback : child,
    errorBuilder: (_, _, _) =>
        fallback ?? const Center(child: Icon(Icons.broken_image_outlined)),
  );

  @override
  Widget build(BuildContext context) {
    final thumbnail = _artworkImage(art, 640);
    final base = image(thumbnail, fit);
    final content = detail
        ? _ArtworkDetailImage(
            art: art,
            lowResolution: base,
            highResolution: () =>
                image(_artworkImage(art, 1400), fit, fallback: base),
          )
        : base;
    final clipped = ClipRRect(
      borderRadius: detail ? artworkDetailCorners : artworkTileCorners,
      child: content,
    );
    if (MediaQuery.disableAnimationsOf(context)) return clipped;
    return Hero(
      tag: 'artwork_${art.id}',
      flightShuttleBuilder: (context, animation, direction, from, to) {
        final provider = thumbnail;
        final fit = direction == HeroFlightDirection.push
            ? BoxFit.contain
            : BoxFit.cover;
        return AnimatedBuilder(
          animation: animation,
          child: image(provider, fit),
          builder: (_, child) => ClipRRect(
            borderRadius: BorderRadius.lerp(
              artworkTileCorners,
              artworkDetailCorners,
              animation.value.clamp(0.0, 1.0),
            )!,
            child: child,
          ),
        );
      },
      child: clipped,
    );
  }
}

class _ArtworkDetailImage extends StatefulWidget {
  const _ArtworkDetailImage({
    required this.art,
    required this.lowResolution,
    required this.highResolution,
  });
  final Artwork art;
  final Widget lowResolution;
  final Widget Function() highResolution;
  @override
  State<_ArtworkDetailImage> createState() => _ArtworkDetailImageState();
}

class _ArtworkDetailImageState extends State<_ArtworkDetailImage> {
  Animation<double>? transition;
  bool settled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (transition == animation) return;
    transition?.removeStatusListener(onStatus);
    transition = animation;
    if (animation?.isCompleted != false) settled = true;
    animation?.addStatusListener(onStatus);
  }

  void onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !settled)
      setState(() => settled = true);
  }

  @override
  void dispose() {
    transition?.removeStatusListener(onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      settled &&
          math.max(widget.art.width, widget.art.height) > 640 &&
          !widget.art.path.toLowerCase().endsWith('.gif')
      ? widget.highResolution()
      : widget.lowResolution;
}

Future<void> openArtwork(
  BuildContext context,
  AppStore store,
  Artwork art,
  ValueChanged<String> onEdit, {
  ValueChanged<String>? onReuse,
}) => Navigator.push(
  context,
  PageRouteBuilder<void>(
    settings: const RouteSettings(name: 'artwork_detail'),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 155),
    reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 125),
    pageBuilder: (_, _, _) =>
        ArtworkDetail(store: store, art: art, onEdit: onEdit, onReuse: onReuse),
    transitionsBuilder: (_, animation, secondary, child) =>
        StudioRouteMotion(animation: animation, artwork: true, child: child),
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
  Future<void> preview() => showZoomImage(
    context,
    FileImage(File(widget.art.path)),
    preview: _artworkImage(widget.art, 640),
  );

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
                    Icons.fullscreen_rounded,
                    tooltip: '查看大图',
                    onTap: preview,
                  ),
                  const SizedBox(width: 9),
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
              SizedBox(
                height: 380,
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 6,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = applyBoxFit(
                        BoxFit.contain,
                        Size(
                          math.max(1, art.width).toDouble(),
                          math.max(1, art.height).toDouble(),
                        ),
                        constraints.biggest,
                      ).destination;
                      return Center(
                        child: SizedBox.fromSize(
                          size: size,
                          child: _ArtworkHero(
                            art: art,
                            fit: BoxFit.contain,
                            detail: true,
                          ),
                        ),
                      );
                    },
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
                '生成分享图',
                icon: Icons.auto_awesome_rounded,
                onTap: busy
                    ? null
                    : () => action(
                        () => shareArtworkCard(context, widget.store, art),
                      ),
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
                    if (art.modelWidth != null && art.modelHeight != null)
                      _meta(
                        context,
                        '模型输出',
                        '${art.modelWidth} × ${art.modelHeight}${art.modelWidth != art.width || art.modelHeight != art.height ? ' · 已还原画布尺寸' : ''}',
                      ),
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
                child: StudioSelectable(
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
  @override
  void initState() {
    super.initState();
    duration = (widget.store.prefs.getInt('gif_duration') ?? 500).clamp(
      100,
      2000,
    );
    colors = widget.store.prefs.getInt('gif_colors') == 128 ? 128 : 256;
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.store.prefs.setInt('gif_duration', duration);
    widget.store.prefs.setInt('gif_colors', colors);
  }

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
    if (!widget.store.gifEnabled) {
      toast(context, gifUnavailableMessage);
      return;
    }
    if (frames.length < 2 || busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await beginProcessing(local: true);
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
      await endProcessing(local: true);
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
                              for (final art
                                  in widget.store.visibleArtworks.take(30))
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
              unavailable: !StudioScope.of(context).gifEnabled,
              onTap: !widget.store.gifEnabled || frames.length >= 2
                  ? compose
                  : null,
            ),
            const SizedBox(height: 25),
          ],
        ),
      ),
    ),
  );
}
