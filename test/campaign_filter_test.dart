import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/home_screen.dart';

import 'fake_secure_storage.dart';

void main() {
  testWidgets(
      'Campaign narrows the catalog to the chosen authors, titled '
      '"Campaign", with the exact same Sort-by/filter UI as Community '
      'Puzzles', (tester) async {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(
          title: 'Campaign',
          authorFilter: {
            'igoro',
            'blake',
            'markbyers',
            'snydej',
            'stingray',
            'wido',
          },
        ),
      ),
    );

    // Loading the catalog does real dart:io file I/O (rootBundle.loadString
    // on a real asset), which never completes under testWidgets' FakeAsync
    // zone via plain pump(); runAsync briefly escapes to real time so it can.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('Campaign'), findsOneWidget);
    // 33 (igoro) + 86 (snydej) + 65 (markbyers) + 4 (stingray) + 1 (blake)
    // in the bundled catalog, verified directly against the asset. "wido"
    // contributes 0 here since their puzzles are server-published, not part
    // of the bundled asset this test loads.
    expect(find.text('189 puzzles'), findsOneWidget);

    // Campaign is no longer a stripped-down HomeScreen — same Sort-by
    // chips as Community Puzzles.
    expect(find.text('Sort by'), findsOneWidget);
    expect(find.text('Difficulty'), findsOneWidget);
    expect(find.text('Popularity'), findsOneWidget);
    // The per-difficulty filter chips are there too.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
  });
}
