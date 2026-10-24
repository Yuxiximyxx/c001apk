import 'package:c001apk_flutter/components/adaptive_card_list.dart';
import 'package:c001apk_flutter/utils/desktop_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop startup has room for three feed columns and navigation',
      (tester) async {
    final bounds = desktopStartupBounds(const Rect.fromLTWH(0, 0, 1920, 1040));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = bounds.size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Row(children: [
      const SizedBox(width: 80),
      Expanded(
          child: AdaptiveCardList(
              itemCount: 12,
              itemBuilder: (_, i) => SizedBox(
                  key: ValueKey(i), height: 100, child: Text('动态 $i')))),
    ]))));
    final first = tester.getTopLeft(find.byKey(const ValueKey(0)));
    final third = tester.getTopLeft(find.byKey(const ValueKey(2)));
    final fourth = tester.getTopLeft(find.byKey(const ValueKey(3)));
    expect(third.dx, greaterThan(first.dx));
    expect(third.dy, first.dy);
    expect(fourth.dy, greaterThan(first.dy));
    expect(bounds.width / bounds.height, closeTo(16 / 9, .01));
    expect(tester.takeException(), isNull);
  });

  for (final workArea in [
    const Rect.fromLTWH(0, 0, 1366, 728),
    const Rect.fromLTWH(-1280, 40, 1280, 640),
    const Rect.fromLTWH(1920, 0, 960, 500),
  ]) {
    test('startup fits and centers inside work area $workArea', () {
      final bounds = desktopStartupBounds(workArea);
      expect(bounds.left, greaterThanOrEqualTo(workArea.left));
      expect(bounds.top, greaterThanOrEqualTo(workArea.top));
      expect(bounds.right, lessThanOrEqualTo(workArea.right));
      expect(bounds.bottom, lessThanOrEqualTo(workArea.bottom));
      expect(bounds.center.dx, closeTo(workArea.center.dx, .001));
      expect(bounds.center.dy, closeTo(workArea.center.dy, .001));
      expect(bounds.width / bounds.height, closeTo(16 / 9, .01));
    });
  }
}
