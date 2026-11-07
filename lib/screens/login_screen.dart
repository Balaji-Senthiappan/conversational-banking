import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../data/mock_bank.dart';
import '../state/session.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Default to the first demo customer's username, so sign-in is one MPIN away.
  final _login = TextEditingController(text: demoLogins.first.username);
  final _mpin = TextEditingController();

  @override
  void dispose() {
    _login.dispose();
    _mpin.dispose();
    super.dispose();
  }

  // Labels sit above the fields (see _Labelled), so the decoration only carries a hint.
  InputDecoration _field({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.muted),
        counterText: '',
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.teal, width: 1.4)),
      );

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    void submit() => session.login(_login.text, _mpin.text);

    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 48, 20, 24), children: [
          const Eyebrow('AI Mode'),
          const SizedBox(height: 12),
          const Text('Banking that starts with you.', style: AppText.headline),
          const SizedBox(height: 10),
          const Text('Log in and your assistant loads your accounts, dues and offers. No menus.', style: AppText.sub),
          const SizedBox(height: 28),
          _Labelled(
            'Login',
            TextField(
              controller: _login,
              keyboardType: TextInputType.visiblePassword, // plain keyboard, no autocorrect or capitals
              autocorrect: false,
              enableSuggestions: false,
              // Login IDs never contain spaces or "+": a username, or a mobile number as digits only.
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\s+]'))],
              maxLength: 40,
              decoration: _field(hint: 'Username or mobile number, e.g. 919876500001'),
            ),
          ),
          const SizedBox(height: 14),
          _Labelled(
            'MPIN',
            TextField(
              controller: _mpin,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              obscureText: true,
              maxLength: 4,
              decoration: _field(hint: '4 digits'),
              onSubmitted: (_) => submit(),
            ),
          ),
          if (session.loginError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(session.loginError!, style: const TextStyle(color: AppColors.amber, fontSize: 13.5)),
            ),
          const SizedBox(height: 20),
          PrimaryButton('Log in', onTap: submit),
          const SizedBox(height: 24),
          // Demo customers stay folded away until the presenter opens them.
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: false,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              iconColor: AppColors.muted,
              collapsedIconColor: AppColors.muted,
              title: const Text('Demo customers',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
              children: [
                for (final d in demoLogins) ...[
                  OutlineCard(
                    onTap: () {
                      _login.text = d.username;
                      _mpin.text = d.mpin;
                      submit();
                    },
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.label, style: AppText.cardTitle),
                          const SizedBox(height: 4),
                          Text('Login ${d.username} or ${d.mobileLogin} · MPIN ${d.mpin}', style: AppText.note),
                        ]),
                      ),
                      const Icon(Icons.arrow_forward, color: AppColors.teal),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// A field with its label above it rather than inside it.
class _Labelled extends StatelessWidget {
  final String label;
  final Widget field;
  const _Labelled(this.label, this.field);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
        const SizedBox(height: 6),
        field,
      ]);
}
