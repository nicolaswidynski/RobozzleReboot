import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/home_screen.dart';

void main() {
  testWidgets(
      'Campaign narrows the catalog to the chosen authors, titled '
      '"Campaign", with no Sort-by choice and no Top 30 chip',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

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
          allowSortChoice: false,
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

    // No Sort-by choice — always sorted by difficulty.
    expect(find.text('Sort by'), findsNothing);
    expect(find.text('Difficulty'), findsNothing);
    expect(find.text('Popularity'), findsNothing);
    // Top 30 was removed entirely.
    expect(find.text('Top 30'), findsNothing);
    // The per-difficulty filter chips are still there.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
  });
}
