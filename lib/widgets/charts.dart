import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/theme.dart';

void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint, {double dash = 5, double gap = 4}) {
  final total = (b - a).distance;
  final dir = (b - a) / total;
  for (var d = 0.0; d < total; d += dash + gap) {
    canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), paint);
  }
}

/// Invested (teal, filled) against left idle (grey, dashed) over 12 months.
class GrowthChart extends StatelessWidget {
  final List<double> invested;
  final List<double> idle;
  const GrowthChart({super.key, required this.invested, required this.idle});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 130,
        width: double.infinity,
        child: CustomPaint(painter: _GrowthPainter(invested, idle)),
      );
}

class _GrowthPainter extends CustomPainter {
  final List<double> invested;
  final List<double> idle;
  _GrowthPainter(this.invested, this.idle);

  @override
  void paint(Canvas canvas, Size size) {
    final base = idle.first;
    final span = math.max(invested.last - base, 1.0);
    final lo = base - span * 0.45;
    final hi = invested.last + span * 0.08;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    double x(int i) => i / (invested.length - 1) * size.width;

    final line = Path()..moveTo(0, y(invested.first));
    for (var i = 1; i < invested.length; i++) {
      line.lineTo(x(i), y(invested[i]));
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = AppColors.tealSoft);
    canvas.drawPath(
        line,
        Paint()
          ..color = AppColors.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    _dashedLine(
        canvas,
        Offset(0, y(idle.first)),
        Offset(size.width, y(idle.last)),
        Paint()
          ..color = AppColors.faint
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_GrowthPainter old) => old.invested != invested || old.idle != idle;
}

/// Projected daily balance as a step line; the part below zero is shaded.
class CashflowChart extends StatelessWidget {
  final List<double> balances;
  final double overdraftLimit;
  const CashflowChart({super.key, required this.balances, this.overdraftLimit = 0});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 130,
        width: double.infinity,
        child: CustomPaint(painter: _CashflowPainter(balances, overdraftLimit)),
      );
}

class _CashflowPainter extends CustomPainter {
  final List<double> balances;
  final double overdraftLimit;
  _CashflowPainter(this.balances, this.overdraftLimit);

  @override
  void paint(Canvas canvas, Size size) {
    final minV = math.min(balances.reduce(math.min), overdraftLimit > 0 ? -overdraftLimit : 0.0);
    final maxV = math.max(balances.reduce(math.max), 0.0);
    final pad = (maxV - minV) * 0.08;
    final lo = minV - pad, hi = maxV + pad;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    double x(int i) => i / (balances.length - 1) * size.width;
    final zeroY = y(0);

    final line = Path()..moveTo(0, y(balances.first));
    for (var i = 1; i < balances.length; i++) {
      line
        ..lineTo(x(i), y(balances[i - 1]))
        ..lineTo(x(i), y(balances[i]));
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, zeroY, size.width, size.height));
    final below = Path.from(line)
      ..lineTo(size.width, zeroY)
      ..lineTo(0, zeroY)
      ..close();
    canvas.drawPath(below, Paint()..color = AppColors.amberSoft);
    canvas.restore();

    final grey = Paint()
      ..color = AppColors.faint
      ..strokeWidth = 1.5;
    _dashedLine(canvas, Offset(0, zeroY), Offset(size.width, zeroY), grey);
    if (overdraftLimit > 0) {
      final odY = y(-overdraftLimit);
      _dashedLine(
          canvas,
          Offset(0, odY),
          Offset(size.width, odY),
          Paint()
            ..color = AppColors.teal
            ..strokeWidth = 1.5,
          dash: 3,
          gap: 3);
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = AppColors.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = ui.StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_CashflowPainter old) => old.balances != balances || old.overdraftLimit != overdraftLimit;
}
