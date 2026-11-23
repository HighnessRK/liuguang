import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'glass.dart';

/// A single Flutter render tree: the lens samples the live page every frame.
/// No platform-view textures, screenshots, PNG encoding or polling timers.
class LiquidNavigation extends StatefulWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const LiquidNavigation({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  @override
  State<LiquidNavigation> createState() => _LiquidNavigationState();
}

class _LiquidNavigationState extends State<LiquidNavigation>
    with SingleTickerProviderStateMixin {
  late final position = AnimationController.unbounded(
    vsync: this,
    value: widget.selected.toDouble(),
  );
  bool dragging = false;
  int? pendingSelection;
  @override
  void didUpdateWidget(covariant LiquidNavigation old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected && !dragging) {
      if (pendingSelection != widget.selected)
        settle(widget.selected, notify: false);
      pendingSelection = null;
    }
  }

  void settle(int index, {bool notify = true, double velocity = 0}) {
    final target = index.clamp(0, 3);
    if (StudioScope.of(context).reduceMotion ||
        MediaQuery.disableAnimationsOf(context)) {
      position.value = target.toDouble();
    } else {
      position.animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 420, damping: 33),
          position.value,
          target.toDouble(),
          velocity,
        ),
      );
    }
    if (notify && target != widget.selected) {
      if (StudioScope.of(context).haptics) {
        HapticFeedback.selectionClick();
      }
      pendingSelection = target;
      widget.onChanged(target);
    }
  }

  @override
  void dispose() {
    position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(304.0, constraints.maxWidth * .74);
      return Center(
        child: SizedBox(
          width: width,
          height: 60,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) =>
                settle(((d.localPosition.dx - 4) / ((width - 8) / 4)).floor()),
            onHorizontalDragStart: (_) {
              position.stop();
              setState(() => dragging = true);
            },
            onHorizontalDragUpdate: (d) => position.value =
                ((d.localPosition.dx - 4) / ((width - 8) / 4) - .5).clamp(
                  0.0,
                  3.0,
                ),
            onHorizontalDragEnd: (details) {
              final slot = (width - 8) / 4;
              final velocity = ((details.primaryVelocity ?? 0) / slot).clamp(
                -10.0,
                10.0,
              );
              final target = (position.value + velocity * .07).round().clamp(
                0,
                3,
              );
              setState(() => dragging = false);
              settle(target, velocity: velocity);
            },
            onHorizontalDragCancel: () {
              setState(() => dragging = false);
              settle(widget.selected, notify: false);
            },
            child: BackdropGroup(
              child: Glass(
                radius: 99,
                separateLayer: true,
                liveBackdrop: true,
                opacity: isDark(context) ? .28 : .18,
                refraction: 1.8,
                padding: const EdgeInsets.all(4),
                child: AnimatedBuilder(
                  animation: position,
                  builder: (context, _) {
                    final slot = (width - 8) / 4;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: slot,
                          child: Transform.translate(
                            offset: Offset(
                              slot * position.value.clamp(0.0, 3.0),
                              0,
                            ),
                            child: Transform.scale(
                              scaleX: dragging ? 1.06 : 1,
                              scaleY: dragging ? .96 : 1,
                              child: BackdropGroup(
                                child: Glass(
                                  radius: 99,
                                  opacity: isDark(context) ? .32 : .36,
                                  blur: false,
                                  tint: accent(context),
                                  padding: EdgeInsets.zero,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: List.generate(4, (i) {
                            final intensity = (1 - (position.value - i).abs())
                                .clamp(0.0, 1.0);
                            final color = Color.lerp(
                              muted(context),
                              accentInk(context),
                              intensity,
                            )!;
                            return Expanded(
                              child: Semantics(
                                button: true,
                                selected: widget.selected == i,
                                label: ['创作', '修图', '作品', '设置'][i],
                                onTap: () => settle(i),
                                child: ExcludeSemantics(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        [
                                          Icons.auto_awesome_outlined,
                                          Icons.tune_rounded,
                                          Icons.grid_view_outlined,
                                          Icons.settings_outlined,
                                        ][i],
                                        size: 21,
                                        color: color,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        ['创作', '修图', '作品', '设置'][i],
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1.1,
                                          fontWeight: FontWeight.w500,
                                          color: color,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
