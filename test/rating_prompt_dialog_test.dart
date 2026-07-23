import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/screens/home_screen.dart';

import 'fake_secure_storage.dart';

void main() {
  testWidgets(
      'shows the rating prompt once 5 puzzles are completed, and "Not now" dismisses it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeStorage = installFakeSecureStorage();
    await fakeStorage.write(
      key: 'completed_level_ids',
      value: jsonEncode(['a', 'b', 'c', 'd', 'e']),
      options: const {},
    );

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // Loading the catalog does real dart:io file I/O (rootBundle.loadString
    // on a real asset), which never completes under testWidgets' FakeAsync
    // zone via plain pump(); runAsync briefly escapes to real time so it can.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.pump(); // let the async shouldShow() check resolve and show it

    expect(find.text('Enjoying Robozzle?'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.text('Enjoying Robozzle?'), findsNothing);
  });
}
