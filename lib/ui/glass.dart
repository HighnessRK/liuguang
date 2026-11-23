import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' as mx;
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart' as lgr;

import '../core/store.dart';
import '../core/updates.dart';
import '../core/appearance.dart';
import 'editable.dart';
export 'editable.dart' show StudioSelectable;

class StudioTabInset extends InheritedWidget {
  final double bottom;
  const StudioTabInset({super.key, required this.bottom, required super.child});
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudioTabInset>()?.bottom ?? 0;
  @override
  bool updateShouldNotify(StudioTabInset oldWidget) =>
      bottom != oldWidget.bottom;
}

class StudioScope extends InheritedNotifier<AppStore> {
  const StudioScope({super.key, required AppStore store, required super.child})
    : super(notifier: store);
  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudioScope>()!.notifier!;
}

bool isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;
Color ink(BuildContext context) => mx.MiuixTheme.of(context).colors.onSurface;
Color muted(BuildContext context) =>
    mx.MiuixTheme.of(context).colors.onSurfaceVariantSummary;
Color accent(BuildContext context) => mx.MiuixTheme.of(context).colors.primary;
Color accentInk(BuildContext context) => accent(context);
// Glass is translucent: onPrimary is only suitable for an opaque primary fill.
Color primaryOn(BuildContext context, {double? opacity}) {
  final surface = Color.alphaBlend(
    accent(context)
        .withValues(alpha: opacity ?? StudioScope.of(context).glassOpacity),
    mx.MiuixTheme.of(context).colors.surface,
  );
  const light = Colors.white, dark = Color(0xff15202c);
  final luminance = surface.computeLuminance();
  final lightContrast = (light.computeLuminance() + .05) / (luminance + .05);
  final darkContrast = (luminance + .05) / (dark.computeLuminance() + .05);
  if (lightContrast < 4.5 && darkContrast < 4.5) return Colors.black;
  return lightContrast > darkContrast ? light : dark;
}

lgr.LiquidGlassSettings glassSettings(BuildContext context) {
  final store = StudioScope.of(context);
  return lgr.LiquidGlassSettings.ios27Regular(
    brightness: Theme.of(context).brightness,
    tintAmount: (store.glassOpacity / .7).clamp(0.0, 1.0),
    frost: (store.blur * .2).clamp(0, 10),
  ).copyWith(contourStrength: .16, bevelShadowStrength: 0, highlight: .75);
}

class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius, refraction;
  final Color? tint;
  final bool blur, separateLayer, liveBackdrop;
  final double? opacity;
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.tint,
    this.blur = true,
    this.opacity,
    this.refraction = 1,
    this.separateLayer = false,
    this.liveBackdrop = false,
  });
  @override
  Widget build(BuildContext context) {
    final store = StudioScope.of(context), dark = isDark(context);
    final material = store.advancedMaterials ? store.glassMaterial : null;
    final liquid = material == StudioMaterial.liquid;
    final gaussian = material == StudioMaterial.gaussian;
    final enhanced = material != null;
    final r = BorderRadius.circular(radius);
    final base = dark ? const Color(0xff263349) : Colors.white;
    final useLiveLens = liquid && liveBackdrop && !store.highContrast;
    final shift = (store.glassOpacity - .22) * .55;
    final alpha = opacity ?? store.glassOpacity;
    double surfaceAlpha(double value) => (value + shift).clamp(.03, .96);
    final surface = store.highContrast
        ? [
            (tint ?? (dark ? const Color(0xff202733) : Colors.white))
                .withValues(alpha: .96),
          ]
        : tint != null
        ? [
            tint!.withValues(alpha: opacity ?? (separateLayer ? alpha : .30)),
            tint!.withValues(alpha: opacity ?? (separateLayer ? alpha : .20)),
          ]
        : switch (material) {
            StudioMaterial.liquid => [
              base.withValues(alpha: surfaceAlpha(dark ? .63 : .57)),
              base.withValues(alpha: surfaceAlpha(dark ? .35 : .25)),
              base.withValues(alpha: surfaceAlpha(dark ? .57 : .53)),
            ],
            StudioMaterial.gaussian => [
              base.withValues(alpha: surfaceAlpha(dark ? .70 : .65)),
              base.withValues(alpha: surfaceAlpha(dark ? .64 : .58)),
            ],
            null =>
              dark
                  ? [
                      Colors.white.withValues(alpha: surfaceAlpha(.13)),
                      Colors.white.withValues(alpha: surfaceAlpha(.05)),
                    ]
                  : [
                      Colors.white.withValues(alpha: surfaceAlpha(.82)),
                      Colors.white.withValues(alpha: surfaceAlpha(.52)),
                    ],
          };
    final body = Padding(padding: padding, child: child);
    if (useLiveLens && ui.ImageFilter.isShaderFilterSupported) {
      // Keep the refraction capture local to the floating bar. Do not sample
      // the page again for the moving selection indicator inside it.
      return lgr.LiquidGlassCapture(
        child: lgr.LiquidGlass.withOwnLayer(
          shape: lgr.LiquidRoundedSuperellipse(borderRadius: radius),
          settings: glassSettings(context)
              .copyWith(refractionAmount: 60 * refraction),
          appearance: lgr.LiquidGlassAppearance(
            tint: base.withValues(
              alpha: (alpha + (dark ? .18 : .30)).clamp(.25, .8),
            ),
            colorModel: const lgr.LiquidGlassColorModel.direct(
              saturation: 1.08,
            ),
          ),
          child: body,
        ),
      );
    }
    final content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        color: surface.length == 1 ? surface.single : null,
        gradient: surface.length == 1
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: surface,
              ),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: dark ? (liquid ? .24 : .14) : .85,
          ),
        ),
      ),
      child: liquid && !store.highContrast
          ? CustomPaint(foregroundPainter: _GlassRim(radius, dark), child: body)
          : body,
    );
    // Repeatable controls and moving surfaces use only their material finish.
    // Gaussian backdrop passes share the page capture. The floating bar has
    // its own group because it intentionally overlaps the content underneath.
    if (!enhanced ||
        !blur ||
        store.highContrast ||
        store.blur <= 0 ||
        (!liveBackdrop &&
            (GlassMotionScope.of(context) || separateLayer || liquid))) {
      return content;
    }
    final sigma = gaussian ? store.blur.clamp(3.0, 16.0) : 9.0;
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: content,
      ),
    );
  }
}

