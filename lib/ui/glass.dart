import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' as mx;
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart' as lgr;

import '../core/store.dart';
import '../core/appearance.dart';
import 'editable.dart';
export 'editable.dart' show StudioSelectable;

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
Color primaryOn(BuildContext context) =>
    mx.MiuixTheme.of(context).colors.onPrimary;

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
  final bool blur, separateLayer;
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
  });
  @override
  Widget build(BuildContext context) {
    final store = StudioScope.of(context), dark = isDark(context);
    final nested =
        context
            .dependOnInheritedWidgetOfExactType<_GlassScope>()
            ?.insideGlass ??
        false;
    if (!separateLayer && !nested) {
      final r = BorderRadius.circular(radius);
      final materialShift = (store.glassOpacity - .22) * .6;
      double surfaceAlpha(double value) =>
          store.highContrast ? .96 : (value + materialShift).clamp(.03, .96);
      return ClipRRect(
        borderRadius: r,
        child: BackdropFilter.grouped(
          filter: ui.ImageFilter.blur(
            sigmaX: store.highContrast || !blur ? 0 : store.blur,
            sigmaY: store.highContrast || !blur ? 0 : store.blur,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tint != null
                    ? [
                        tint!.withValues(alpha: opacity ?? .3),
                        tint!.withValues(alpha: opacity ?? .2),
                      ]
                    : dark
                    ? [
                        (store.highContrast
                                ? const Color(0xff202733)
                                : Colors.white)
                            .withValues(alpha: surfaceAlpha(.13)),
                        (store.highContrast
                                ? const Color(0xff202733)
                                : Colors.white)
                            .withValues(alpha: surfaceAlpha(.05)),
                      ]
                    : [
                        Colors.white.withValues(alpha: surfaceAlpha(.82)),
                        Colors.white.withValues(alpha: surfaceAlpha(.52)),
                      ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? .14 : .85),
              ),
            ),
            child: child,
          ),
        ),
      );
    }
    final alpha = opacity ?? store.glassOpacity;
    final color = tint ?? (dark ? const Color(0xff263349) : Colors.white);
    final content = _GlassScope(
      child: Padding(
        padding: padding,
        child: child is Column
            ? lgr.LiquidGlassLayer(
                settings: glassSettings(context),
                child: _GlassScope(insideGlass: false, child: child),
              )
            : child,
      ),
    );
    if (store.highContrast || !blur) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: store.highContrast ? .96 : alpha),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: Colors.white.withValues(alpha: dark ? .12 : .65),
          ),
        ),
        child: content,
      );
    }
    final settings = glassSettings(context)
        .copyWith(refractionAmount: 60 * refraction);
    final appearance = lgr.LiquidGlassAppearance(
      tint: color.withValues(alpha: alpha),
      colorModel: const lgr.LiquidGlassColorModel.direct(saturation: 1.12),
    );
    final shape = lgr.LiquidRoundedSuperellipse(borderRadius: radius);
    const shadows = <BoxShadow>[];
    if (separateLayer || nested) {
      return lgr.LiquidGlassCapture(
        child: lgr.LiquidGlass.withOwnLayer(
          shape: shape,
          settings: settings,
          appearance: appearance,
          shadows: shadows,
          child: content,
        ),
      );
    }
    return lgr.LiquidGlass.auto(
      shape: shape,
      settings: settings,
      appearance: appearance,
      shadows: shadows,
      child: content,
    );
  }
}

class _GlassScope extends InheritedWidget {
  final bool insideGlass;
  const _GlassScope({required super.child, this.insideGlass = true});
  @override
  bool updateShouldNotify(_GlassScope old) => insideGlass != old.insideGlass;
}

