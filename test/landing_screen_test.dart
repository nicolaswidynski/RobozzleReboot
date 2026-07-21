import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/tutorial_levels.dart';
import 'package:robozzle_reboot/screens/auth/sign_in_screen.dart';
import 'package:robozzle_reboot/screens/coming_soon_screen.dart';
import 'package:robozzle_reboot/screens/home_screen.dart';
import 'package:robozzle_reboot/screens/landing_screen.dart';
import 'package:robozzle_reboot/screens/tutorial_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows all 5 menu entries', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    for (final label in [
      'Tutorials',
      'Campaign',
      'Community Puzzles',
      'Editor',
      'Leaderboard',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets(
      'Community Puzzles opens HomeScreen, and its back button returns to the landing page',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    await tester.tap(find.text('Community Puzzles'));
    // Not pumpAndSettle: HomeScreen shows a perpetually-animating spinner
    // while it loads the real catalog asset, which would never "settle".
    // Just pump past the page-route transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LandingScreen), findsOneWidget);
  });

  testWidgets('Tutorials opens TutorialScreen, listing all 3 tutorial levels',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    await tester.tap(find.text('Tutorials'));
    await tester.pumpAndSettle();

    expect(find.byType(TutorialScreen), findsOneWidget);
    for (final level in tutorialLevels) {
      expect(find.text(level.name), findsOneWidget);
    }
  });

  testWidgets('unbuilt entries (e.g. Editor, once signed in) open a Coming '
      'soon placeholder', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    // Not signed in — gated behind Sign in with Apple, same as Leaderboard.
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(ComingSoonScreen), findsNothing);
  });

  testWidgets(
      'Leaderboard and Editor require Sign in with Apple before opening',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(ComingSoonScreen), findsNothing);
  });
}
