import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Marca do HopeCash Retaguarda — reaproveita o mesmo símbolo do app,
/// acrescentando o selo "Retaguarda".
class HopeCashLogo extends StatelessWidget {
  const HopeCashLogo({
    super.key,
    this.compact = false,
    this.showTagline = false,
    this.iconSize = 48,
  });

  final bool compact;
  final bool showTagline;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final mark = _HopeCashMark(size: iconSize);
    if (compact) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mark,
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                        children: [
                          TextSpan(
                            text: 'Hope',
                            style: TextStyle(color: textColor),
                          ),
                          const TextSpan(
                            text: 'Cash',
                            style: TextStyle(color: AppTheme.hopeGreen),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const _RetaguardaBadge(),
                  ],
                ),
              ),
              if (showTagline)
                Text(
                  'Painel administrativo',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RetaguardaBadge extends StatelessWidget {
  const _RetaguardaBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.skyBlue.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.skyBlue.withValues(alpha: 0.30)),
      ),
      child: Text(
        'RETAGUARDA',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppTheme.skyBlue,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _HopeCashMark extends StatelessWidget {
  const _HopeCashMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _HopeCashMarkPainter()),
    );
  }
}

class _HopeCashMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 48;
    final radius = Radius.circular(2 * unit);
    final bars = [
      (x: 12.0, h: 18.0, color: AppTheme.skyBlue),
      (x: 21.0, h: 28.0, color: AppTheme.hopeGreen),
      (x: 30.0, h: 36.0, color: AppTheme.success),
    ];

    for (final bar in bars) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          bar.x * unit,
          (38 - bar.h) * unit,
          7 * unit,
          bar.h * unit,
        ),
        radius,
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [AppTheme.deepBlue.withValues(alpha: 0.9), bar.color],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
    }

    final arcPaint = Paint()
      ..color = AppTheme.deepBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * unit
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(5 * unit, 14 * unit, 37 * unit, 30 * unit),
      math.pi * 0.18,
      math.pi * 0.72,
      false,
      arcPaint,
    );

    final arrowPaint = Paint()
      ..color = AppTheme.deepBlue
      ..style = PaintingStyle.fill;
    final arrow = Path()
      ..moveTo(39 * unit, 14 * unit)
      ..lineTo(44 * unit, 12 * unit)
      ..lineTo(42 * unit, 18 * unit)
      ..close();
    canvas.drawPath(arrow, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
