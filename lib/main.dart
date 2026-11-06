import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'screens/home_shell.dart';
import 'screens/loading_screen.dart';
import 'screens/login_screen.dart';
import 'state/session.dart';

void main() => runApp(const BankCxApp());

class BankCxApp extends StatefulWidget {
  const BankCxApp({super.key});

  @override
  State<BankCxApp> createState() => _BankCxAppState();
}

class _BankCxAppState extends State<BankCxApp> {
  final _session = BankSession();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SessionScope(
        session: _session,
        child: MaterialApp(
          title: 'AI Mode banking mock',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          builder: (context, child) => _PhoneFrame(child: child!),
          home: const _Root(),
        ),
      );
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: switch (session.stage) {
        Stage.loggedOut => const LoginScreen(key: ValueKey('login')),
        Stage.loading => const LoadingScreen(key: ValueKey('loading')),
        Stage.ready => const HomeShell(key: ValueKey('home')),
      },
    );
  }
}

/// On a wide window (web demo) the app sits in a phone-sized frame.
class _PhoneFrame extends StatelessWidget {
  final Widget child;
  const _PhoneFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width < 520) return child;
    final height = math.min(mq.size.height - 32, 880.0);
    const width = 412.0;
    return ColoredBox(
      color: AppColors.backdrop,
      child: Center(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 30, offset: Offset(0, 10))],
          ),
          clipBehavior: Clip.antiAlias,
          child: MediaQuery(
            data: mq.copyWith(size: Size(width, height), padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
            child: child,
          ),
        ),
      ),
    );
  }
}
