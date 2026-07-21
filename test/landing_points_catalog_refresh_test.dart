import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/catalog_metadata_store.dart';
import 'package:robozzle_reboot/data/catalog_refresher.dart';
import 'package:robozzle_reboot/screens/landing_screen.dart';

void main() {
  testWidgets(
      'recomputes points as soon as the catalog refreshes — e.g. a '
      'completed puzzle gets re-rated — without navigating away and back',
      (tester) async {
    // "catalog-195" ("Another speed control") has difficulty 3 in the
    // bundled catalog asset -> (1 + 3)^2 = 16 points.
    SharedPreferences.setMockInitialValues({
      'completed_level_ids': ['catalog-195'],
    });

    await tester.pumpWidget(const MaterialApp(home: LandingScreen()));

    // Computing points does real dart:io file I/O (rootBundle.loadString on
    // a real asset), which never completes under testWidgets' FakeAsync
    // zone via plain pump(); runAsync briefly escapes to real time so it can.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('16'), findsOneWidget);

    // Simulate a background catalog refresh (daily or pull-to-refresh)
    // re-rating "catalog-195" down to difficulty 1 -> (1 + 1)^2 = 4 points.
    // This is exactly what CatalogRefresher does before notifying listeners
    // once the network call succeeds, minus the network call itself.
    await CatalogMetadataStore().saveOverrides({
      'catalog-195': CatalogMetadataOverride(difficulty: 1),
    });
    CatalogRefresher.instance.notifyListeners();

    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    // The FutureBuilder needs one pump to notice _pointsFuture changed
    // (dropping to its loading state) and a second to show the resolved
    // value.
    await tester.pump();
    await tester.pump();

    expect(find.text('4'), findsOneWidget);
    expect(find.text('16'), findsNothing);
  });
}
