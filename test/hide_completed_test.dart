import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/home_screen.dart';

void main() {
  testWidgets(
      'Hide completed filters out completed puzzles and restores them when toggled off',
      (tester) async {
    // "catalog-195" is a real entry ("Another speed control") in the
    // bundled catalog asset — mark it completed before HomeScreen loads.
    SharedPreferences.setMockInitialValues({
      'completed_level_ids': ['catalog-195'],
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // Loading the catalog does real dart:io file I/O (rootBundle.loadString
    // on a real asset), which never completes under testWidgets' FakeAsync
    // zone via plain pump(); runAsync briefly escapes to real time so it can.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('908 puzzles'), findsOneWidget);

    await tester.tap(find.text('Hide completed'));
    await tester.pump();

    expect(find.text('907 puzzles'), findsOneWidget);

    await tester.tap(find.text('Hide completed'));
    await tester.pump();

    expect(find.text('908 puzzles'), findsOneWidget);
  });
}
