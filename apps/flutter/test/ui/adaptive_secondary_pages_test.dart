import 'dart:io';

import 'package:c001apk_flutter/components/app_keyboard_navigation.dart';
import 'package:c001apk_flutter/pages/message/message_page.dart';
import 'package:c001apk_flutter/pages/settings/settings_page.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-secondary-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    GlobalData().isLogin = false;
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  Future<void> resize(WidgetTester tester, double width,
      {double height = 700}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    await tester.pumpAndSettle();
  }

  Widget app(Widget page, {double scale = 1}) => GetMaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: AppKeyboardNavigation(navigatorKey: Get.key, child: child!),
        ),
        home: page,
      );

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  testWidgets('my page places messages beside shortcuts only when they fit',
      (tester) async {
    await resize(tester, 1200);
    await tester.pumpWidget(app(const MessagePage()));
    await tester.pumpAndSettle();
    final shortcut = find.text('本地收藏');
    final message = find.text('@我的动态');
    expect(tester.getTopLeft(message).dx,
        greaterThan(tester.getTopLeft(shortcut).dx + 200));
    expect(tester.getTopLeft(message).dy,
        lessThan(tester.getBottomLeft(shortcut).dy + 30));
    await resize(tester, 400);
    expect(tester.getTopLeft(message).dy,
        greaterThan(tester.getBottomLeft(find.text('我的回复')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('my page keeps its scroll position when changing layout',
      (tester) async {
    await resize(tester, 400, height: 300);
    await tester.pumpWidget(app(const MessagePage()));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(70);
    await tester.pumpAndSettle();
    await resize(tester, 1200, height: 300);
    expect(
        tester.state<ScrollableState>(find.byType(Scrollable).first), scroll);
    expect(scroll.position.pixels, closeTo(70, 1));
    await resize(tester, 400, height: 300);
    expect(scroll.position.pixels, closeTo(70, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'large text falls back to stacked my page and settings navigation',
      (tester) async {
    await resize(tester, 1000);
    await tester.pumpWidget(app(const MessagePage(), scale: 1.5));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('@我的动态')).dy,
        greaterThan(tester.getBottomLeft(find.text('我的回复')).dy));
    await tester.pumpWidget(app(const SettingsPage(), scale: 1.5));
    await tester.pumpAndSettle();
    expect(find.text('分栏阅读'), findsNothing);
    await tester.tap(find.text('外观与字号'));
    await tester.pumpAndSettle();
    expect(find.text('分栏阅读'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings arrows scroll the category pane the user last touched',
      (tester) async {
    await resize(tester, 1500, height: 340);
    await tester.pumpWidget(app(const SettingsPage()));
    await tester.pumpAndSettle();
    final lists = find.byType(ListView);
    ScrollPosition position(int index) => tester
        .state<ScrollableState>(find.descendant(
            of: lists.at(index), matching: find.byType(Scrollable)))
        .position;
    await tester.tap(find.text(SettingsSection.appearance.description));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(position(0).pixels, greaterThan(0));
    expect(position(1).pixels, 0);
    final categoryOffset = position(0).pixels;
    await tester.tap(find.text('外观与字号').last);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(position(1).pixels, greaterThan(0));
    expect(position(0).pixels, categoryOffset);
  });

  testWidgets('settings remembers each category scroll position',
      (tester) async {
    await resize(tester, 1200, height: 360);
    await tester.pumpWidget(app(const SettingsPage()));
    await tester.pumpAndSettle();
    ScrollPosition detail() => tester
        .state<ScrollableState>(find.descendant(
            of: find.byType(SettingsDetailPage),
            matching: find.byType(Scrollable)))
        .position;
    detail().jumpTo(90);
    await tester.pumpAndSettle();
    await tester.tap(find.text('浏览与隐私'));
    await tester.pumpAndSettle();
    expect(detail().pixels, 0);
    await tester.tap(find.text('外观与字号').first);
    await tester.pumpAndSettle();
    expect(detail().pixels, closeTo(90, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('grouped settings fit 320dp with double text size',
      (tester) async {
    await resize(tester, 320, height: 800);
    await tester.pumpWidget(app(
        const SettingsDetailPage(section: SettingsSection.appearance),
        scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('字体大小'), 300,
        scrollable: find.byType(Scrollable));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('字体大小'), findsOneWidget);
  });
}
