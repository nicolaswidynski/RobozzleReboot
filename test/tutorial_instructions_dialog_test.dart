import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/tutorial_levels.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';

import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'a tutorial level shows its instructions dialog on load, dismissible '
      'via "Got it", and re-openable via the header help button',
      (tester) async {
    final level = tutorialLevels[0];
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [level])),
    );
    await tester.pumpAndSettle();

    expect(find.text(level.name), findsWidgets); // title + dialog heading
    expect(find.text(level.description), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text(level.description), findsNothing);

    // Re-open on demand via the help icon in the header.
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text(level.description), findsOneWidget);
  });

  testWidgets('a level without a description never shows the dialog or '
      'the help icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [testLevel()])),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    expect(find.text('Got it'), findsNothing);
  });
}
