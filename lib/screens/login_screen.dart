import 'package:flutter/material.dart';

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
  // Default to the first demo customer so sign-in is one MPIN away.
  final _mobile = TextEditingController(text: demoLogins.first.mobile);
  final _mpin = TextEditingController();

  @override
  void dispose() {
    _mobile.dispose();
    _mpin.dispose();
    super.dispose();
  }

  InputDecoration _field(String label, {String? prefix}) => InputDecoration(
        labelText: label,
        prefixText: prefix,
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
    void submit() => session.login(_mobile.text, _mpin.text);

    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 48, 20, 24), children: [
          const Eyebrow('AI Mode'),
          const SizedBox(height: 12),
          const Text('Banking that starts with you.', style: AppText.headline),
          const SizedBox(height: 10),
          const Text('Log in and your assistant loads your accounts, dues and offers. No menus.', style: AppText.sub),
          const SizedBox(height: 28),
          TextField(
            controller: _mobile,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: _field('Mobile number', prefix: '+91 '),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _mpin,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            decoration: _field('MPIN'),
            onSubmitted: (_) => submit(),
          ),
          if (session.loginError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(session.loginError!, style: const TextStyle(color: AppColors.amber, fontSize: 13.5)),
            ),
          const SizedBox(height: 20),
          PrimaryButton('Log in', onTap: submit),
          const SizedBox(height: 32),
          const Text('Demo customers',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
          const SizedBox(height: 10),
          for (final d in demoLogins) ...[
            OutlineCard(
              onTap: () {
                _mobile.text = d.mobile;
                _mpin.text = d.mpin;
                submit();
              },
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.label, style: AppText.cardTitle),
                    const SizedBox(height: 4),
                    Text('Mobile ${d.mobile} · MPIN ${d.mpin}', style: AppText.note),
                  ]),
                ),
                const Icon(Icons.arrow_forward, color: AppColors.teal),
              ]),
            ),
            const SizedBox(height: 10),
          ],
        ]),
      ),
    );
  }
}
