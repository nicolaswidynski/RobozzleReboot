import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/screens/game_screen.dart';

import 'fake_secure_storage.dart';
import 'test_level.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();
  });

  testWidgets(
      'reopening a solved level restores the winning program instead of a blank one',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [testLevel()])),
    );
    await tester.pumpAndSettle();

    // "forward" is selected by default; 3 forwards solves the 4-tile strip.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(DragTarget<ProgramInstruction>).at(i));
      await tester.pump();
    }
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.pumpAndSettle();
    }
    expect(find.text('Clear!'), findsOneWidget);

    // Simulate leaving and reopening the same level fresh — a brand new
    // GameScreen instance, as HomeScreen would create.
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(levels: [testLevel()])),
    );
    await tester.pumpAndSettle();

    // The saved program should already be in place, not a blank slate.
    expect(
      find.descendant(
        of: find.byType(DragTarget<ProgramInstruction>).at(0),
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DragTarget<ProgramInstruction>).at(1),
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DragTarget<ProgramInstruction>).at(2),
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );
  });
}
