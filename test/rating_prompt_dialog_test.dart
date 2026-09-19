import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/landing_screen.dart';

import 'fake_secure_storage.dart';

Future<void> _openLanding(WidgetTester tester, {required Key key}) async {
  await tester.pumpWidget(MaterialApp(home: LandingScreen(key: key)));
  await tester.pump(); // first frame -> post-frame callback fires
  await tester.pump(); // let the async shouldShow() check resolve
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();
  });

  testWidgets('does not ask before the third launch', (tester) async {
    SharedPreferences.setMockInitialValues({'rating_prompt_launch_count': 2});
    await _openLanding(tester, key: const ValueKey('a'));

    expect(find.text('Enjoying Robozzle?'), findsNothing);
  });

  testWidgets(
      'asks on the third launch, "Not now" dismisses it, and it never comes '
      'back on a later launch', (tester) async {
    SharedPreferences.setMockInitialValues({'rating_prompt_launch_count': 3});
    await _openLanding(tester, key: const ValueKey('third'));

    expect(find.text('Enjoying Robozzle?'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Enjoying Robozzle?'), findsNothing);

    // A fourth launch (new LandingScreen state, more launches counted).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('rating_prompt_launch_count', 4);
    await _openLanding(tester, key: const ValueKey('fourth'));

    expect(find.text('Enjoying Robozzle?'), findsNothing);
  });

  testWidgets('dismissing by tapping outside still counts as the one ask',
      (tester) async {
    SharedPreferences.setMockInitialValues({'rating_prompt_launch_count': 3});
    await _openLanding(tester, key: const ValueKey('first'));
    expect(find.text('Enjoying Robozzle?'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5)); // the barrier
    await tester.pumpAndSettle();
    expect(find.text('Enjoying Robozzle?'), findsNothing);

    await _openLanding(tester, key: const ValueKey('second'));
    expect(find.text('Enjoying Robozzle?'), findsNothing);
  });
}
