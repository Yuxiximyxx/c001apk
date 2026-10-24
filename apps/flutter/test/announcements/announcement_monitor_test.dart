import 'dart:async';
import 'dart:typed_data';

import 'package:c001apk_flutter/components/announcement_monitor.dart';
import 'package:c001apk_flutter/logic/announcements/announcement_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'announcement_ui_test.dart' show waitForAnnouncement;
import 'fixtures.dart';

void main() {
  late Box<dynamic> box;
  late AnnouncementService service;
  late AnnouncementAdapter adapter;
  late DateTime now;
  setUp(() async {
    Get.testMode = true;
    box = await Hive.openBox('announcements-monitor', bytes: Uint8List(0));
    adapter = AnnouncementAdapter()
      ..index = indexJson(1, [noticeJson('a', important: true)]);
    now = DateTime.utc(2026, 10, 23, 10);
    service = AnnouncementService(box,
        dio: Dio()..httpClientAdapter = adapter, clock: () => now);
  });
  tearDown(() async {
    service.dispose();
    await box.close();
    Get.reset();
  });

  Future<void> mount(WidgetTester tester, {bool updateShown = false}) async {
    await tester.pumpWidget(AnnouncementMonitor(
        service: service,
        clock: () => now,
        checkUpdates: () async {},
        updatePromptShown: () => updateShown,
        child: const GetMaterialApp(home: Scaffold(body: Text('首页')))));
  }

  Future<void> drain(WidgetTester tester) async {
    for (var n = 0; n < 15; n++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  testWidgets('startup displays newest important once; resume never stacks',
      (tester) async {
    await mount(tester);
    await waitForAnnouncement(tester, find.text('公告正文', findRichText: true));
    expect(service.pendingImportant, isNull);
    expect(service.unreadCount, 1);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    now = now.add(const Duration(hours: 7));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await drain(tester);
    expect(find.text('知道了'), findsNothing);
    expect(adapter.bodyRequests, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('update prompt takes priority without downloading announcement',
      (tester) async {
    await mount(tester, updateShown: true);
    await drain(tester);
    expect(service.items, hasLength(1));
    expect(adapter.bodyRequests, 0);
    expect(find.text('知道了'), findsNothing);
    expect(service.pendingImportant?.id, 'a');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving root while index loads avoids popup and body request',
      (tester) async {
    adapter.pendingIndex = Completer<void>();
    await mount(tester);
    await drain(tester);
    Get.to(() => const Scaffold(body: Text('登录页')));
    await tester.pumpAndSettle();
    adapter.pendingIndex!.complete();
    await drain(tester);
    expect(find.text('登录页'), findsOneWidget);
    expect(adapter.bodyRequests, 0);
    expect(service.pendingImportant?.id, 'a');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background or route change during body load consumes no prompt',
      (tester) async {
    adapter.pendingBody = Completer<void>();
    await mount(tester);
    await drain(tester);
    expect(adapter.bodyRequests, 1);
    Get.to(() => const Scaffold(body: Text('其他页面')));
    await tester.pumpAndSettle();
    adapter.pendingBody!.complete();
    await drain(tester);
    expect(find.text('知道了'), findsNothing);
    expect(service.pendingImportant?.id, 'a');
    expect(service.unreadCount, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled automatic check makes no startup network request',
      (tester) async {
    await tester.runAsync(() => service.setAutomaticEnabled(false));
    await mount(tester);
    await drain(tester);
    expect(adapter.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed automatic body backs off across repeated resume events',
      (tester) async {
    adapter.bodyStatus = 503;
    await mount(tester);
    await drain(tester);
    expect(adapter.bodyRequests, 1);
    for (var n = 0; n < 2; n++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await drain(tester);
    }
    expect(adapter.bodyRequests, 1);
    adapter.bodyStatus = 200;
    String? manuallyLoaded;
    unawaited(service.loadBody(service.items.single).then((body) {
      manuallyLoaded = body;
    }));
    await drain(tester);
    expect(manuallyLoaded, sampleBody,
        reason: 'Manual reading bypasses automatic backoff');
    now = now.add(const Duration(minutes: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitForAnnouncement(tester, find.text('公告正文', findRichText: true));
    await tester.pumpWidget(const SizedBox());
  });
}