class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary, small, busy;
  const GlassButton(
    this.label, {
    super.key,
    this.icon,
    this.onTap,
    this.primary = false,
    this.small = false,
    this.busy = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = mx.MiuixTheme.of(context).colors;
    final button = mx.MiuixButton(
      enabled: onTap != null && !busy,
      onPressed: busy ? null : onTap,
      minHeight: small ? 40 : 48,
      minWidth: 40,
      cornerRadius: 16,
      insideMargin: EdgeInsets.symmetric(
        horizontal: small ? 14 : 20,
        vertical: small ? 8 : 12,
      ),
      colors: primary
          ? mx.MiuixButtonDefaults.buttonColorsPrimary(context)
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primary ? c.onPrimary : c.onSurface,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 20, color: primary ? c.onPrimary : c.onSurface),
          if (busy || icon != null) const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: primary ? c.onPrimary : c.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return small
        ? Align(alignment: Alignment.center, widthFactor: 1, child: button)
        : button;
  }
}

class GlassIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const GlassIcon(
    this.icon, {
    super.key,
    required this.tooltip,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      label: tooltip,
      button: true,
      child: icon == Icons.arrow_back_rounded || icon == Icons.close_rounded
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Glass(
                radius: 16,
                separateLayer: true,
                refraction: 1.5,
                padding: EdgeInsets.zero,
                child: SizedBox.square(
                  dimension: 44,
                  child: Icon(icon, size: 22, color: ink(context)),
                ),
              ),
            )
          : mx.MiuixButton(
              onPressed: onTap,
              minWidth: 44,
              minHeight: 44,
              insideMargin: const EdgeInsets.all(10),
              cornerRadius: 16,
              child: Icon(icon, size: 22, color: ink(context)),
            ),
    ),
  );
}

class GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int minLines, maxLines;
  final bool obscure;
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
    this.keyboard,
    this.onChanged,
    this.suffix,
  });
  @override
  Widget build(BuildContext context) => StudioEditable(
    controller: controller,
    hint: hint,
    minLines: minLines,
    maxLines: maxLines,
    obscure: obscure,
    keyboard: keyboard,
    onChanged: onChanged,
    suffix: suffix,
  );
}

class GlassSegments extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const GlassSegments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: mx.MiuixTabRowWithContour(
      tabs: labels,
      selectedTabIndex: selected,
      onTabSelected: onChanged,
      itemSpacing: 0,
      colors: mx.MiuixTabRowColors(
        backgroundColor: ink(context).withValues(alpha: .045),
        contentColor: muted(context),
        selectedBackgroundColor: isDark(context)
            ? Colors.white.withValues(alpha: .16)
            : Colors.white.withValues(alpha: .95),
        selectedContentColor: accentInk(context),
      ),
      minWidth: 0,
      maxWidth: double.infinity,
      height: 48,
      cornerRadius: 16,
    ),
  );
}

class GlassSlider extends StatelessWidget {
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart, onChangeEnd;
  final String? label, left, right, semanticLabel;
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
              '${(value * 100).round()}',
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

class TaskStatusCard extends StatelessWidget {
  final String title, stage;
  final int seconds;
  final VoidCallback? onCancel;
  const TaskStatusCard({
    super.key,
    required this.title,
    required this.stage,
    required this.seconds,
    this.onCancel,
  });
  @override
  Widget build(BuildContext context) => Glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: accent(context),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    stage,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: muted(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              '已用时 $seconds 秒',
              style: TextStyle(fontSize: 12, color: muted(context)),
            ),
            const Spacer(),
            if (onCancel != null)
              GlassButton('取消任务', small: true, onTap: onCancel),
          ],
        ),
      ],
    ),
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

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      content: Glass(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: accentInk(context),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: ink(context),
                ),
              ),
            ),
          ],
        ),
      ),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        ModalRoute.of(context)?.isFirst == true ? 112 : 16,
      ),
      duration: const Duration(seconds: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
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
  builder: (ctx) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * .92,
      ),
      child: Glass(
        radius: 32,
        opacity: isDark(ctx) ? .82 : .9,
        tint: isDark(ctx) ? const Color(0xff222d40) : const Color(0xfff6f8ff),
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
        // The modal's slide layout does not expose its paint translation to
        // region captures. Share a normal inner layer for the controls instead.
        child: lgr.LiquidGlassLayer(
          settings: glassSettings(ctx),
          child: _GlassScope(
            insideGlass: false,
            child: scroll
                ? SingleChildScrollView(
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