class _GlassRim extends CustomPainter {
  const _GlassRim(this.radius, this.dark);
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final inset = bounds.deflate(1.1);
    if (inset.isEmpty) return;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, .38, .68, 1],
        colors: [
          Colors.white.withValues(alpha: dark ? .55 : .96),
          Colors.white.withValues(alpha: .02),
          const Color(0xff859ddb).withValues(alpha: dark ? .11 : .35),
          Colors.white.withValues(alpha: dark ? .43 : .90),
        ],
      ).createShader(bounds);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, Radius.circular(radius)),
      rim,
    );
  }

  @override
  bool shouldRepaint(_GlassRim old) => radius != old.radius || dark != old.dark;
}

String _buttonEvent(String label) => switch (label) {
  '智能润色' || '智能润色描述' => 'polish_tapped',
  '开始创作' => 'image_create_tapped',
  '生成表情包' => 'sticker_generate_tapped',
  '开始增强' => 'lens_enhance_tapped',
  '取消任务' => 'task_cancel_tapped',
  '从作品导入' || '从相册导入' => 'artwork_import_tapped',
  '导出' => 'export_tapped',
  '去安装' || '安装' => 'install_tapped',
  '下载更新' => 'update_download_tapped',
  '删除所选' => 'batch_delete_tapped',
  '全选' => 'select_all_tapped',
  _ => 'button_tapped',
};

