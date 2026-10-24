import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:get/get.dart';

/// GetX's native transition uses a fixed PageTransitionsTheme. Delegate to our
/// Android builder explicitly, using the route's uncurved animations so the
/// SDK owns predictive back geometry and its cancel/commit phases.
class AppPageTransition extends CustomTransition {
  @override
  Widget buildTransition(
    BuildContext context,
    Curve? curve,
    Alignment? alignment,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final route = ModalRoute.of(context)! as PageRoute;
    if (Theme.of(context).platform == TargetPlatform.android) {
      return const AppPredictiveBackPageTransitionsBuilder().buildTransitions(
        route,
        context,
        route.animation!,
        route.secondaryAnimation!,
        child,
      );
    }
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final builder = switch (Theme.of(context).platform) {
      TargetPlatform.iOS => const CupertinoPageTransitionsBuilder(),
      _ => const FadeForwardsPageTransitionsBuilder(),
    };
    return builder.buildTransitions(
      route,
      context,
      route.animation!,
      secondaryAnimation,
      child,
    );
  }
}

class AppPredictiveBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPredictiveBackPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _AppPredictiveBack(
      route: route,
      child: child,
    );
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 450);
}

class _AppPredictiveBack extends StatefulWidget {
  const _AppPredictiveBack({required this.route, required this.child});

  final PageRoute route;
  final Widget child;

  @override
  State<_AppPredictiveBack> createState() => _AppPredictiveBackState();
}

class _AppPredictiveBackState extends State<_AppPredictiveBack> {
  bool _restoreWhenCurrent = false;
  late final _guardedRoute = _GuardedBackRoute(widget.route);
  final _pageKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // A newly pushed route can cover a half-completed gesture. Flutter skips
    // animation restoration while that route is not current. Resume its cancel
    // animation once it is visible again, without touching the new top route.
    final isCurrent = ModalRoute.isCurrentOf(context) ?? widget.route.isCurrent;
    if (!isCurrent &&
        widget.route.navigator!.userGestureInProgress &&
        !widget.route.animation!.isCompleted &&
        widget.route.animation!.status != AnimationStatus.reverse) {
      _restoreWhenCurrent = true;
    }
    if (_restoreWhenCurrent && isCurrent) {
      _restoreWhenCurrent = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final route = widget.route;
        if (mounted &&
            route.isCurrent &&
            !route.popGestureInProgress &&
            !route.animation!.isCompleted) {
          route.handleStartBackGesture(progress: route.animation!.value);
          route.handleCancelBackGesture();
        }
      });
    }
    // Keep the SDK detector mounted when PopScope/accessibility changes during
    // a gesture. The adapter checks disposition again when a gesture commits.
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final page = KeyedSubtree(key: _pageKey, child: widget.child);
    return Stack(fit: StackFit.expand, children: [
      ExcludeSemantics(
        excluding: reducedMotion,
        child: const PredictiveBackPageTransitionsBuilder().buildTransitions(
          _guardedRoute,
          context,
          widget.route.animation!,
          widget.route.secondaryAnimation!,
          reducedMotion ? const SizedBox.shrink() : page,
        ),
      ),
      // The SDK also follows vertical finger displacement independently of
      // animation progress. Keep its gesture detector, but put the single page
      // outside its visual transform when motion is disabled. The key retains
      // page state if accessibility settings change during a gesture.
      if (reducedMotion) page,
    ]);
  }
}

/// A non-installed view of a GetX route for the SDK gesture detector. GetX 4's
/// popGestureEnabled predates PopScope; delegate navigation to the real route
/// while checking the current disposition at both gesture start and commit.
class _GuardedBackRoute extends PageRoute<void> {
  _GuardedBackRoute(this.route);
  final PageRoute route;

  @override
  bool get isCurrent => route.isCurrent;
  @override
  NavigatorState? get navigator => route.navigator;
  @override
  Animation<double>? get animation => route.animation;
  @override
  Animation<double>? get secondaryAnimation => route.secondaryAnimation;
  @override
  bool get popGestureEnabled =>
      route.popGestureEnabled &&
      route.popDisposition == RoutePopDisposition.pop;
  @override
  bool get popGestureInProgress => route.popGestureInProgress;
  @override
  void handleStartBackGesture({double progress = 0}) =>
      route.handleStartBackGesture(progress: progress);
  @override
  void handleUpdateBackGestureProgress({required double progress}) =>
      route.handleUpdateBackGestureProgress(progress: progress);
  @override
  void handleCancelBackGesture() => route.handleCancelBackGesture();
  @override
  void handleCommitBackGesture() {
    if (route.popDisposition == RoutePopDisposition.pop && route.isCurrent) {
      route.handleCommitBackGesture();
    } else {
      route.handleCancelBackGesture();
    }
  }

  @override
  Color? get barrierColor => route.barrierColor;
  @override
  String? get barrierLabel => route.barrierLabel;
  @override
  bool get maintainState => route.maintainState;
  @override
  Duration get transitionDuration => route.transitionDuration;
  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      const SizedBox.shrink();
}
