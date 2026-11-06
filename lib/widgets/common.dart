import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// The four-point sparkle used on every screen's eyebrow.
class Sparkle extends StatelessWidget {
  final double size;
  final Color color;
  const Sparkle({super.key, this.size = 12, this.color = AppColors.teal});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _SparklePainter(color));
}

class _SparklePainter extends CustomPainter {
  final Color color;
  _SparklePainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height, k = 0.16;
    final path = Path()
      ..moveTo(w / 2, 0)
      ..quadraticBezierTo(w * (0.5 + k), h * (0.5 - k), w, h / 2)
      ..quadraticBezierTo(w * (0.5 + k), h * (0.5 + k), w / 2, h)
      ..quadraticBezierTo(w * (0.5 - k), h * (0.5 + k), 0, h / 2)
      ..quadraticBezierTo(w * (0.5 - k), h * (0.5 - k), w / 2, 0);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.color != color;
}

class Eyebrow extends StatelessWidget {
  final String text;
  const Eyebrow(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        const Sparkle(),
        const SizedBox(width: 8),
        Text(text, style: AppText.eyebrow),
      ]);
}

class OutlineCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const OutlineCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.page,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

class _Button extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final double height;
  final bool expand;
  final IconData? icon;

  const _Button(this.label, this.onTap, this.background, this.foreground,
      {this.height = 46, this.expand = true, this.icon});

  @override
  Widget build(BuildContext context) {
    final text = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (icon != null) ...[Icon(icon, size: 18, color: foreground), const SizedBox(width: 6)],
      Flexible(
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: foreground)),
      ),
    ]);
    return SizedBox(
      width: expand ? double.infinity : null,
      height: height,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: onTap == null ? background.withValues(alpha: 0.45) : background,
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: text,
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool expand;
  final IconData? icon;
  const PrimaryButton(this.label, {super.key, this.onTap, this.expand = true, this.icon});

  @override
  Widget build(BuildContext context) =>
      _Button(label, onTap, AppColors.navy, Colors.white, height: 48, expand: expand, icon: icon);
}

/// Primary button that shows a spinner for a moment before running [onConfirm],
/// so a mock transaction feels like it went to the bank and back.
class ProcessingButton extends StatefulWidget {
  final String label;
  final String processingLabel;
  final Future<void> Function() onConfirm;
  const ProcessingButton(this.label, {super.key, required this.processingLabel, required this.onConfirm});

  @override
  State<ProcessingButton> createState() => _ProcessingButtonState();
}

class _ProcessingButtonState extends State<ProcessingButton> {
  static const _delays = [500, 1000, 1500]; // ms; varies so it feels like a real round trip
  static final _random = math.Random();
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    await Future<void>.delayed(Duration(milliseconds: _delays[_random.nextInt(_delays.length)]));
    await widget.onConfirm();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_busy) return PrimaryButton(widget.label, onTap: _run);
    return Container(
      height: 48,
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Text(widget.processingLabel,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Colors.white)),
      ]),
    );
  }
}

class SoftButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool expand;
  final IconData? icon;
  const SoftButton(this.label, {super.key, this.onTap, this.expand = true, this.icon});

  @override
  Widget build(BuildContext context) =>
      _Button(label, onTap, AppColors.tealSoft, AppColors.tealDark, expand: expand, icon: icon);
}

class PillChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const PillChip(this.label, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.chip,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink)),
          ),
        ),
      );
}

/// Label, proportional bar, amount. Used for spend categories.
class BarRow extends StatelessWidget {
  final String label;
  final String value;
  final double fraction;
  final Color color;
  final double labelWidth;
  const BarRow({
    super.key,
    required this.label,
    required this.value,
    required this.fraction,
    this.color = AppColors.teal,
    this.labelWidth = 72,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(
            width: labelWidth,
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(children: [
                Container(height: 10, color: AppColors.tealSoft),
                FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: Container(height: 10, color: color),
                ),
              ]),
            ),
          ),
          SizedBox(
            width: 78,
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
          ),
        ]),
      );
}

void showResult(BuildContext context, String message, {String? detail}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(detail, style: const TextStyle(fontSize: 12.5, color: Color(0xFFC9D6E2))),
          ),
      ]),
    ));
}
