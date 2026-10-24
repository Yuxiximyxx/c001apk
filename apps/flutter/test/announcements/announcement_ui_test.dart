import 'dart:async';
import 'dart:io';

import 'package:c001apk_flutter/components/announcement_dialog.dart';
import 'package:c001apk_flutter/components/announcement_entry.dart';
import 'package:c001apk_flutter/logic/announcements/announcement_service.dart';
import 'package:c001apk_flutter/pages/announcements/announcement_inbox_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:dio/dio.dart';

import 'fixtures.dart';

Future<void> waitForAnnouncement(WidgetTester tester, Finder finder) async {
  for (var n = 0; n < 150; n++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
  }
  expect(finder, findsWidgets);
}

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late AnnouncementService service;
  late AnnouncementAdapter adapter;
  late DateTime now;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('announcement-ui-');
    Hive.init(directory.path);
    box = await Hive.openBox('announcements', bytes: Uint8List(0));
    adapter = AnnouncementAdapter();
    now = DateTime.utc(2026, 10, 23, 10);
    service = AnnouncementService(box,
        dio: Dio()..httpClientAdapter = adapter, clock: () => now);
    await service.sync(SyncReason.manual);
  });
  tearDown(() async {
    service.dispose();
    await box.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, Widget home) =>
      tester.pumpWidget(MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN')],
          home: home));

  testWidgets('inbox displays metadata without downloading or marking all read',
      (tester) async {
    await mount(tester, AnnouncementInboxPage(service: service));
    await tester.pumpAndSettle();
    expect(find.text('公告 a'), findsOneWidget);
    expect(find.text('摘要 a'), findsOneWidget);
    expect(service.unreadCount, 1);
    expect(adapter.bodyRequests, 0);
  });

  testWidgets('open one announcement marks only that item read and expands',
      (tester) async {
    adapter.index = indexJson(2, [noticeJson('a'), noticeJson('b')]);
    await tester.runAsync(() => service.sync(SyncReason.manual));
    await mount(tester, AnnouncementInboxPage(service: service));
    await tester.tap(find.text('公告 a'));
    await waitForAnnouncement(tester, find.text('公告正文', findRichText: true));
    await tester.pump();
    expect(service.unreadCount, 1);
    expect(adapter.bodyRequests, 1);
    await tester.tap(find.byTooltip('展开阅读'));
    await tester.pumpAndSettle();
    expect(find.byType(AnnouncementReadingPage), findsOneWidget);
    expect(find.text('公告正文', findRichText: true).last, findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(AnnouncementDialog), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公告 a'));
    await waitForAnnouncement(tester, find.text('公告正文', findRichText: true));
    expect(adapter.bodyRequests, 1);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
  });

  testWidgets('automatic popup marks prompted only after body is visible',
      (tester) async {
    adapter.index = indexJson(2, [noticeJson('a', important: true)]);
    await tester.runAsync(() => service.sync(SyncReason.manual));
    await mount(
        tester,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showAnnouncement(
                        context, service, service.items.single,
                        automatic: true),
                    child: const Text('展示')))));
    await tester.tap(find.text('展示'));
    await waitForAnnouncement(tester, find.text('公告正文', findRichText: true));
    await tester.pump();
    expect(service.pendingImportant, isNull);
    expect(service.unreadCount, 1);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(service.unreadCount, 1);
  });

  testWidgets('failed body offers retry and never marks read', (tester) async {
    adapter.bodyStatus = 404;
    await mount(tester, AnnouncementInboxPage(service: service));
    await tester.tap(find.text('公告 a'));
    await waitForAnnouncement(tester, find.text('重试'));
    expect(service.unreadCount, 1);
    adapter.bodyStatus = 200;
    await tester.tap(find.text('重试'));
    await waitForAnnouncement(tester, find.text('公告正文', findRichText: true));
    await tester.pump();
    expect(service.unreadCount, 0);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
  });

  testWidgets('leaving while body downloads does not consume unread',
      (tester) async {
    adapter.pendingBody = Completer<void>();
    await mount(tester, AnnouncementInboxPage(service: service));
    await tester.tap(find.text('公告 a'));
    await tester.pump();
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    adapter.pendingBody!.complete();
    await tester.runAsync(() => adapter.bodyStarted.future);
    await tester.pump(const Duration(milliseconds: 200));
    expect(service.unreadCount, 1);
  });

  testWidgets('entry updates badge and can open without account data',
      (tester) async {
    await mount(tester, Scaffold(body: AnnouncementEntry(service: service)));
    expect(find.text('c001apk 小助手'), findsOneWidget);
    expect(find.byType(Badge), findsOneWidget);
    await tester.tap(find.text('c001apk 小助手'));
    await tester.pumpAndSettle();
    expect(find.byType(AnnouncementInboxPage), findsOneWidget);
    expect(adapter.bodyRequests, 0);
    await tester.tap(find.text('公告 a'));
    await waitForAnnouncement(tester, find.text('公告正文', findRichText: true));
    await tester.pump();
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('narrow large text keeps actions and Markdown scrollable',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(
        tester,
        MediaQuery(
            data: const MediaQueryData(
                size: Size(360, 640), textScaler: TextScaler.linear(1.6)),
            child: AnnouncementInboxPage(service: service)));
    await tester.tap(find.text('公告 a'));
    await waitForAnnouncement(tester, find.text('公告正文', findRichText: true));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('展开阅读'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long title on short large-text screen leaves close accessible',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final title = List.filled(5, '公告功能测试：欢迎来到 c001apk 小助手').join('，');
    adapter.index = indexJson(2, [noticeJson('a')..['title'] = title]);
    await tester.runAsync(() => service.sync(SyncReason.manual));
    await mount(
        tester,
        MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 480), textScaler: TextScaler.linear(2)),
            child: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showAnnouncement(
                            context, service, service.items.single),
                        child: const Text('展示'))))));
    await tester.tap(find.text('展示'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.byType(AnnouncementDialog), findsNothing);
  });

  testWidgets('expiry updates an already visible list without another sync',
      (tester) async {
    adapter.index =
        indexJson(2, [noticeJson('a')..['expiresAt'] = '2026-10-23T10:00:01Z']);
    await tester.runAsync(() => service.sync(SyncReason.manual));
    await mount(tester, AnnouncementInboxPage(service: service));
    await tester.pump();
    expect(find.text('公告 a'), findsOneWidget);
    now = now.add(const Duration(seconds: 2));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('公告 a'), findsNothing);
    expect(find.text('暂无公告'), findsOneWidget);
  });

  testWidgets('covered popup waits until visible before marking read',
      (tester) async {
    adapter.pendingBody = Completer<void>();
    await mount(tester, AnnouncementInboxPage(service: service));
    await tester.tap(find.text('公告 a'));
    await tester.pump(const Duration(milliseconds: 300));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(DialogRoute<void>(
        context: navigator.context,
        builder: (_) => const AlertDialog(content: Text('遮挡页')))));
    await tester.pump(const Duration(milliseconds: 300));
    adapter.pendingBody!.complete();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    for (var n = 0; n < 10; n++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
    expect(service.unreadCount, 1);
    navigator.pop();
    await waitForAnnouncement(tester, find.text('公告正文', findRichText: true));
    expect(service.unreadCount, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
