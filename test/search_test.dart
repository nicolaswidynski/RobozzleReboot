import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/home_screen.dart';

import 'fake_secure_storage.dart';

void main() {
  testWidgets('searching filters puzzles by name, case-insensitively, and clears',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // Loading the catalog does real dart:io file I/O (rootBundle.loadString
    // on a real asset), which never completes under testWidgets' FakeAsync
    // zone via plain pump(); runAsync briefly escapes to real time so it can.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('908 puzzles'), findsOneWidget);

    // 4 real catalog entries contain "stairs" (case-insensitive): "Stairs",
    // "Upstairs, downstairs", "Stairs and Ladders", "Stairs with green
    // ends.For John".
    await tester.enterText(find.byType(TextField), 'STAIRS');
    await tester.pump();

    expect(find.text('4 puzzles'), findsOneWidget);
    expect(find.text('Stairs'), findsOneWidget);

    // Clearing the search (via the X button) restores the full list.
    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pump();

    expect(find.text('908 puzzles'), findsOneWidget);
  });
}
