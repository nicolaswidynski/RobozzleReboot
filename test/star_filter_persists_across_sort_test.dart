import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/home_screen.dart';

import 'fake_secure_storage.dart';

void main() {
  testWidgets(
      'the star-count filter stays applied (and visible) after switching '
      'from Difficulty to Popularity sort, instead of resetting to the '
      'full catalog', (tester) async {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // Loading the catalog does real dart:io file I/O (rootBundle.loadString
    // on a real asset), which never completes under testWidgets' FakeAsync
    // zone via plain pump(); runAsync briefly escapes to real time so it can.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    // 533 puzzles round to 3 stars in the bundled catalog, verified
    // directly against the asset.
    await tester.tap(find.text('3'));
    await tester.pump();
    expect(find.text('533 puzzles'), findsOneWidget);

    await tester.tap(find.text('Popularity'));
    await tester.pump();

    // Still filtered to 3-star puzzles -- sort mode changed, the filter
    // didn't reset -- and the filter chips themselves are still visible.
    expect(find.text('533 puzzles'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
  });
}
