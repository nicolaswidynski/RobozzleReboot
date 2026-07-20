import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/landing_screen.dart';

void main() {
  testWidgets('shows total points computed from completed puzzles',
      (tester) async {
    // "catalog-195" ("Another speed control") has difficulty 3 in the
    // bundled catalog asset -> (1 + 3)^2 = 16 points.
    SharedPreferences.setMockInitialValues({
      'completed_level_ids': ['catalog-195'],
    });

    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    // Computing points does real dart:io file I/O (rootBundle.loadString on
    // a real asset), which never completes under testWidgets' FakeAsync
    // zone via plain pump(); runAsync briefly escapes to real time so it can.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('16'), findsOneWidget);
  });
}
