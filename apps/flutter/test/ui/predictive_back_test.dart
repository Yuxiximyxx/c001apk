import 'package:c001apk_flutter/router/app_pages.dart';
import 'package:c001apk_flutter/router/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  tearDown(Get.reset);

  Future<void> backEvent(WidgetTester tester, String method,
      {double progress = 0, int edge = 0, double y = 300}) async {
    final width = tester.view.physicalSize.width;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, {
        'touchOffset': <double>[
          width * (edge == 0 ? progress : 1 - progress),
          y,
        ],
        'progress': progress,
        'swipeEdge': edge,
      })),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> openPage(WidgetTester tester,
      {bool blocked = false,
      Widget? content,
      TargetPlatform platform = TargetPlatform.android}) async {
    final route = AppPages.getPages.firstWhere((page) => page.name == '/about');
    await tester.pumpWidget(GetMaterialApp(
      customTransition: AppPageTransition(),
      theme: ThemeData(platform: platform),
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const Scaffold(body: Text('上一页'))),
        route.copy(
          curve: Curves.easeOutQuad,
          page: () => PopScope(
            canPop: !blocked,
            child: content ?? const Scaffold(body: Text('当前页')),
          ),
        ),
      ],
    ));
    Get.toNamed('/about');
    await tester.pumpAndSettle();
  }

  double pageOpacity(WidgetTester tester) {
    final fades = tester.widgetList<FadeTransition>(find.ancestor(
      of: find.text('当前页'),
      matching: find.byType(FadeTransition),
    ));
    final opacities = tester.widgetList<Opacity>(
        find.ancestor(of: find.text('当前页'), matching: find.byType(Opacity)));
    return opacities.fold(
        fades.fold<double>(1, (value, fade) => value * fade.opacity.value),
        (value, opacity) => value * opacity.opacity);
  }

  Rect pageBounds(WidgetTester tester) => tester.getRect(find
      .ancestor(of: find.text('当前页'), matching: find.byType(Scaffold))
      .first);

  testWidgets('predictive back reveals the previous surface immediately',
      (tester) async {
    await openPage(tester);
    await backEvent(tester, 'startBackGesture');
    await backEvent(tester, 'updateBackGestureProgress', progress: 0.25);
    final fades = tester.widgetList<FadeTransition>(find.ancestor(
        of: find.text('上一页'), matching: find.byType(FadeTransition)));
    expect(fades.fold<double>(1, (value, fade) => value * fade.opacity.value),
        greaterThan(0.99));
    await backEvent(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ordinary Android navigation moves forward while fading in',
      (tester) async {
    await openPage(tester);
    Get.back();
    await tester.pumpAndSettle();
    Get.toNamed('/about');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(pageBounds(tester).left, greaterThan(0));
    await tester.pumpAndSettle();
    expect(pageBounds(tester).left, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion keeps predictive navigation without transforms',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await openPage(tester);
    final original = pageBounds(tester);
    await backEvent(tester, 'startBackGesture', y: 200);
    await backEvent(tester, 'updateBackGestureProgress', progress: 0.5, y: 450);
    expect(pageBounds(tester), original);
    expect(pageOpacity(tester), 1);
    await backEvent(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('上一页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final edge in [0, 1]) {
    testWidgets(
        'back from edge $edge shrinks and moves the page with the swipe',
        (tester) async {
      await openPage(tester);
      final original = pageBounds(tester);
      await backEvent(tester, 'startBackGesture', edge: edge);
      await backEvent(tester, 'updateBackGestureProgress',
          progress: 0.25, edge: edge);
      final early = pageBounds(tester);
      expect(early.width, lessThan(original.width));
      expect(early.height, lessThan(original.height));
      expect(
          early.center.dx,
          edge == 0
              ? greaterThan(original.center.dx)
              : lessThan(original.center.dx));

      await backEvent(tester, 'updateBackGestureProgress',
          progress: 0.65, edge: edge);
      final later = pageBounds(tester);
      expect(later.width, lessThan(early.width));
      expect((later.center.dx - original.center.dx).abs(),
          greaterThan((early.center.dx - original.center.dx).abs()));
      expect(later.center.dy, closeTo(original.center.dy, 0.01));
      expect(pageOpacity(tester), 1);

      await backEvent(tester, 'updateBackGestureProgress',
          progress: 0.25, edge: edge);
      expect(pageBounds(tester).width, closeTo(early.width, 0.01));
      expect(pageBounds(tester).center.dx, closeTo(early.center.dx, 0.01));
      await backEvent(tester, 'cancelBackGesture', edge: edge);
      await tester.pump(const Duration(milliseconds: 50));
      expect(pageBounds(tester).width, greaterThan(early.width));
      await tester.pumpAndSettle();
      expect(pageBounds(tester), original);
      expect(pageOpacity(tester), 1);

      // A later button press must not reuse the cancelled gesture's transform.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Button navigation now uses Android's forward fade. It keeps the
      // surface at full size and never reuses the previous swipe direction.
      expect(pageBounds(tester).size, original.size);
      expect(pageBounds(tester).left, greaterThanOrEqualTo(original.left));
      await tester.pumpAndSettle();
      expect(find.text('上一页'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'official preview from edge $edge keeps the current page opaque',
        (tester) async {
      await openPage(tester);
      await backEvent(tester, 'startBackGesture', edge: edge);
      await backEvent(tester, 'updateBackGestureProgress',
          progress: 0.1, edge: edge);
      final earlyOpacity = pageOpacity(tester);
      expect(earlyOpacity, 1);
      await backEvent(tester, 'updateBackGestureProgress',
          progress: 0.25, edge: edge);
      expect(pageOpacity(tester), 1);
      expect(find.text('上一页'), findsOneWidget);
      await backEvent(tester, 'updateBackGestureProgress',
          progress: 0.65, edge: edge);
      expect(pageOpacity(tester), 1);
      await backEvent(tester, 'updateBackGestureProgress',
          progress: 0.1, edge: edge);
      expect(pageOpacity(tester), closeTo(earlyOpacity, 0.01));
      await backEvent(tester, 'cancelBackGesture', edge: edge);
      await tester.pump(const Duration(milliseconds: 50));
      expect(pageOpacity(tester), 1);
      await tester.pumpAndSettle();
      expect(pageOpacity(tester), 1);
      expect(Get.currentRoute, '/about');
      expect(Get.key.currentState!.userGestureInProgress, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('committing predictive back pops exactly the current route',
      (tester) async {
    await openPage(tester);
    await backEvent(tester, 'startBackGesture');
    await backEvent(tester, 'updateBackGestureProgress', progress: 0.5);
    final beforeCommit = pageBounds(tester);
    expect(beforeCommit.width, lessThan(800));
    await backEvent(tester, 'commitBackGesture');
    expect(pageBounds(tester).width, closeTo(beforeCommit.width, 0.01));
    await tester.pumpAndSettle();
    expect(find.text('当前页'), findsNothing);
    expect(find.text('上一页'), findsOneWidget);
    expect(Get.key.currentState!.canPop(), isFalse);
    expect(Get.key.currentState!.userGestureInProgress, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('predictive back preserves an entered draft across cancellation',
      (tester) async {
    await openPage(tester,
        content: const Scaffold(
          body: Column(children: [Text('当前页'), TextField()]),
        ));
    await tester.enterText(find.byType(TextField), '尚未提交的本地草稿');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await backEvent(tester, 'startBackGesture');
    expect(find.text('尚未提交的本地草稿'), findsOneWidget);
    await backEvent(tester, 'updateBackGestureProgress', progress: 0.25);
    expect(find.text('尚未提交的本地草稿'), findsOneWidget);
    await backEvent(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('尚未提交的本地草稿'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('上一页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final finish in ['commitBackGesture', 'cancelBackGesture']) {
    testWidgets('$finish preserves a route pushed during the gesture',
        (tester) async {
      await openPage(tester);
      await backEvent(tester, 'startBackGesture');
      await backEvent(tester, 'updateBackGestureProgress', progress: 0.5);
      Get.to(() => const Scaffold(body: Text('新打开的页面')));
      await tester.pumpAndSettle();
      await backEvent(tester, finish);
      await tester.pumpAndSettle();
      expect(find.text('新打开的页面'), findsOneWidget);
      expect(Get.key.currentState!.userGestureInProgress, isFalse);
      Get.back();
      await tester.pumpAndSettle();
      expect(find.text('当前页'), findsOneWidget);
      expect(pageOpacity(tester), 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('predictive back respects a route that blocks popping',
      (tester) async {
    await openPage(tester, blocked: true);
    await backEvent(tester, 'startBackGesture');
    await backEvent(tester, 'updateBackGestureProgress', progress: 0.5);
    expect(pageOpacity(tester), 1);
    await backEvent(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(Get.currentRoute, '/about');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final finish in ['cancelBackGesture', 'commitBackGesture']) {
    testWidgets(
        'changing PopScope during a gesture restores the route ($finish)',
        (tester) async {
      final canPop = ValueNotifier(true);
      await openPage(tester,
          content: ValueListenableBuilder<bool>(
            valueListenable: canPop,
            builder: (_, value, child) =>
                PopScope(canPop: value, child: child!),
            child: const Scaffold(body: Text('当前页')),
          ));
      await backEvent(tester, 'startBackGesture');
      await backEvent(tester, 'updateBackGestureProgress', progress: 0.5);
      canPop.value = false;
      await tester.pump();
      await backEvent(tester, finish);
      await tester.pumpAndSettle();
      expect(find.text('当前页'), findsOneWidget);
      expect(pageOpacity(tester), 1);
      expect(pageBounds(tester).width, 800);
      expect(Get.key.currentState!.userGestureInProgress, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      canPop.dispose();
    });
  }

  testWidgets(
      'enabling reduced motion during a gesture keeps cancellation connected',
      (tester) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await openPage(tester,
        content:
            const Scaffold(body: Column(children: [Text('当前页'), TextField()])));
    await tester.enterText(find.byType(TextField), '保留无障碍切换前的草稿');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await backEvent(tester, 'startBackGesture');
    await backEvent(tester, 'updateBackGestureProgress', progress: 0.5);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    await backEvent(tester, 'updateBackGestureProgress', progress: 0.7, y: 500);
    expect(pageBounds(tester).width, 800);
    expect(pageBounds(tester).top, 0);
    expect(find.text('保留无障碍切换前的草稿'), findsOneWidget);
    await backEvent(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(Get.key.currentState!.userGestureInProgress, isFalse);
    expect(pageBounds(tester).width, 800);
    expect(pageOpacity(tester), 1);
    expect(find.text('保留无障碍切换前的草稿'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('iOS back keeps the native transition linear during a gesture',
      (tester) async {
    await openPage(tester, platform: TargetPlatform.iOS);
    final route = ModalRoute.of(tester.element(find.text('当前页')))! as PageRoute;
    route.handleStartBackGesture(progress: 0.5);
    await tester.pump();
    expect(tester.getTopLeft(find.text('当前页')).dx, closeTo(400, 1));
    route.handleCancelBackGesture();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