class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary, small, busy, unavailable;
  const GlassButton(
    this.label, {
    super.key,
    this.icon,
    this.onTap,
    this.primary = false,
    this.small = false,
    this.busy = false,
    this.unavailable = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = mx.MiuixTheme.of(context).colors;
    final store = StudioScope.of(context);
    final popup = ModalRoute.of(context) is PopupRoute;
    final foreground = unavailable
        ? muted(context)
        : primary
        ? primaryOn(
            context,
            opacity: popup
                ? .25
                : store.highContrast
                ? .96
                : null,
          )
        : c.onSurface;
    final button = Semantics(
      button: true,
      enabled: onTap != null && !busy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy || onTap == null
            ? null
            : () {
                AppLog.record(_buttonEvent(label));
                onTap!();
              },
        child: Glass(
          separateLayer: ModalRoute.of(context) is! PopupRoute,
          radius: 16,
          tint: primary && !unavailable ? accent(context) : null,
          padding: EdgeInsets.symmetric(
            horizontal: small ? 14 : 20,
            vertical: small ? 8 : 12,
          ),
          child: _PressMotion(
            enabled: onTap != null && !busy && !unavailable,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: StudioProgress(color: foreground),
                  )
                else if (icon != null)
                  Icon(icon, size: 20, color: foreground),
                if (busy || icon != null) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return small
        ? Align(alignment: Alignment.center, widthFactor: 1, child: button)
        : button;
  }
}

class StudioProgress extends StatelessWidget {
  const StudioProgress({super.key, this.color, this.strokeWidth = 2});
  final Color? color;
  final double strokeWidth;
  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? Icon(
          Icons.hourglass_top_rounded,
          size: 14,
          color: color ?? accentInk(context),
          semanticLabel: '正在处理',
        )
      : CircularProgressIndicator(color: color, strokeWidth: strokeWidth);
}

class GlassIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool unavailable;
  const GlassIcon(
    this.icon, {
    super.key,
    required this.tooltip,
    required this.onTap,
    this.unavailable = false,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      label: tooltip,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Glass(
          radius: 16,
          separateLayer: ModalRoute.of(context) is! PopupRoute,
          refraction: 1.5,
          padding: EdgeInsets.zero,
          child: SizedBox.square(
            dimension: 44,
            child: _PressMotion(
              enabled: onTap != null && !unavailable,
              child: Icon(
                icon,
                size: 22,
                color: unavailable ? muted(context) : ink(context),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const studioEaseOut = Cubic(.23, 1, .32, 1);

class GlassMotionScope extends InheritedWidget {
  const GlassMotionScope({
    super.key,
    required super.child,
    required this.staticSurface,
  });
  final bool staticSurface;
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlassMotionScope>()
          ?.staticSurface ??
      false;
  @override
  bool updateShouldNotify(GlassMotionScope oldWidget) =>
      staticSurface != oldWidget.staticSurface;
}

class StudioRouteMotion extends StatelessWidget {
  const StudioRouteMotion({
    super.key,
    required this.animation,
    required this.child,
    this.artwork = false,
  });
  final Animation<double> animation;
  final Widget child;
  final bool artwork;

  @override
  Widget build(BuildContext context) {
    final content = RepaintBoundary(
      child: GlassMotionScope(staticSurface: true, child: child),
    );
    if (MediaQuery.disableAnimationsOf(context)) return content;
    return ClipRect(
      child: SlideTransition(
        position: animation
            .drive(CurveTween(curve: studioEaseOut))
            .drive(
              Tween(begin: Offset(artwork ? .036 : .09, 0), end: Offset.zero),
            ),
        child: content,
      ),
    );
  }
}

class _PressMotion extends StatefulWidget {
  const _PressMotion({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;
  @override
  State<_PressMotion> createState() => _PressMotionState();
}

class _PressMotionState extends State<_PressMotion> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context))
      return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => down = true),
      onPointerUp: (_) => setState(() => down = false),
      onPointerCancel: (_) => setState(() => down = false),
      child: AnimatedScale(
        scale: down ? .97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: studioEaseOut,
        child: widget.child,
      ),
    );
  }
}

class GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int minLines, maxLines;
  final bool obscure, readOnly;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  const GlassField({
    super.key,
    required this.controller,
    required this.hint,
    this.minLines = 1,
    this.maxLines = 1,
    this.obscure = false,
    this.readOnly = false,
    this.keyboard,
    this.onChanged,
    this.suffix,
  });
  @override
  Widget build(BuildContext context) {
    final advanced = StudioScope.of(context).advancedMaterials;
    final field = StudioEditable(
      transparent: advanced,
      controller: controller,
      hint: hint,
      minLines: minLines,
      maxLines: maxLines,
      obscure: obscure,
      readOnly: readOnly,
      keyboard: keyboard,
      onChanged: onChanged,
      suffix: suffix,
    );
    return advanced
        ? Glass(radius: 16, blur: false, padding: EdgeInsets.zero, child: field)
        : field;
  }
}

class GlassSegments extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final Set<int> unavailable;
  const GlassSegments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.unavailable = const {},
  });
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final segments = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: ink(context).withValues(alpha: .045),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final width = bounds.maxWidth / labels.length;
              return Stack(
                children: [
                  if (selected >= 0 &&
                      selected < labels.length &&
                      !unavailable.contains(selected))
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 0,
                      width: width,
                      child: AnimatedSlide(
                        offset: Offset(selected.toDouble(), 0),
                        duration: reduce
                            ? Duration.zero
                            : const Duration(milliseconds: 165),
                        curve: studioEaseOut,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            color: Colors.white.withValues(
                              alpha: isDark(context) ? .16 : .95,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      for (final (index, label) in labels.indexed)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: selected == index,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onChanged(index),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 40,
                                ),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 6,
                                    ),
                                    child: Text(
                                      label,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: unavailable.contains(index)
                                            ? muted(context)
                                                  .withValues(alpha: .67)
                                            : selected == index
                                            ? accentInk(context)
                                            : muted(context),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    return StudioScope.of(context).advancedMaterials
        ? Glass(
            radius: 16,
            blur: false,
            padding: EdgeInsets.zero,
            child: segments,
          )
        : segments;
  }
}

class GlassSlider extends StatelessWidget {
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart, onChangeEnd;
  final String? label, left, right, semanticLabel, valueLabel;
  final Color? leftColor, rightColor;
  const GlassSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = -1,
    this.max = 1,
    this.label,
    this.left,
    this.right,
    this.semanticLabel,
    this.valueLabel,
    this.leftColor,
    this.rightColor,
    this.onChangeStart,
    this.onChangeEnd,
  });
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null)
        Row(
          children: [
            Expanded(child: Text(label!, style: const TextStyle(fontSize: 14))),
            const SizedBox(width: 16),
            Text(
              valueLabel ?? '${(value * 100).round()}',
              style: TextStyle(
                fontSize: 12,
                color: muted(context),
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      if (label != null) const SizedBox(height: 10),
      Row(
        children: [
          if (leftColor != null) ...[
            ColorEndpoint(color: leftColor!),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Listener(
              onPointerDown: (_) => onChangeStart?.call(value),
              child: Semantics(
                label: semanticLabel ?? label,
                child: mx.MiuixSlider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onValueChanged: onChanged,
                  onValueChangeFinished: () => onChangeEnd?.call(value),
                ),
              ),
            ),
          ),
          if (rightColor != null) ...[
            const SizedBox(width: 14),
            ColorEndpoint(color: rightColor!),
          ],
        ],
      ),
      const SizedBox(height: 10),
      if (left != null || right != null)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              left ?? '',
              style: TextStyle(fontSize: 12, color: muted(context)),
            ),
            Text(
              right ?? '',
              style: TextStyle(fontSize: 12, color: muted(context)),
            ),
          ],
        ),
    ],
  );
}

