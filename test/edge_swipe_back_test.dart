import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/widgets/edge_swipe_back.dart';

void main() {
  Future<GlobalKey<NavigatorState>> pumpTwoRoutes(WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) =>
          EdgeSwipeBack(navigatorKey: navigatorKey, child: child!),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));
    navigatorKey.currentState!.push(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Center(child: Text('Second'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    return navigatorKey;
  }

  testWidgets(
      'a fast rightward swipe starting inside the edge zone pops the '
      'current route', (tester) async {
    await pumpTwoRoutes(tester);

    await tester.flingFrom(const Offset(10, 300), const Offset(300, 0), 800);
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Second'), findsNothing);
  });

  testWidgets(
      'a fast rightward swipe starting outside the edge zone does nothing',
      (tester) async {
    await pumpTwoRoutes(tester);

    await tester.flingFrom(
        const Offset(EdgeSwipeBack.edgeWidth + 40, 300), const Offset(300, 0), 800);
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('a slow drag inside the edge zone (below the velocity threshold) does nothing',
      (tester) async {
    await pumpTwoRoutes(tester);

    final gesture = await tester.startGesture(const Offset(10, 300));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('does nothing when there is no previous route to pop back to',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) =>
          EdgeSwipeBack(navigatorKey: navigatorKey, child: child!),
      home: const Scaffold(body: Center(child: Text('Home'))),
    ));

    await tester.flingFrom(const Offset(10, 300), const Offset(300, 0), 800);
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });
}
