import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../data/mock_bank.dart';
import '../state/session.dart';
import '../widgets/common.dart';

/// Login, laid out like the client's existing mobile app, top to bottom:
/// "Welcome Back", "Login to Continue", the customer, "Enter MPIN" with one box per
/// digit, "Forgot MPIN?", then "Need Help?" and the version at the bottom.
///
/// There is no login-name field: as in the client's app, the device already knows
/// who the customer is. The demo defaults to Priya; tapping her name lets the
/// presenter switch to another demo customer. Signing in happens as soon as the
/// fourth digit is entered, so there is no Log in button.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  /// Shown at the bottom of the screen, matching the client's app.
  static const appVersion = '4.0.1';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _digits = 4;

  final _mpin = TextEditingController();
  final _focus = FocusNode();
  DemoLogin _customer = demoLogins.first; // Priya by default
  bool _busy = false;
  bool _wrongMpin = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {})); // redraw the highlighted box
  }

  @override
  void dispose() {
    _mpin.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String value) async {
    setState(() => _wrongMpin = false);
    if (value.length < _digits || _busy) return;
    _busy = true;
    final session = SessionScope.of(context);
    await session.login(_customer.username, value);
    _busy = false;
    // Still on this screen means the MPIN was wrong: clear the boxes for another try.
    if (mounted && session.stage == Stage.loggedOut) {
      _mpin.clear();
      _focus.requestFocus();
      setState(() => _wrongMpin = true);
    }
  }

  /// Presenter-only: pick which demo customer is "on this phone".
  Future<void> _switchCustomer() async {
    final picked = await showModalBottomSheet<DemoLogin>(
      context: context,
      backgroundColor: AppColors.page,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Demo customers', style: AppText.cardTitle),
            const SizedBox(height: 12),
            for (final d in demoLogins) ...[
              OutlineCard(
                onTap: () => Navigator.pop(context, d),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.label, style: AppText.cardTitle),
                      const SizedBox(height: 4),
                      Text('MPIN ${d.mpin}', style: AppText.note),
                    ]),
                  ),
                  if (d == _customer) const Icon(Icons.check, color: AppColors.teal),
                ]),
              ),
              const SizedBox(height: 10),
            ],
          ]),
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _customer = picked;
        _mpin.clear();
        _wrongMpin = false;
      });
    }
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final firstName = _customer.label.split(' ').first;

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: LayoutBuilder(
          // Scrolls on short screens (or with the keyboard up); otherwise the help
          // button and version sit at the bottom, as in the client's app.
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 40),
                  const Text('Welcome Back', style: _Styles.title),
                  const Text('Login to Continue', style: _Styles.title),
                  const SizedBox(height: 28),

                  // The customer this phone belongs to, with an icon. Not an input field.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _switchCustomer,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.tealSoft,
                            child: Icon(Icons.person, color: AppColors.tealDark, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Text(firstName, style: AppText.cardTitle),
                          const SizedBox(width: 2),
                          const Icon(Icons.expand_more, size: 20, color: AppColors.faint),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  const Text('Enter MPIN', textAlign: TextAlign.center, style: _Styles.label),
                  const SizedBox(height: 14),
                  _MpinBoxes(controller: _mpin, focusNode: _focus, length: _digits, onChanged: _onChanged),
                  if (_wrongMpin)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Incorrect MPIN. Please try again.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.amber, fontSize: 13.5)),
                    ),
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: () => showResult(context, 'Resetting the MPIN is not part of this demo'),
                      child: const Text('Forgot MPIN?', style: _Styles.link),
                    ),
                  ),

                  const Spacer(),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () => showResult(context, 'Help is not part of this demo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.ink, width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      ),
                      child: const Text('Need Help?', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Version ${LoginScreen.appVersion}', textAlign: TextAlign.center, style: AppText.note),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Styles {
  static const title = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.3, color: AppColors.ink);
  static const label = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted);
  static const link = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    decoration: TextDecoration.underline,
  );
}

/// One box per MPIN digit. A single real text field sits underneath and takes the
/// typing (keyboard, paste, backspace); the boxes on top only display it.
class _MpinBoxes extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final ValueChanged<String> onChanged;

  const _MpinBoxes({required this.controller, required this.focusNode, required this.length, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final filled = controller.text.length;
    return SizedBox(
      height: 60,
      child: Stack(children: [
        // The input itself: invisible, but it receives taps, focus and keystrokes.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(length)],
              showCursor: false,
              enableInteractiveSelection: false,
              decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
              onChanged: onChanged,
            ),
          ),
        ),
        // The boxes: drawn on top, and let taps through to the field.
        IgnorePointer(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < length; i++) ...[
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
                    color: i == filled && focusNode.hasFocus ? AppColors.teal : AppColors.border,
                    width: i == filled && focusNode.hasFocus ? 1.6 : 1.2,
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
