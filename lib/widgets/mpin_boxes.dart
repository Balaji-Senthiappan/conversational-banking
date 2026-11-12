import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

/// Number of MPIN digits, on the login screen and on every confirmation sheet.
const mpinLength = 4;

/// One box per MPIN digit, as in the client's app. A single real text field sits
/// underneath and takes the typing (keyboard, paste, backspace); the boxes on top
/// only display it, with a dot per digit entered.
class MpinBoxes extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  final bool enabled;

  const MpinBoxes({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.autofocus = true,
    this.enabled = true,
  });

  @override
  State<MpinBoxes> createState() => _MpinBoxesState();
}

class _MpinBoxesState extends State<MpinBoxes> {
  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Redraw on every digit and on focus changes (the highlighted box moves).
    widget.controller.addListener(_redraw);
    widget.focusNode.addListener(_redraw);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_redraw);
    widget.focusNode.removeListener(_redraw);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.controller.text.length;
    final focused = widget.focusNode.hasFocus && widget.enabled;
    return SizedBox(
      height: 60,
      child: Stack(children: [
        // The input itself: invisible, but it receives taps, focus and keystrokes.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(mpinLength)],
              showCursor: false,
              enableInteractiveSelection: false,
              decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
              onChanged: widget.onChanged,
            ),
          ),
        ),
        // The boxes: drawn on top, and let taps through to the field.
        IgnorePointer(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < mpinLength; i++) ...[
              if (i > 0) const SizedBox(width: 18),
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 52,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.page,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    // The box the next digit goes into is highlighted.
                    color: i == filled && focused ? AppColors.teal : AppColors.border,
                    width: i == filled && focused ? 1.6 : 1.2,
                  ),
                ),
                child: i < filled
                    ? Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                      )
                    : null,
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Confirms an action with the customer's MPIN, typed into [MpinBoxes].
///
/// When the fourth digit goes in, [check] decides whether the MPIN is right. A
/// wrong MPIN clears the boxes and says so. A right one shows a spinner with
/// [processingLabel] for 0.5, 1 or 1.5 seconds, so it feels like a round trip to
/// the bank, and then runs [onConfirmed].
class MpinConfirm extends StatefulWidget {
  final String label;
  final String processingLabel;
  final bool Function(String mpin) check;
  final Future<void> Function() onConfirmed;

  const MpinConfirm({
    super.key,
    required this.label,
    required this.processingLabel,
    required this.check,
    required this.onConfirmed,
  });

  @override
  State<MpinConfirm> createState() => _MpinConfirmState();
}

class _MpinConfirmState extends State<MpinConfirm> {
  static const _delays = [500, 1000, 1500]; // ms, as on the old confirm button
  static final _random = math.Random();

  final _mpin = TextEditingController();
  final _focus = FocusNode();
  bool _wrong = false;
  bool _busy = false;

  @override
  void dispose() {
    _mpin.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String value) async {
    if (_wrong) setState(() => _wrong = false);
    if (value.length < mpinLength || _busy) return;
    if (!widget.check(value)) {
      _mpin.clear();
      _focus.requestFocus();
      setState(() => _wrong = true);
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(Duration(milliseconds: _delays[_random.nextInt(_delays.length)]));
    await widget.onConfirmed();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return Container(
        height: 60,
        decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
          const SizedBox(width: 12),
          Text(widget.processingLabel,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Colors.white)),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(widget.label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted)),
      const SizedBox(height: 12),
      MpinBoxes(controller: _mpin, focusNode: _focus, onChanged: _onChanged),
      if (_wrong)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('Incorrect MPIN. Please try again.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.amber, fontSize: 13.5)),
        ),
    ]);
  }
}
