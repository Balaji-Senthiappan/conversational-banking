import 'package:bank_cx_mock/app/clock.dart';
import 'package:bank_cx_mock/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => clock = () => DateTime(2026, 11, 5, 8, 30));

  testWidgets('Login matches the client app and signs in on the fourth digit', (tester) async {
    await tester.pumpWidget(const BankCxApp());
    await tester.pumpAndSettle();

    // Same order as the client's app.
    for (final text in ['Welcome Back', 'Login to Continue', 'Priya', 'Enter MPIN', 'Forgot MPIN?', 'Need Help?', 'Version 4.0.1']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Welcome Back') < y('Login to Continue'), isTrue);
    expect(y('Login to Continue') < y('Enter MPIN'), isTrue);
    expect(y('Enter MPIN') < y('Forgot MPIN?'), isTrue);
    expect(y('Forgot MPIN?') < y('Need Help?'), isTrue);
    expect(y('Need Help?') < y('Version 4.0.1'), isTrue);

    // A wrong MPIN clears the boxes and says so.
    await tester.enterText(find.byType(TextField), '9999');
    await tester.pump();
    expect(find.text('Incorrect MPIN. Please try again.'), findsOneWidget);

    // The right one signs in as soon as the fourth digit goes in.
    await tester.enterText(find.byType(TextField), '1111');
    await tester.pump();
    expect(find.text('Hello, Priya.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // let the loading checklist finish
    await tester.pumpAndSettle();
    expect(find.textContaining('Good morning, Priya.'), findsOneWidget);
  });
}
