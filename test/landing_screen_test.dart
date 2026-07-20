import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/coming_soon_screen.dart';
import 'package:robozzle_reboot/screens/home_screen.dart';
import 'package:robozzle_reboot/screens/landing_screen.dart';

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

  testWidgets('unbuilt entries (e.g. Tutorials) open a Coming soon placeholder',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    await tester.tap(find.text('Tutorials'));
    await tester.pumpAndSettle();

    expect(find.byType(ComingSoonScreen), findsOneWidget);
    expect(find.text('Tutorials is coming soon'), findsOneWidget);
  });
}
