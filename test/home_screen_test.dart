import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/game_screen.dart';
import 'package:robozzle_reboot/screens/home_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('HomeScreen loads the full catalog and opens a level on tap',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // Before the asset finishes loading, a spinner is shown.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Loading the catalog does real dart:io file I/O (rootBundle.loadString
    // on a real asset), which never completes under testWidgets' FakeAsync
    // zone via plain pump(); runAsync briefly escapes to real time so it can.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    // The full scraped catalog — the app no longer ships hand-authored levels.
    expect(find.textContaining(' puzzles'), findsOneWidget);

    final firstCard = find
        .descendant(of: find.byType(ListView), matching: find.byType(InkWell))
        .first;
    await tester.tap(firstCard);
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsOneWidget);
  });
}
