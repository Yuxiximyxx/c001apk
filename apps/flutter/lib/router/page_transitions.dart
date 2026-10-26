import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:get/get.dart';
import '../components/app_anim.dart';

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

/// Minimum scale a page reaches in the card transition, and the deepest
/// dim applied to a covered page.
///
/// Both mirror the SharedNav `DefaultPageEffects` geometry that LumaGA
/// ships (and the user approved there): the shared threshold
/// `NavigationController.DEFAULT_SHARED_MAX_PRECENT` is 0.875, and the
/// covered page's mask goes from transparent to black at 0.25 alpha
/// (`defaultMask`). SharedNav also blurs the covered page up to 25dp;
/// this port deliberately substitutes dim for blur — animating a filter
/// sigma per frame is a known jank source (see [AppAnim]).
const double kCardPageMinScale = 0.875;
const double kCardPageMaxDim = 0.25;

/// One frame of the card-style page geometry, as a pure function of the
/// route's primary ([animationValue]) and secondary ([secondaryValue])
/// progress. Push and pop pass through the same frames in opposite
/// orders, so pops mirror pushes exactly.
///
/// Foreground (this page entering/leaving), following LumaGA's
/// `CardPageEffects` variant of the SharedNav stock effect: the scale is
/// floored at [kCardPageMinScale] around the screen centre, the progress
/// range below that floor is traded for a fade on top of the stock
/// 0.75→1 alpha ramp, and the corner radius interpolates from 2.25× the
/// screen corner down to the screen corner itself (the value SharedNav
/// reads from the device via `ScreenCornerHelper`).
///
/// Background (this page being covered/uncovered): scale down to
/// [kCardPageMinScale], dim to [kCardPageMaxDim], corner up to the
/// screen corner. (SharedNav keeps the covered page's corner flat; the
/// radius here is part of this port's card treatment.)
class CardPageFrame {
  const CardPageFrame({
    required this.scale,
    required this.opacity,
    required this.cornerRadius,
    required this.dim,
    required this.shadowOpacity,
  });

  final double scale;
  final double opacity;
  final double cornerRadius;

  /// Black overlay alpha painted over the page while it is covered.
  final double dim;

  /// Opacity of the soft shadow that lifts the entering card off the
  /// covered page beneath it.
  final double shadowOpacity;

  bool get isIdentity =>
      scale == 1 && opacity == 1 && cornerRadius == 0 && dim == 0;
}

CardPageFrame cardPageFrame({
  required double animationValue,
  required double secondaryValue,
  required double screenCorner,
}) {
  final a = animationValue.clamp(0.0, 1.0);
  final s = secondaryValue.clamp(0.0, 1.0);

  // Foreground, driven by the page's own animation.
  final t = AppAnim.sharedCurve.transform(a);
  final fgScale = math.max(t, kCardPageMinScale);
  final fgAlpha =
      (0.75 + 0.25 * t) * (t < kCardPageMinScale ? t / kCardPageMinScale : 1.0);
  final fgRadius = screenCorner * (2.25 - 1.25 * t);

  // Background, driven by the covering route's progress. The corner
  // needs no separate term: a covered page sits at its foreground rest
  // radius, which is already the screen corner.
  final u = AppAnim.enterCurve.transform(s);
  final bgScale = 1 - (1 - kCardPageMinScale) * u;

  final lift = ((1 - fgScale) / (1 - kCardPageMinScale)).clamp(0.0, 1.0);
  return CardPageFrame(
    scale: fgScale * bgScale,
    opacity: fgAlpha,
    cornerRadius: fgRadius,
    dim: kCardPageMaxDim * u,
    shadowOpacity: 0.3 * lift * fgAlpha,
  );
}

