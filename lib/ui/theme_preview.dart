import 'package:flutter/material.dart';

import '../core/appearance.dart';
import 'glass.dart';

class PalettePreview extends StatelessWidget {
  final StudioPalette palette;
  const PalettePreview({super.key, required this.palette});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: AspectRatio(
      aspectRatio: 1.48,
      child: CustomPaint(painter: _PalettePainter(palette, isDark(context))),
    ),
  );
}

class _PalettePainter extends CustomPainter {
  final StudioPalette palette;
  final bool dark;
  const _PalettePainter(this.palette, this.dark);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = dark ? const Color(0xff17202a) : const Color(0xfff3f4f7),
    );
    for (var i = 0; i < 3; i++) {
      final center = Offset(
        size.width * [.15, .87, .55][i],
        size.height * [.15, .4, .95][i],
      );
      final rect = Rect.fromCircle(center: center, radius: size.width * .7);
      canvas.drawCircle(
        center,
        size.width * .7,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Color(palette.colors[i]).withValues(alpha: dark ? 0.46 : 0.5),
              Color(palette.colors[i]).withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    final surface = Paint()
      ..color = Colors.white.withValues(alpha: dark ? 0.12 : 0.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .12,
          size.height * .24,
          size.width * .76,
          size.height * .34,
        ),
        const Radius.circular(10),
      ),
      surface,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .12,
          size.height * .67,
          size.width * .76,
          size.height * .16,
        ),
        const Radius.circular(7),
      ),
      Paint()..color = Color(palette.primary),
    );
    canvas.drawCircle(
      Offset(size.width * .23, size.height * .41),
      size.height * .07,
      Paint()..color = Color(palette.primary).withValues(alpha: .6),
    );
    for (var i = 0; i < 2; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * .36,
            size.height * (.34 + i * .11),
            size.width * (i == 0 ? 0.38 : 0.27),
            size.height * .025,
          ),
          const Radius.circular(3),
        ),
        Paint()
          ..color = (dark ? Colors.white : const Color(0xff334155)).withValues(
            alpha: .35,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_PalettePainter old) =>
      palette.id != old.palette.id || dark != old.dark;
}
