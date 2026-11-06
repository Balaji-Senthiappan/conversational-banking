import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../state/session.dart';
import '../widgets/common.dart';

/// Shows the data being assembled: profile, balances, transactions, dues, projection.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Eyebrow('Getting your day ready'),
            const SizedBox(height: 12),
            Text('Hello, ${session.loadingName}.', style: AppText.headline),
            const SizedBox(height: 10),
            const Text('Reading your accounts so you do not have to.', style: AppText.sub),
            const SizedBox(height: 28),
            for (var i = 0; i < loadSteps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: i < session.stepsDone
                        ? const Icon(Icons.check_circle, color: AppColors.teal, size: 22)
                        : i == session.stepsDone
                            ? const Padding(
                                padding: EdgeInsets.all(3),
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.teal),
                              )
                            : const Icon(Icons.circle_outlined, color: AppColors.border, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Text(loadSteps[i],
                      style: TextStyle(
                        fontSize: 15.5,
                        color: i <= session.stepsDone ? AppColors.ink : AppColors.faint,
                      )),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
