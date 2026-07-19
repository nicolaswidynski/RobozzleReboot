import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/game_screen.dart';
import 'package:robozzle_reboot/widgets/robot_grid.dart';

import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('functions are visible by default and hide/show on tap without moving the grid',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    final handle = find.byKey(const Key('functions_handle'));
    final crossFade = find.byType(AnimatedCrossFade);
    expect(
      tester.widget<AnimatedCrossFade>(crossFade).crossFadeState,
      CrossFadeState.showFirst, // visible by default
    );

    final gridRectBefore = tester.getRect(find.byType(RobotGrid));

    await tester.tap(handle);
    await tester.pumpAndSettle();

    expect(
      tester.widget<AnimatedCrossFade>(crossFade).crossFadeState,
      CrossFadeState.showSecond,
    );
    expect(tester.getRect(find.byType(RobotGrid)), gridRectBefore);

    await tester.tap(handle);
    await tester.pumpAndSettle();

    expect(
      tester.widget<AnimatedCrossFade>(crossFade).crossFadeState,
      CrossFadeState.showFirst,
    );
    expect(tester.getRect(find.byType(RobotGrid)), gridRectBefore);
  });

  testWidgets('swiping the grip up/down hides and shows the functions too', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(levels: [testLevel()])));
    await tester.pumpAndSettle();

    final handle = find.byKey(const Key('functions_handle'));
    final crossFade = find.byType(AnimatedCrossFade);
    expect(
      tester.widget<AnimatedCrossFade>(crossFade).crossFadeState,
      CrossFadeState.showFirst, // visible by default
    );

    // Swipe up: no-op while already visible.
    await tester.fling(handle, const Offset(0, -60), 800);
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedCrossFade>(crossFade).crossFadeState,
      CrossFadeState.showFirst,
    );

    // Swipe down: hides.
    await tester.fling(handle, const Offset(0, 60), 800);
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedCrossFade>(crossFade).crossFadeState,
      CrossFadeState.showSecond,
    );

    // Swipe up again: shows.
    await tester.fling(handle, const Offset(0, -60), 800);
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedCrossFade>(crossFade).crossFadeState,
      CrossFadeState.showFirst,
    );
  });
}
