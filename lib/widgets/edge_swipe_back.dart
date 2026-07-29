import 'package:flutter/material.dart';

/// A wider, app-controlled substitute for iOS's built-in edge-swipe-to-go-
/// back gesture. That built-in gesture only recognizes a swipe starting
/// within a ~20-logical-pixel sliver of the screen's left edge — thin
/// enough that it's easy to miss, and it competes with any of this app's
/// own horizontal-drag widgets that happen to sit that close to the edge
/// (which several do: the palette, the control bar). Wrapping the whole
/// app in this instead gives a wider, dedicated hit zone
/// ([edgeWidth]) that only ever does one thing — pop the current route —
/// so it can't be shadowed by other gestures the way the native one is.
///
/// Screens are expected to keep their own interactive content clear of
/// [edgeWidth] from the left edge (see the screens' outer padding) so
/// there's nothing there to compete with.
///
/// Sits above the [MaterialApp]'s `builder`, which is above the Navigator
/// it needs to pop — [Navigator.of]/[Navigator.maybePop] can't reach a
/// Navigator from a context that isn't one of its descendants, so this
/// needs the app's own [navigatorKey] instead of relying on its `context`.
class EdgeSwipeBack extends StatelessWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  static const double edgeWidth = 32;
  static const double _minVelocity = 250;

  const EdgeSwipeBack({super.key, required this.child, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: edgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity > _minVelocity) {
                navigatorKey.currentState?.maybePop();
              }
            },
          ),
        ),
      ],
    );
  }
}
