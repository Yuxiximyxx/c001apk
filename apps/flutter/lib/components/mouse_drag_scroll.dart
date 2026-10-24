import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Enables mouse dragging within a horizontal control without changing the
/// surrounding page's scrolling or text selection.
class MouseDragScroll extends StatelessWidget {
  const MouseDragScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: behavior.copyWith(
        dragDevices: {...behavior.dragDevices, PointerDeviceKind.mouse},
      ),
      child: child,
    );
  }
}
