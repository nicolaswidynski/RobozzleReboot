import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/tutorial_levels.dart';
import 'package:robozzle_reboot/screens/about_screen.dart';
import 'package:robozzle_reboot/screens/auth/sign_in_screen.dart';
import 'package:robozzle_reboot/screens/home_screen.dart';
import 'package:robozzle_reboot/screens/landing_screen.dart';
import 'package:robozzle_reboot/screens/tutorial_screen.dart';

import 'fake_secure_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();
  });

  testWidgets('shows all 6 menu entries', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    for (final label in [
      'Tutorials',
      'Campaign',
      'Community Puzzles',
      'Editor',
      'Leaderboard',
      'About',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('About opens AboutScreen with the Robozzle attribution',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(
      find.textContaining('Igor Ostrovsky', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('permanent ban'), findsOneWidget);
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

  testWidgets('Leaderboard requires Sign in with Apple before opening',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('Editor requires Sign in with Apple before opening',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });
}
