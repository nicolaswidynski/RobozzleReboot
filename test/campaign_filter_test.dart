import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/home_screen.dart';

void main() {
  testWidgets(
      'Campaign narrows the catalog to the 5 chosen authors, titled "Campaign"',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(
          title: 'Campaign',
          authorFilter: {'igoro', 'blake', 'markbyers', 'snydej', 'stingray'},
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
    // in the bundled catalog, verified directly against the asset.
    expect(find.text('189 puzzles'), findsOneWidget);
  });
}
