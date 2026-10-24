import 'package:c001apk_flutter/components/expressive_list_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'legacy dynamic palette keeps grouped rows distinct from background',
      (tester) async {
    final theme = ThemeData(
        colorScheme: const ColorScheme.dark(
      surface: Color(0xff241b18),
    ));
    await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(
          body:
              ExpressiveListSection(children: [ListTile(title: Text('主题设置'))]),
        )));
    final material = find
        .ancestor(of: find.text('主题设置'), matching: find.byType(Material))
        .first;
    expect(tester.widget<Material>(material).color,
        isNot(theme.scaffoldBackgroundColor));
  });

  testWidgets('scrolling releases the row press before the finger lifts',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: ListView(children: [
        ExpressiveListSection(children: [
          ListTile(title: const Text('可滚动设置'), onTap: () => taps++),
          const SizedBox(height: 1000),
        ]),
      ]),
    )));
    final material = find
        .ancestor(of: find.text('可滚动设置'), matching: find.byType(Material))
        .first;
    final resting = tester.widget<Material>(material).shape;
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('可滚动设置')));
    await tester.pumpAndSettle();
    expect(tester.widget<Material>(material).shape, isNot(resting));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(tester.widget<Material>(material).shape, resting);
    expect(taps, 0);
    await gesture.up();
  });

  testWidgets('cancelled press restores row shape without activating the row',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: ExpressiveListSection(children: [
        ListTile(title: const Text('设置项目'), onTap: () => taps++),
        const ListTile(title: Text('第二项')),
      ]),
    )));
    final material = find
        .ancestor(of: find.text('设置项目'), matching: find.byType(Material))
        .first;
    ShapeBorder? shape() => tester.widget<Material>(material).shape;
    final resting = shape();
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('设置项目')));
    await tester.pumpAndSettle();
    expect(shape(), isNot(resting));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(shape(), resting);
    expect(taps, 0);
    await tester.tap(find.text('设置项目'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('group decoration does not duplicate switch actions',
      (tester) async {
    var changes = 0;
    var enabled = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: StatefulBuilder(
          builder: (context, setState) => ExpressiveListSection(children: [
                SwitchListTile(
                    title: const Text('开关项目'),
                    value: enabled,
                    onChanged: (value) => setState(() {
                          enabled = value;
                          changes++;
                        })),
                const ListTile(enabled: false, title: Text('不可用')),
              ])),
    )));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(changes, 1);
    await tester.tap(find.text('开关项目'));
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
    expect(changes, 2);
    expect(tester.takeException(), isNull);
  });
}
