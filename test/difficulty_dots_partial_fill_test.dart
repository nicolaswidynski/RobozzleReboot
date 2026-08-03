import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/home_screen.dart';

import 'fake_secure_storage.dart';

void main() {
  testWidgets(
      'a puzzle\'s difficulty stars fill in quarters, not just on/off, to '
      'show the precise scraped rating', (tester) async {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // Loading the catalog does real dart:io file I/O (rootBundle.loadString
    // on a real asset), which never completes under testWidgets' FakeAsync
    // zone via plain pump(); runAsync briefly escapes to real time so it can.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    // "Another speed control" (sourceId 195) rates 3.33 in the bundled
    // catalog, verified directly against the asset -- searching narrows
    // the list to just this one card, so every star icon on screen
    // afterward belongs to it.
    await tester.enterText(
        find.byType(TextField), 'Another speed control');
    await tester.pump();
    // Matches both the search field's own echoed text and the level
    // card's title.
    expect(find.text('Another speed control'), findsNWidgets(2));

    // 3.33 -> 3 full stars, a quarter-filled 4th (0.33 rounds to the
    // nearest quarter, 0.25), and an empty 5th. The quarter-filled star is
    // drawn as a full star clipped to 25% width over an empty one, so
    // there are 4 "star_rounded" icons total (3 whole + 1 clipped) and 2
    // "star_border_rounded" icons (the clipped star's backing outline +
    // the fully empty 5th star).
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
    expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(2));
  });
}
