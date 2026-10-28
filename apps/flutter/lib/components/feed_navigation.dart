import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FeedNavigation extends InheritedWidget {
  const FeedNavigation(
      {super.key,
      required this.openFeed,
      required this.selectedId,
      this.paneCapable = false,
      this.compact = false,
      required super.child});

  final bool Function(String) openFeed;
  final String? selectedId;
  final bool compact;

  static bool compactOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeedNavigation>()?.compact ??
      false;

  /// True when [openFeed] can actually present the feed beside the list
  /// (split reading pane). When false, [open] falls back to pushing a route,
  /// so tappable sources may use a source-anchored container transition
  /// instead of the plain GetX navigation.
  final bool paneCapable;

  static String? selectedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeedNavigation>()?.selectedId;

  static void open(BuildContext context, String id) {
    final scope = context.getInheritedWidgetOfExactType<FeedNavigation>();
    if (scope?.openFeed(id) != true) Get.toNamed('/feed/$id');
  }

  @override
  bool updateShouldNotify(FeedNavigation oldWidget) =>
      oldWidget.selectedId != selectedId ||
          oldWidget.paneCapable != paneCapable ||
          oldWidget.compact != compact;
}