/// The largest display corner radius, i.e. the "screen corner" the card
/// geometry is expressed in. Zero when the platform does not report
/// display corner radii (square screens, older Android), which reduces
/// the radius terms to nothing.
double screenCornerRadiusOf(BuildContext context) {
  final radii = MediaQuery.displayCornerRadiiOf(context);
  if (radii == null) return 0;
  return math.max(
    math.max(radii.topLeft.x, radii.topRight.x),
    math.max(radii.bottomLeft.x, radii.bottomRight.x),
  );
}

/// Applies [cardPageFrame] to [child] for non-gesture navigation. Only
/// the wrappers a frame actually needs are built, and a settled,
/// uncovered page is returned unwrapped so steady-state pages (long
/// lists in particular) pay no per-frame layer cost.
class CardPageTransition extends StatelessWidget {
  const CardPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screenCorner = screenCornerRadiusOf(context);
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        if (animation.value == 1 && secondaryAnimation.value == 0) {
          return child!;
        }
        final frame = cardPageFrame(
          animationValue: animation.value,
          secondaryValue: secondaryAnimation.value,
          screenCorner: screenCorner,
        );
        if (frame.isIdentity) return child!;
        Widget page = child!;
        if (frame.dim > 0) {
          page = Stack(
            children: [
              page,
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Color.fromRGBO(0, 0, 0, frame.dim),
                  ),
                ),
              ),
            ],
          );
        }
        if (frame.cornerRadius > 0) {
          page = ClipRRect(
            borderRadius: BorderRadius.circular(frame.cornerRadius),
            child: page,
          );
        }
        if (frame.shadowOpacity > 0) {
          page = DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(frame.cornerRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: frame.shadowOpacity),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: page,
          );
        }
        page = Transform.scale(scale: frame.scale, child: page);
        if (frame.opacity < 1) {
          page = Opacity(opacity: frame.opacity, child: page);
        }
        return page;
      },
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
  Duration get transitionDuration => AppAnim.page;
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
  ValueNotifier<bool>? _gestureNotifier;

  /// The page renders in one of two slots: inside the SDK predictive
  /// back transition while a back gesture is in progress, or in the
  /// card-geometry layer ([CardPageTransition]) for ordinary navigation.
  /// Which slot is active depends on [PageRoute.popGestureInProgress],
  /// whose flips do not always come with an animation notification (a
  /// gesture starting on a settled route leaves the value at 1), so
  /// listen to the navigator's notifier directly to switch slots on the
  /// exact frame the flag changes.
  void _syncGestureListener() {
    final notifier = widget.route.navigator?.userGestureInProgressNotifier;
    if (notifier == _gestureNotifier) return;
    _gestureNotifier?.removeListener(_handleGestureToggle);
    _gestureNotifier = notifier;
    _gestureNotifier?.addListener(_handleGestureToggle);
  }

  void _handleGestureToggle() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncGestureListener();
  }

  @override
  void dispose() {
    _gestureNotifier?.removeListener(_handleGestureToggle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncGestureListener();
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
    // While a back gesture is in progress the SDK owns the page's visuals
    // exactly as before. Otherwise the SDK builder stays mounted (its
    // gesture detector must be in the tree to receive system back events)
    // but renders a shrink, and the page is driven by the card geometry
    // instead of the SDK's FadeForwards fallback. The key retains page
    // state when the page moves between slots, the same reparenting the
    // reduced-motion path below already relies on.
    final inGesture = widget.route.popGestureInProgress;
    final sdkOwnsPage = inGesture && !reducedMotion;
    return Stack(fit: StackFit.expand, children: [
      ExcludeSemantics(
        excluding: reducedMotion,
        child: const PredictiveBackPageTransitionsBuilder().buildTransitions(
          _guardedRoute,
          context,
          widget.route.animation!,
          widget.route.secondaryAnimation!,
          sdkOwnsPage ? page : const SizedBox.shrink(),
        ),
      ),
      if (!reducedMotion && !inGesture)
        CardPageTransition(
          animation: widget.route.animation!,
          secondaryAnimation: widget.route.secondaryAnimation!,
          child: page,
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
