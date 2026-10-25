import 'dart:io';

import 'package:c001apk_flutter/components/source_container.dart';
import 'package:c001apk_flutter/pages/ffflist/ffflist_content.dart';
import 'package:c001apk_flutter/pages/ffflist/ffflist_page.dart';
import 'package:c001apk_flutter/pages/history/history_page.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Render-level tests for pages opened through source-anchored containers.
///
/// miuix9/10 wiring tests only asserted that an openBuilder *returns* the
/// right page object. That missed the miuix10 white-screen regression:
/// a container route is a plain Navigator route and carries no arguments,
/// so `Get.arguments` is null while the page renders — FFFListPage indexed
/// it directly (`Get.arguments['uid']`) and its build threw, leaving the
/// opened route blank. These tests actually open each page through an
/// [AnchoredContainer] (the production mechanism) and assert the real
/// skeleton — AppBar title and body — appears.
void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-anchored-render-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    GStorage.favFeed = await Hive.openBox('favFeed');
    GStorage.historyFeed = await Hive.openBox('historyFeed');
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  tearDown(Get.reset);

  /// Opens [target] through an [AnchoredContainer], exactly like the
  /// profile-page slots do, and lets the (transport-blocked) first data
  /// load resolve into its loading/error/empty state.
  Future<void> openAnchored(WidgetTester tester, Widget target) async {
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: AnchoredContainer(
            closedColor: Colors.white,
            openColor: Colors.white,
            closedBuilder: (context, open) => GestureDetector(
              onTap: open,
              child: const SizedBox(
                width: 80,
                height: 60,
                child: Text('入口'),
              ),
            ),
            openBuilder: (context, close) => target,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('入口'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {});
    await tester.pump();
  }

  Future<void> closeAll(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {});
  }

  group('FFFListPage opened by a container renders its skeleton', () {
    final cases = <(FFFListPage, String)>[
      (const FFFListPage(type: FFFListType.FEED), '我的动态'),
      (const FFFListPage(type: FFFListType.FOLLOW), '我的关注'),
      (const FFFListPage(type: FFFListType.FAN), '关注我的人'),
      (const FFFListPage(type: FFFListType.RECENT), '我的常去'),
      (const FFFListPage(type: FFFListType.LIKE), '我的赞'),
      (const FFFListPage(type: FFFListType.COLLECTION), '我的收藏'),
      (
        const FFFListPage(
          type: FFFListType.COLLECTION_ITEM,
          id: '42',
          title: '测试收藏夹',
        ),
        '测试收藏夹',
      ),
    ];
    for (final (page, title) in cases) {
      testWidgets('${page.type} renders AppBar "$title" and a body',
          (tester) async {
        await openAnchored(tester, page);
        // The harness route carries no GetX arguments: this is the exact
        // condition that white-screened on device.
        expect(Get.arguments, isNull);
        expect(tester.takeException(), isNull);
        expect(find.byType(FFFListPage), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        expect(find.byType(FFFListContent), findsWidgets);
        await closeAll(tester);
      });
    }

    testWidgets('REPLY renders its tab skeleton', (tester) async {
      await openAnchored(
          tester, const FFFListPage(type: FFFListType.REPLY));
      expect(Get.arguments, isNull);
      expect(tester.takeException(), isNull);
      expect(find.byType(AppBar), findsOneWidget);
      // Title and first tab share the label; the second tab is unique.
      expect(find.text('我的回复'), findsWidgets);
      expect(find.text('我收到的回复'), findsOneWidget);
      expect(find.byType(FFFListContent), findsWidgets);
      await closeAll(tester);
    });

    testWidgets('FOLLOW renders its tab skeleton', (tester) async {
      await openAnchored(
          tester, const FFFListPage(type: FFFListType.FOLLOW));
      expect(tester.takeException(), isNull);
      expect(find.text('用户'), findsOneWidget);
      expect(find.text('应用'), findsOneWidget);
      expect(find.byType(FFFListContent), findsWidgets);
      await closeAll(tester);
    });
  });

  group('HistoryPage opened by a container renders its skeleton', () {
    final cases = <(HistoryType, String)>[
      (HistoryType.Favorite, '本地收藏'),
      (HistoryType.History, '浏览历史'),
    ];
    for (final (type, title) in cases) {
      testWidgets('$type renders AppBar "$title" and the empty state',
          (tester) async {
        await openAnchored(tester, HistoryPage(type: type));
        expect(Get.arguments, isNull);
        expect(tester.takeException(), isNull);
        expect(find.byType(HistoryPage), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        // Both Hive boxes are empty in this test environment.
        expect(find.text('暂无内容'), findsOneWidget);
        await closeAll(tester);
      });
    }
  });
}
