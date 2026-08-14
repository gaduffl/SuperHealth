import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The soft floral wash behind easy mode.
///
/// Drawn rather than shipped: an image would be a second asset to keep in step
/// with the theme, would look wrong in dark mode, and would cost download size
/// for decoration. These are a handful of five-petal shapes at low opacity,
/// tinted from the active colour scheme, so the wash follows the palette,
/// the brightness, and the high-contrast setting without a single asset.
class BlossomBackground extends StatelessWidget {
  const BlossomBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: 0.35),
              scheme.surface,
            ),
            scheme.surface,
            Color.alphaBlend(
              scheme.tertiaryContainer.withValues(alpha: 0.30),
              scheme.surface,
            ),
          ],
        ),
      ),
      child: CustomPaint(
        // A painter with a child paints behind it, so the content sits on top
        // and nothing here can intercept a tap.
        painter: _BlossomPainter(
          petal: scheme.primary.withValues(alpha: 0.09),
          leaf: scheme.tertiary.withValues(alpha: 0.08),
          heart: scheme.secondary.withValues(alpha: 0.12),
        ),
        child: child,
      ),
    );
  }
}

/// One blossom's placement, in fractions of the painted area.
typedef _Blossom = ({double x, double y, double radius, double turn});

class _BlossomPainter extends CustomPainter {
  const _BlossomPainter({
    required this.petal,
    required this.leaf,
    required this.heart,
  });

  final Color petal;
  final Color leaf;
  final Color heart;

  /// Fixed placements rather than random ones: the background must not
  /// reshuffle itself on every rebuild, and a layout that moves under a
  /// scrolling list reads as a rendering fault.
  static const _blossoms = <_Blossom>[
    (x: 0.06, y: 0.04, radius: 46, turn: 0.0),
    (x: 0.88, y: 0.11, radius: 68, turn: 0.6),
    (x: 0.22, y: 0.35, radius: 32, turn: 1.1),
    (x: 0.94, y: 0.52, radius: 40, turn: 0.3),
    (x: 0.10, y: 0.72, radius: 58, turn: 0.9),
    (x: 0.68, y: 0.86, radius: 44, turn: 1.4),
    (x: 0.40, y: 0.97, radius: 36, turn: 0.2),
  ];

  static const _petalCount = 5;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < _blossoms.length; index++) {
      final blossom = _blossoms[index];
      canvas.save();
      canvas.translate(blossom.x * size.width, blossom.y * size.height);
      canvas.rotate(blossom.turn);
      _paintBlossom(
        canvas,
        blossom.radius,
        // Alternating tints keep seven identical stamps from reading as a
        // repeated texture.
        index.isEven ? petal : leaf,
      );
      canvas.restore();
    }
  }

  void _paintBlossom(Canvas canvas, double radius, Color color) {
    final brush = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    for (var petal = 0; petal < _petalCount; petal++) {
      canvas.save();
      canvas.rotate(petal * 2 * math.pi / _petalCount);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, -radius * 0.58),
          width: radius * 0.82,
          height: radius * 1.15,
        ),
        brush,
      );
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, radius * 0.26, Paint()..color = heart);
  }

  @override
  bool shouldRepaint(_BlossomPainter oldDelegate) =>
      oldDelegate.petal != petal ||
      oldDelegate.leaf != leaf ||
      oldDelegate.heart != heart;
}
