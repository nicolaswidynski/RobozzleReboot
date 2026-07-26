import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/landing_screen.dart';

import 'fake_secure_storage.dart';

void main() {
  testWidgets(
      'shows the pseudonym next to the points badge, top right, when known',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_provider': 'apple',
      'apple_user_id': 'apple-test-user',
      'apple_pseudonym_set': true,
      'apple_pseudonym': 'RoboFan',
    });
    installFakeSecureStorage();

    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    // Loading the pseudonym/catalog does real dart:io file I/O (rootBundle
    // .loadString on a real asset for the points badge), which never
    // completes under testWidgets' FakeAsync zone via plain pump(); runAsync
    // briefly escapes to real time so it can.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('RoboFan'), findsOneWidget);

    // Both the pseudonym and the points badge sit in the same trailing
    // group, to the right of the "Robozzle" title.
    final titleX = tester.getTopLeft(find.text('Robozzle')).dx;
    final pseudonymX = tester.getTopLeft(find.text('RoboFan')).dx;
    expect(pseudonymX, greaterThan(titleX));
  });
}
