import 'dart:convert';
import 'dart:io';

import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/pages/topic/topic_page.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart' as miuix;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Pins the topic page's reported page background (miuix22 keyboard
/// tint fix).
///
/// The topic page used to paint its whole Scaffold with the topic
/// primary color (the blue header showed through it). The system
/// reports that scaffold background to the keyboard area, so a
/// translucent frosted IME skin came up dyed in the topic color when
/// the publish editor raised the keyboard over this page. Other pages
/// report the normal page background (surface) and are unaffected.
///
/// The fix: the topic Scaffold takes the same page background as
/// every other page (surface), while the primary color survives only
/// in the header layer itself plus an underlay behind the sheet,
/// which is visible solely through the sheet's 24dp rounded top
/// corner notches — the header visuals are unchanged.
class TopicDetailAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final isTopicDetail = options.path.contains('newTagDetail');
    final payload = isTopicDetail
        ? {
            'data': {
              'id': 123,
              'title': '测试话题',
              'entityType': 'topic',
              'logo': '',
              'hot_num_txt': '2177',
              'follow_num': '426',
              'commentnum_txt': '123',
              'selectedTab': 'feed2',
              'tabList': [
                {
                  'title': '推荐',
                  'url': '/v6/topic/feed1',
                  'page_name': 'feed1',
                },
                {
                  'title': '讨论',
                  'url': '/v6/topic/feed2',
                  'page_name': 'feed2',
                },
              ],
              'userAction': {'follow': 0},
            },
          }
        : {'data': <dynamic>[]};
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late TopicDetailAdapter adapter;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-topic-bg-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    GStorage.favFeed = await Hive.openBox('favFeed');
    GStorage.historyFeed = await Hive.openBox('historyFeed');
    GStorage.blackList = await Hive.openBox('blackList');
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-device',
      SettingsBoxKey.userAgent: 'SyntheticTest/1.0',
      SettingsBoxKey.versionName: '16.2.0',
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.apiVersion: '16',
      SettingsBoxKey.sdkInt: '33',
    });
  });

  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  setUp(() {
    adapter = TopicDetailAdapter();
    Request();
    Request.dio.httpClientAdapter = adapter;
  });

  tearDown(Get.reset);

  testWidgets(
      'topic scaffold reports the page surface, header stays primary',
      (tester) async {
    final themeData = appMiuixThemeData(Brightness.dark);
    final surface = themeData.colors.surface;
    final primary = themeData.colors.primary;
    expect(surface, isNot(primary));

    await tester.pumpWidget(
      miuix.MiuixTheme(
        data: themeData,
        child: const GetMaterialApp(home: TopicPage(tag: '测试话题')),
      ),
    );
    // Let the fake topic-detail request resolve into the Success
    // branch (header + sheet), and the tab contents' list requests
    // settle too — Dio schedules them on zero-duration fake-zone
    // timers that must not outlive the test.
    await tester.pump();
    await tester.runAsync(() async {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {});
    await tester.pump();

    // The Success branch rendered: the header shows the topic title.
    final titleFinder = find.text('测试话题');
    expect(titleFinder, findsOneWidget);

    // The page Scaffold must report the normal page background, not
    // the topic primary — this is the color the keyboard area gets.
    final scaffoldFinder = find.ancestor(
      of: titleFinder,
      matching: find.byType(Scaffold),
    );
    expect(scaffoldFinder, findsOneWidget);
    final scaffold = tester.widget<Scaffold>(scaffoldFinder);
    expect(scaffold.backgroundColor, surface);
    expect(scaffold.backgroundColor, isNot(primary));

    // The header itself still paints primary across the full width.
    final headerFinder = find.byWidgetPredicate(
      (w) => w is Container && w.color == primary,
    );
    expect(headerFinder, findsOneWidget);
    final headerRect = tester.getRect(headerFinder);
    expect(headerRect.left, 0);
    expect(headerRect.right, tester.view.physicalSize.width /
        tester.view.devicePixelRatio);
    expect(headerRect.top, 0);

    // The sheet keeps its surface fill and 24dp rounded top corners.
    final sheetFinder = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final decoration = w.decoration;
      return decoration is BoxDecoration &&
          decoration.color == surface &&
          decoration.borderRadius ==
              const BorderRadius.vertical(top: Radius.circular(24));
    });
    expect(sheetFinder, findsOneWidget);
    final sheetRect = tester.getRect(sheetFinder);
    expect(sheetRect.top, headerRect.bottom);

    // A primary underlay backs the whole sheet area, so the rounded
    // corner notches still reveal the topic color exactly as before;
    // the sheet's opaque surface covers it everywhere else. (The
    // header's own Container also materializes as a primary
    // ColoredBox, so select by geometry: the underlay is the primary
    // box that exactly spans the sheet's rect.)
    Rect? underlayRect;
    for (final element in find.byType(ColoredBox).evaluate()) {
      final box = element.widget as ColoredBox;
      if (box.color != primary) continue;
      final rect = tester.getRect(find.byWidget(box));
      if (rect == sheetRect) underlayRect = rect;
    }
    expect(underlayRect, isNotNull,
        reason: 'a primary underlay must span the sheet area');

    // Dispose and flush the tab contents' in-flight list requests
    // (Dio schedules them on zero-duration timers in the fake zone;
    // only a pump with a duration advances that clock).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {});
    await tester.pump(const Duration(milliseconds: 500));
  });
}