class ColorEndpoint extends StatelessWidget {
  final Color color;
  const ColorEndpoint({super.key, required this.color});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: 22,
        child: CustomPaint(painter: _ColorEndpointPainter(color)),
      ),
    ),
  );
}

class _ColorEndpointPainter extends CustomPainter {
  final Color color;
  const _ColorEndpointPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(size.center(Offset.zero), 10, Paint()..color = color);
    canvas.drawCircle(
      size.center(Offset.zero),
      10,
      Paint()
        ..color = const Color(0x18000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ColorEndpointPainter old) => old.color != color;
}

class GlassCheckbox extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final Color? activeColor;
  const GlassCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });
  @override
  Widget build(BuildContext context) =>
      mx.MiuixCheckbox(value: value, onChanged: onChanged);
}

class GlassToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeTrackColor;
  const GlassToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeTrackColor,
  });
  @override
  Widget build(BuildContext context) =>
      mx.MiuixSwitch(value: value, onChanged: onChanged);
}

class TaskStatusCard extends StatefulWidget {
  final String title, stage;
  final int seconds;
  final double? progress;
  final VoidCallback? onCancel;
  const TaskStatusCard({
    super.key,
    required this.title,
    required this.stage,
    required this.seconds,
    this.onCancel,
    this.progress,
  });
  @override
  State<TaskStatusCard> createState() => _TaskStatusCardState();
}

