import 'package:c001apk_flutter/router/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Geometry contract of the card-style page transition that replaced the
/// SDK's FadeForwards fallback for ordinary Android navigation. The
/// values mirror the SharedNav Default page effects as customised by
/// LumaGA's CardPageEffects: foreground scale floored at 0.875 with the
/// sub-floor range traded for a fade over the stock 0.75→1 alpha ramp,
/// corner from 2.25× the screen corner down to the screen corner, and a
/// covered page scaled to 0.875 with a black dim up to 0.25.
void main() {
  group('cardPageFrame foreground', () {
    test('starts as a transparent card at the minimum scale', () {
      final frame = cardPageFrame(
        animationValue: 0,
        secondaryValue: 0,
        screenCorner: 20,
      );
      expect(frame.scale, 0.875);
      expect(frame.opacity, 0);
      expect(frame.cornerRadius, 45);
      expect(frame.dim, 0);
      expect(frame.shadowOpacity, 0);
    });

    test('settles to the full page at the screen corner', () {
      final frame = cardPageFrame(
        animationValue: 1,
        secondaryValue: 0,
        screenCorner: 20,
      );
      expect(frame.scale, 1);
      expect(frame.opacity, 1);
      expect(frame.cornerRadius, 20);
      expect(frame.dim, 0);
      expect(frame.shadowOpacity, 0);
    });

    test('below the floor the scale is pinned and progress becomes fade',
        () {
      // easeOutQuart(0.2) ≈ 0.59 < 0.875, so the scale must stay floored
      // while the alpha carries the stock ramp times the tail fraction.
      final t = Curves.easeOutQuart.transform(0.2);
      expect(t, lessThan(kCardPageMinScale));
      final frame = cardPageFrame(
        animationValue: 0.2,
        secondaryValue: 0,
        screenCorner: 20,
      );
      expect(frame.scale, kCardPageMinScale);
      expect(
        frame.opacity,
        closeTo((0.75 + 0.25 * t) * (t / kCardPageMinScale), 1e-9),
      );
      expect(
        frame.cornerRadius,
        closeTo(20 * (2.25 - 1.25 * t), 1e-9),
      );
    });

    test('above the floor the scale follows the curved progress', () {
      final t = Curves.easeOutQuart.transform(0.5);
      expect(t, greaterThan(kCardPageMinScale));
      final frame = cardPageFrame(
        animationValue: 0.5,
        secondaryValue: 0,
        screenCorner: 20,
      );
      expect(frame.scale, closeTo(t, 1e-9));
      expect(frame.opacity, closeTo(0.75 + 0.25 * t, 1e-9));
    });
  });

  group('cardPageFrame background', () {
    test('a fully covered page is scaled down and dimmed', () {
      final frame = cardPageFrame(
        animationValue: 1,
        secondaryValue: 1,
        screenCorner: 20,
      );
      expect(frame.scale, kCardPageMinScale);
      expect(frame.opacity, 1);
      expect(frame.dim, kCardPageMaxDim);
      expect(frame.cornerRadius, 20);
    });

    test('partial cover interpolates scale and dim', () {
      final u = Curves.easeOutCubic.transform(0.5);
      final frame = cardPageFrame(
        animationValue: 1,
        secondaryValue: 0.5,
        screenCorner: 20,
      );
      expect(frame.scale, closeTo(1 - 0.125 * u, 1e-9));
      expect(frame.dim, closeTo(kCardPageMaxDim * u, 1e-9));
      // A covered page rests at its foreground end radius: the screen
      // corner, independent of how far the cover has progressed.
      expect(frame.cornerRadius, 20);
    });

    test('foreground and background compose multiplicatively', () {
      final frame = cardPageFrame(
        animationValue: 0.5,
        secondaryValue: 1,
        screenCorner: 0,
      );
      final fg = cardPageFrame(
        animationValue: 0.5,
        secondaryValue: 0,
        screenCorner: 0,
      );
      expect(frame.scale, closeTo(fg.scale * kCardPageMinScale, 1e-9));
      expect(frame.opacity, fg.opacity);
      expect(frame.dim, kCardPageMaxDim);
    });
  });

  group('card page transition widgets', () {
    tearDown(Get.reset);

    Future<void> openApp(WidgetTester tester) async {
      await tester.pumpWidget(GetMaterialApp(
        customTransition: AppPageTransition(),
        theme: ThemeData(platform: TargetPlatform.android),
        initialRoute: '/',
        getPages: [
          GetPage(
              name: '/', page: () => const Scaffold(body: Text('上一页'))),
          GetPage(
              name: '/about',
              page: () => const Scaffold(body: Text('当前页'))),
        ],
      ));
      await tester.pumpAndSettle();
    }

    Rect boundsOf(WidgetTester tester, String text) => tester.getRect(find
        .ancestor(of: find.text(text), matching: find.byType(Scaffold))
        .first);

    testWidgets('push grows the new page as a centred card over a '
        'shrinking covered page', (tester) async {
      await openApp(tester);
      Get.toNamed('/about');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final current = boundsOf(tester, '当前页');
      expect(current.width, lessThan(800));
      expect(current.width, greaterThan(0));
      expect(current.center.dx, closeTo(400, 0.01));
      expect(current.center.dy, closeTo(300, 0.01));

      final covered = boundsOf(tester, '上一页');
      expect(covered.width, lessThan(800));
      expect(covered.center.dx, closeTo(400, 0.01));

      await tester.pumpAndSettle();
      // A settled page is returned unwrapped: no transition layers are
      // left around it to tax steady-state scrolling.
      expect(boundsOf(tester, '当前页'), const Rect.fromLTWH(0, 0, 800, 600));
      expect(
        find.ancestor(
            of: find.text('当前页'), matching: find.byType(Transform)),
        findsNothing,
      );
      expect(
        find.ancestor(
            of: find.text('当前页'), matching: find.byType(ClipRRect)),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('programmatic pop mirrors the push around the centre',
        (tester) async {
      await openApp(tester);
      Get.toNamed('/about');
      await tester.pumpAndSettle();

      Get.back();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final exiting = boundsOf(tester, '当前页');
      expect(exiting.width, lessThan(800));
      expect(exiting.center.dx, closeTo(400, 0.01));
      expect(exiting.center.dy, closeTo(300, 0.01));

      await tester.pumpAndSettle();
      expect(find.text('上一页'), findsOneWidget);
      expect(boundsOf(tester, '上一页'), const Rect.fromLTWH(0, 0, 800, 600));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
