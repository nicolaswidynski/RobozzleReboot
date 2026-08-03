import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/home_screen.dart';

import 'fake_secure_storage.dart';

void main() {
  testWidgets(
      'Community Puzzles (excludeAuthors) hides puzzles by the Campaign '
      'authors instead of also showing them', (tester) async {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(
          excludeAuthors: {'igoro', 'blake', 'markbyers', 'wido'},
        ),
      ),
    );

    // Loading the catalog does real dart:io file I/O (rootBundle.loadString
    // on a real asset), which never completes under testWidgets' FakeAsync
    // zone via plain pump(); runAsync briefly escapes to real time so it can.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    // 908 bundled puzzles total, minus 33 (igoro) + 1 (blake) + 65
    // (markbyers) + 0 (wido, server-published, not in the bundled asset)
    // = 809, verified directly against the asset.
    expect(find.text('809 puzzles'), findsOneWidget);
  });
}
