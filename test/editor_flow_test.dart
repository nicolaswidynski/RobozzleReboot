import 'package:flutter/material.dart' hide GridTile;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/custom_puzzle_store.dart';
import 'package:robozzle_reboot/data/editor_draft_store.dart';
import 'package:robozzle_reboot/models/direction.dart';
import 'package:robozzle_reboot/models/grid_tile.dart';
import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/models/level.dart';
import 'package:robozzle_reboot/models/tile_color.dart';
import 'package:robozzle_reboot/screens/editor/editor_home_screen.dart';
import 'package:robozzle_reboot/screens/editor/editor_screen.dart';
import 'package:robozzle_reboot/screens/editor/editor_test_screen.dart';

// EditorScreen's body is a plain ListView, which (like ListView.builder)
// only builds children within its viewport/cache extent — the "Test
// Solution" button starts off-screen. The built-in tester.scrollUntilVisible
// can't be used here since it needs a single unambiguous Scrollable and the
// TextField's internal EditableText adds a second one, so this drags the
// ListView directly instead.
Future<void> _scrollToVisible(
  WidgetTester tester,
  Finder finder, {
  bool up = false,
}) async {
  final delta = up ? const Offset(0, 300) : const Offset(0, -300);
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(ListView).first, delta);
    await tester.pump();
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'tapping the direction control cycles the starting direction through '
      'all 4 facings', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditorScreen()));
    await tester.pumpAndSettle();

    // Defaults to facing Right, then cycles Down -> Left -> Up -> Right.
    for (final next in ['Facing Down', 'Facing Left', 'Facing Up', 'Facing Right']) {
      final directionControl = find.textContaining('Facing ');
      await _scrollToVisible(tester, directionControl);
      await tester.tap(directionControl);
      await tester.pump();
      expect(find.text(next), findsOneWidget);
    }
  });

  testWidgets('Test Solution blocks with a validation error when no title '
      'is set', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditorScreen()));
    await tester.pumpAndSettle();

    final testSolutionButton =
        find.widgetWithText(ElevatedButton, 'Test Solution');
    await _scrollToVisible(tester, testSolutionButton);
    await tester.tap(testSolutionButton);
    await tester.pump();

    expect(find.text('Give your puzzle a title first.'), findsOneWidget);
    expect(find.byType(EditorTestScreen), findsNothing);
  });

  testWidgets('Test Solution blocks with a validation error when a title '
      "is set but there's no star", (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditorScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'My Puzzle');
    final testSolutionButton =
        find.widgetWithText(ElevatedButton, 'Test Solution');
    await _scrollToVisible(tester, testSolutionButton);
    await tester.tap(testSolutionButton);
    await tester.pump();

    expect(find.text('Place at least one star.'), findsOneWidget);
    expect(find.byType(EditorTestScreen), findsNothing);
  });

  testWidgets(
      'creating, solving, and saving a puzzle makes it playable from '
      'EditorHomeScreen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditorHomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text("You haven't made any puzzles yet."), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'New Puzzle'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Straight Line');

    // Default tool is "Red" — paint a 2-tile strip: (0,0) and (0,1).
    await tester.tap(find.byKey(const ValueKey('editor_cell_0_0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor_cell_0_1')));
    await tester.pump();

    // Switch to the Star tool and place a star on (0,1), the endpoint.
    await tester.tap(find.text('Star'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor_cell_0_1')));
    await tester.pump();

    // Start defaults to (0,0) facing right, which is now a painted tile —
    // no need to touch the Start tool. Pick a suggested difficulty of 4.
    final difficultyStar4 = find.byKey(const ValueKey('difficulty_star_4'));
    await _scrollToVisible(tester, difficultyStar4);
    await tester.tap(difficultyStar4);
    await tester.pump();

    final testSolutionButton =
        find.widgetWithText(ElevatedButton, 'Test Solution');
    await _scrollToVisible(tester, testSolutionButton);
    await tester.tap(testSolutionButton);
    await tester.pumpAndSettle();
    expect(find.byType(EditorTestScreen), findsOneWidget);

    // "forward" is selected by default; one forward crosses the 2-tile strip.
    await tester.tap(find.byType(DragTarget<ProgramInstruction>).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pumpAndSettle();

    // Two "Solved!" texts legitimately coexist: ControlBar's own status
    // label, plus this screen's bigger "you solved it, save?" overlay.
    expect(find.text('Solved!'), findsWidgets);
    expect(find.text('Save Puzzle'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Puzzle'));
    await tester.pumpAndSettle();

    // Back on EditorHomeScreen, the new puzzle is now listed.
    expect(find.byType(EditorScreen), findsNothing);
    expect(find.text('Straight Line'), findsOneWidget);
    expect(find.text("You haven't made any puzzles yet."), findsNothing);

    final saved = await CustomPuzzleStore().loadAll();
    expect(saved, hasLength(1));
    expect(saved.first.name, 'Straight Line');
    expect(saved.first.difficulty, 4);
  });

  testWidgets(
      'navigating away from an unfinished new puzzle saves a draft, which '
      'is restored the next time "New Puzzle" is opened', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditorHomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'New Puzzle'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Draft Puzzle');
    // Default tool is "Red" — paint (0,0) without ever reaching Test
    // Solution.
    await tester.tap(find.byKey(const ValueKey('editor_cell_0_0')));
    await tester.pump();

    // Leave without finishing — this is what should trigger the draft save.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);

    final draft = await EditorDraftStore().load();
    expect(draft, isNotNull);
    expect(draft!['title'], 'Draft Puzzle');
    expect((draft['rows'] as List).first, startsWith('r')); // (0,0) painted red

    // Reopening "New Puzzle" resumes the draft instead of starting blank.
    await tester.tap(find.widgetWithText(ElevatedButton, 'New Puzzle'));
    await tester.pumpAndSettle();
    expect(find.text('Draft Puzzle'), findsOneWidget);
  });

  testWidgets('the Reset button clears an in-progress new-puzzle draft',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditorScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Will be reset');
    await tester.tap(find.byKey(const ValueKey('editor_cell_0_0')));
    await tester.pump();

    await tester.tap(find.byTooltip('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Reset this puzzle?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    // Title field is back to empty (hint text showing, no entered text).
    final titleField = tester.widget<TextField>(find.byType(TextField));
    expect(titleField.controller!.text, isEmpty);
    expect(await EditorDraftStore().load(), isNull);
  });

  testWidgets(
      'Publish requires confirming an irreversibility warning, and (when '
      "not signed in) doesn't mark the puzzle as published", (tester) async {
    final level = Level(
      id: CustomPuzzleStore.newId(),
      name: 'Publishable Puzzle',
      grid: [
        [GridTile(color: TileColor.red, hasStar: true)],
      ],
      startRow: 0,
      startCol: 0,
      startDirection: Direction.right,
      slotsPerFunction: const [1, 0, 0, 0, 0],
    );
    await CustomPuzzleStore().save(level);

    await tester.pumpWidget(const MaterialApp(home: EditorHomeScreen()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Publish'), findsOneWidget);
    await tester.tap(find.byTooltip('Publish'));
    await tester.pumpAndSettle();

    expect(find.text('Publish this puzzle?'), findsOneWidget);
    expect(find.textContaining("can't be undone"), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Publish'));
    await tester.pumpAndSettle();

    // Not signed in in this test environment — publish attempt is refused
    // before ever reaching the network, and nothing is marked published.
    expect(find.text('Sign in to publish.'), findsOneWidget);
    expect(await CustomPuzzleStore().loadPublishedIds(), isEmpty);
    expect(find.byTooltip('Publish'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_rounded), findsNothing);
  });
}
