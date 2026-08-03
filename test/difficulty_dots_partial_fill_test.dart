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
    // the list to just this one card, so its 5 stars are the only
    // _StarPainter-backed CustomPaint widgets on screen.
    await tester.enterText(
        find.byType(TextField), 'Another speed control');
    await tester.pump();

    // _StarPainter is private, so it can't be named as a type here, but
    // its "fraction" field isn't itself a private identifier -- Dart's
    // library privacy hides the class name, not a public-named member on
    // an instance of it, so reading it dynamically still works.
    final starFractions = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .where((p) => p != null && p.runtimeType.toString() == '_StarPainter')
        .map((p) => (p as dynamic).fraction as double)
        .toList();

    // 3.33 -> 3 full stars, a quarter-filled 4th (0.33 rounds to the
    // nearest quarter, 0.25), and an empty 5th.
    expect(starFractions, [1.0, 1.0, 1.0, 0.25, 0.0]);
  });
}