class _TaskStatusCardState extends State<TaskStatusCard>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
      controller.value = 1;
    } else if (!controller.isAnimating) {
      controller.repeat();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = widget.progress;
    return Glass(
      blur: false,
      padding: const EdgeInsets.all(16),
      radius: 26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TaskPulse(animation: controller, size: 46),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: ink(context),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.stage.replaceAll(
                        RegExp(r'\s+\d+(?:\.\d+)?%$'),
                        '',
                      ),
                      style: TextStyle(color: muted(context), fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (percent != null)
                Text(
                  '${(percent.clamp(0, 1) * 100).round()}%',
                  style: TextStyle(
                    color: accentInk(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (percent != null)
            TweenAnimationBuilder<double>(
              tween: Tween(end: percent.clamp(0, 1)),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                color: accent(context),
                backgroundColor: accent(context).withValues(alpha: .12),
                minHeight: 4,
                borderRadius: BorderRadius.circular(8),
              ),
            )
          else
            LinearProgressIndicator(
              value: MediaQuery.disableAnimationsOf(context) ? 0 : null,
              color: accent(context),
              backgroundColor: accent(context).withValues(alpha: .12),
              minHeight: 4,
              borderRadius: BorderRadius.circular(8),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '已用时 ${widget.seconds} 秒',
                  style: TextStyle(fontSize: 12, color: muted(context)),
                ),
              ),
              if (widget.onCancel != null)
                GlassButton('取消任务', small: true, onTap: widget.onCancel),
            ],
          ),
        ],
      ),
    );
  }
}

class TaskPulse extends StatelessWidget {
  final Animation<double> animation;
  final double size;
  const TaskPulse({super.key, required this.animation, required this.size});

  @override
  Widget build(BuildContext context) {
    final color = accentInk(context);
    return SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: animation,
          child: Icon(
            Icons.auto_awesome_rounded,
            color: color,
            size: size * .49,
          ),
          builder: (_, child) {
            final pulse = .5 - .5 * math.cos(animation.value * 2 * math.pi);
            return Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color.withValues(alpha: .16 + pulse * .14),
                      ),
                      gradient: RadialGradient(
                        colors: [
                          color.withValues(alpha: .25 + pulse * .12),
                          color.withValues(alpha: .06),
                        ],
                      ),
                    ),
                  ),
                ),
                Transform.scale(scale: .88 + pulse * .16, child: child),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AuroraBusyButton extends StatefulWidget {
  const AuroraBusyButton({super.key});
  @override
  State<AuroraBusyButton> createState() => _AuroraBusyButtonState();
}

class _AuroraBusyButtonState extends State<AuroraBusyButton>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.stop();
    } else if (!motion.isAnimating) {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Glass(
    blur: false,
    radius: 16,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TaskPulse(animation: motion, size: 24),
        const SizedBox(width: 6),
        Text(
          '润色中…',
          style: TextStyle(
            color: ink(context),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

Future<T?> studioDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color barrierColor = Colors.black54,
  bool instant = false,
}) => showGeneralDialog<T>(
  context: context,
  barrierColor: barrierColor,
  barrierDismissible: true,
  barrierLabel: '关闭弹窗',
  transitionDuration: instant || MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 170),
  pageBuilder: (context, _, _) => builder(context),
  transitionBuilder: (_, animation, secondary, child) => ScaleTransition(
    scale: animation
        .drive(CurveTween(curve: studioEaseOut))
        .drive(Tween(begin: .97, end: 1.0)),
    child: child,
  ),
);

Future<void> showZoomImage(
  BuildContext context,
  ImageProvider image, {
  ImageProvider? preview,
}) => studioDialog<void>(
  context: context,
  barrierColor: Colors.black87,
  instant: true,
  builder: (ctx) => Dialog.fullscreen(
    backgroundColor: const Color(0xff101116),
    child: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: .5,
              maxScale: 10,
              child: Center(
                child: Image(
                  image: image,
                  fit: BoxFit.contain,
                  frameBuilder: preview == null
                      ? null
                      : (context, child, frame, _) => frame != null
                            ? child
                            : Image(
                                image: preview,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 16,
            child: GlassIcon(
              Icons.close_rounded,
              tooltip: '关闭大图',
              onTap: () => Navigator.pop(ctx),
            ),
          ),
        ],
      ),
    ),
  ),
);

class ZoomableImage extends StatelessWidget {
  final ImageProvider image;
  final Widget child;
  const ZoomableImage({super.key, required this.image, required this.child});
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => showZoomImage(context, image),
    child: child,
  );
}

class PageHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const PageHeader({super.key, required this.title, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 24),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class SectionLabel extends StatelessWidget {
  final String title;
  final String? caption;
  final Widget? action;
  const SectionLabel(this.title, {super.key, this.caption, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12, left: 3, right: 3),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        if (caption != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              caption!,
              style: TextStyle(color: muted(context), fontSize: 12),
            ),
          ),
        ],
        if (caption == null) const Spacer(),
        ?action,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glass(
            radius: 30,
            padding: const EdgeInsets.all(24),
            child: Icon(icon, size: 38, color: accentInk(context)),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted(context), fontSize: 14, height: 1.8),
          ),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    ),
  );
}

