import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/mock_bank.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import '../widgets/mpin_boxes.dart';

/// Login, laid out like the client's existing mobile app, top to bottom:
/// "Welcome Back", "Login to Continue", the customer, "Enter MPIN" with one box per
/// digit, "Forgot MPIN?", then "Need Help?" and the version at the bottom.
///
/// There is no login-name field: as in the client's app, the device already knows
/// who the customer is. Signing in happens as soon as the fourth digit is entered,
/// so there is no Log in button.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  /// Shown at the bottom of the screen, matching the client's app.
  static const appVersion = '4.0.1';

  /// The customer this phone belongs to. Fixed to Priya: the login screen has no
  /// way to switch customer. Rajesh's data is still in MockBankApi, for tests or a
  /// later build that brings switching back.
  static final customer = demoLogins.first;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mpin = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _wrongMpin = false;

  @override
  void dispose() {
    _mpin.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String value) async {
    if (_wrongMpin) setState(() => _wrongMpin = false);
    if (value.length < mpinLength || _busy) return;
    _busy = true;
    final session = SessionScope.of(context);
    await session.login(LoginScreen.customer.username, value);
    _busy = false;
    // Still on this screen means the MPIN was wrong: clear the boxes for another try.
    if (mounted && session.stage == Stage.loggedOut) {
      _mpin.clear();
      _focus.requestFocus();
      setState(() => _wrongMpin = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = LoginScreen.customer.label.split(' ').first;

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
                  Row(children: [
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.tealSoft,
                      child: Icon(Icons.person, color: AppColors.tealDark, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Text(firstName, style: AppText.cardTitle),
                  ]),
                  const SizedBox(height: 36),

                  const Text('Enter MPIN', textAlign: TextAlign.center, style: _Styles.label),
                  const SizedBox(height: 14),
                  MpinBoxes(controller: _mpin, focusNode: _focus, onChanged: _onChanged),
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