OverlayEntry? _notice;
Timer? _noticeTimer;

void toast(BuildContext context, String text) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  _noticeTimer?.cancel();
  _notice?.remove();
  final success =
      text.startsWith('已完成') ||
      text.startsWith('已保存') ||
      text.startsWith('已生成');
  AppLog.record(success ? 'success_notice' : 'app_notice');
  final reduce = MediaQuery.disableAnimationsOf(context);
  final entry = OverlayEntry(
    builder: (context) => Positioned(
      top: 8,
      left: 16,
      right: 16,
      child: SafeArea(
        bottom: false,
        child: IgnorePointer(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                curve: studioEaseOut,
                builder: (_, v, child) => Transform.translate(
                  offset: Offset(0, -12 * (1 - v)),
                  child: child,
                ),
                child: Glass(
                  blur: false,
                  tint: Theme.of(context).colorScheme.surface,
                  opacity: .98,
                  radius: 21,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        success
                            ? Icons.check_circle_outline_rounded
                            : Icons.info_outline_rounded,
                        color: accentInk(context),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          text,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            decoration: TextDecoration.none,
                            color: ink(context),
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
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
  );
  _notice = entry;
  overlay.insert(entry);
  _noticeTimer = Zone.root.createTimer(const Duration(seconds: 4), () {
    if (identical(_notice, entry)) {
      entry.remove();
      _notice = null;
    }
  });
}

Future<T?> glassSheet<T>(
  BuildContext context,
  Widget child, {
  bool scroll = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black54,
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: Duration(milliseconds: 225),
          reverseDuration: Duration(milliseconds: 175),
        ),
  builder: (ctx) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (ctx, bounds) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: bounds.maxHeight * .94),
          child: GlassMotionScope(
            staticSurface: true,
            child: Glass(
              radius: 30,
              blur: false,
              opacity: .98,
              tint: isDark(ctx)
                  ? const Color(0xff222d40)
                  : const Color(0xfff6f8ff),
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
              child: scroll
                  ? SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [_handle(ctx), child],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _handle(ctx),
                        Flexible(child: child),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Widget _handle(BuildContext context) => Center(
  child: Container(
    margin: const EdgeInsets.only(bottom: 22),
    width: 34,
    height: 4,
    decoration: BoxDecoration(
      color: muted(context).withValues(alpha: .35),
      borderRadius: BorderRadius.circular(9),
    ),
  ),
);

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await glassSheet<bool>(
      context,
      Builder(
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Text(message, style: TextStyle(color: muted(ctx), height: 1.7)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    '取消',
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    '确认',
                    primary: true,
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ) ??
    false;

class StudioBackground extends StatelessWidget {
  final Widget child;
  const StudioBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) => BackdropGroup(
    child: ColoredBox(
      color: mx.MiuixTheme.of(context).colors.surface,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _BackgroundPainter(
                  isDark(context),
                  StudioScope.of(context).palette,
                ),
              ),
            ),
          ),
          Material(type: MaterialType.transparency, child: child),
        ],
      ),
    ),
  );
}

class _BackgroundPainter extends CustomPainter {
  final bool dark;
  final String palette;
  _BackgroundPainter(this.dark, this.palette);
  @override
  void paint(Canvas canvas, Size size) {
    final alpha = dark ? .26 : .40;
    final colors = paletteById(palette).colors;
    final blobs = [
      (-70.0, -60.0, 320.0, Color(colors[0]), 1.0),
      (-90.0, 30.0, 300.0, Color(colors[1]), .9),
      (70.0, 320.0, 260.0, Color(colors[2]), .75),
      (-50.0, 620.0, 240.0, Color(colors[3]), .6),
    ];
    for (var i = 0; i < blobs.length; i++) {
      final b = blobs[i];
      final left = i == 1 || i == 3 ? size.width - b.$3 - b.$1 : b.$1;
      final rect = Rect.fromLTWH(left, b.$2, b.$3, b.$3);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              b.$4.withValues(alpha: alpha * b.$5),
              b.$4.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) =>
      old.dark != dark || old.palette != palette;
}

double? stageProgress(String stage) {
  final match = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(stage);
  return match == null
      ? null
      : (double.parse(match.group(1)!) / 100).clamp(0, 1);
}
