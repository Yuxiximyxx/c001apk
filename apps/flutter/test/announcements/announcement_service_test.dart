import 'dart:async';
import 'dart:io';

import 'package:c001apk_flutter/logic/announcements/announcement.dart';
import 'package:c001apk_flutter/logic/announcements/announcement_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'fixtures.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late AnnouncementAdapter adapter;
  late AnnouncementService service;
  late DateTime now;

  AnnouncementService create() => AnnouncementService(box,
      dio: Dio()..httpClientAdapter = adapter, clock: () => now);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('announcement-');
    Hive.init(directory.path);
    box = await Hive.openBox('announcements');
    adapter = AnnouncementAdapter();
    now = DateTime.utc(2026, 10, 23, 10);
    service = create();
  });
  tearDown(() async {
    service.dispose();
    await box.close();
    await directory.delete(recursive: true);
  });

  test('sync fetches only index; reading downloads and reuses one body',
      () async {
    expect(await service.sync(SyncReason.manual), isNull);
    expect(service.items.map((e) => e.id), ['a']);
    expect(service.unreadCount, 1);
    expect(adapter.bodyRequests, 0);
    expect(await service.loadBody(service.items.single), sampleBody);
    expect(await service.loadBody(service.items.single), sampleBody);
    expect(adapter.bodyRequests, 1);
    expect(service.unreadCount, 1);
    await service.markRead(service.items.single);
    expect(service.unreadCount, 0);
    expect(
        adapter.requests.every((r) => !r.headers.containsKey('Cookie')), true);
    expect(
        adapter.requests.every((r) => !r.headers.containsKey('X-App-Device')),
        true);
  });

  test('read and prompt receipts survive reopen and body cache clearing',
      () async {
    adapter.index = indexJson(1, [noticeJson('a', important: true)]);
    await service.sync(SyncReason.manual);
    await service.loadBody(service.items.single);
    await service.markPrompted(service.items.single);
    expect(service.unreadCount, 1);
    expect(service.pendingImportant, isNull);
    await service.markRead(service.items.single);
    await service.clearBodyCache();
    final restored = create();
    expect(restored.unreadCount, 0);
    expect(restored.pendingImportant, isNull);
    expect(await restored.loadBody(restored.items.single), sampleBody);
    expect(adapter.bodyRequests, 2);
    restored.dispose();
  });

  test('content changes preserve read; reminder changes make unread', () async {
    await service.sync(SyncReason.manual);
    await service.markRead(service.items.single);
    adapter.index = indexJson(2, [noticeJson('a', content: 2)]);
    await service.sync(SyncReason.manual);
    expect(service.unreadCount, 0);
    expect(adapter.bodyRequests, 0);
    adapter.index = indexJson(
        3, [noticeJson('a', content: 2, reminder: 2, important: true)]);
    await service.sync(SyncReason.manual);
    expect(service.unreadCount, 1);
    expect(service.pendingImportant?.id, 'a');
  });

  test('removal prunes unread and cached body but retains receipts', () async {
    await service.sync(SyncReason.manual);
    await service.loadBody(service.items.single);
    await service.markRead(service.items.single);
    adapter.index = indexJson(2, []);
    await service.sync(SyncReason.manual);
    expect(service.items, isEmpty);
    expect(service.unreadCount, 0);
    adapter.index = indexJson(3, [noticeJson('a')]);
    await service.sync(SyncReason.manual);
    expect(service.unreadCount, 0);
    await service.loadBody(service.items.single);
    expect(adapter.bodyRequests, 2);
  });

  test('withdrawn and expired announcements are excluded from list and counts',
      () async {
    adapter.index = indexJson(1, [
      noticeJson('a')..['withdrawn'] = true,
      noticeJson('b')..['expiresAt'] = '2026-10-23T09:00:00Z',
      noticeJson('c'),
    ]);
    await service.sync(SyncReason.manual);
    expect(service.items.map((e) => e.id), ['c']);
    expect(service.unreadCount, 1);
  });

  for (final bad in [
    'http',
    'duplicate',
    'path',
    'schema',
    'missing',
    'hash'
  ]) {
    test('$bad index cannot erase previously synced announcements', () async {
      await service.sync(SyncReason.manual);
      switch (bad) {
        case 'http':
          adapter.status = 404;
        case 'duplicate':
          adapter.index = indexJson(2, [noticeJson('b'), noticeJson('b')]);
        case 'path':
          adapter.index =
              indexJson(2, [noticeJson('b')..['path'] = '../secret']);
        case 'schema':
          adapter.index = indexJson(2, [])..['schemaVersion'] = 2;
        case 'missing':
          adapter.index = {'schemaVersion': 1, 'revision': 2};
        case 'hash':
          adapter.index = indexJson(2, [noticeJson('b')..['sha256'] = 'wrong']);
      }
      expect(await service.sync(SyncReason.manual), isNotNull);
      expect(service.items.map((e) => e.id), ['a']);
    });
  }

  test('older and conflicting same revision indexes cannot roll back data',
      () async {
    adapter.index = indexJson(3, [noticeJson('a')]);
    await service.sync(SyncReason.manual);
    adapter.index = indexJson(2, []);
    expect(await service.sync(SyncReason.manual), isNotNull);
    adapter.index = indexJson(3, []);
    expect(await service.sync(SyncReason.manual), isNotNull);
    expect(service.items.map((e) => e.id), ['a']);
  });

  test('new complete empty index intentionally removes all announcements',
      () async {
    await service.sync(SyncReason.manual);
    adapter.index = indexJson(2, []);
    expect(await service.sync(SyncReason.manual), isNull);
    expect(service.items, isEmpty);
    expect(create().items, isEmpty);
  });

  test('only newest important can prompt; removing it never promotes backlog',
      () async {
    adapter.index = indexJson(1, [
      noticeJson('old', important: true)
        ..['publishedAt'] = '2026-10-22T08:00:00Z',
      noticeJson('new', important: true),
    ]);
    await service.sync(SyncReason.manual);
    expect(service.pendingImportant?.id, 'new');
    await service.markPrompted(service.pendingImportant!);
    expect(service.pendingImportant, isNull);
    expect(service.unreadCount, 2);
    adapter.index = indexJson(2, [
      noticeJson('old', important: true)
        ..['publishedAt'] = '2026-10-22T08:00:00Z'
    ]);
    await service.sync(SyncReason.manual);
    expect(service.pendingImportant, isNull);
  });

  test('failed body and checksum mismatch never overwrite last good cache',
      () async {
    await service.sync(SyncReason.manual);
    await service.loadBody(service.items.single);
    adapter.index = indexJson(2, [noticeJson('a', content: 2)]);
    await service.sync(SyncReason.manual);
    adapter.bodyStatus = 404;
    await expectLater(service.loadBody(service.items.single),
        throwsA(isA<AnnouncementFailure>()));
    adapter.bodyStatus = 200;
    adapter.body = '<html>error</html>';
    await expectLater(service.loadBody(service.items.single),
        throwsA(isA<AnnouncementFailure>()));
    expect(service.unreadCount, 1);
    adapter.body = sampleBody;
    expect(await service.loadBody(service.items.single), sampleBody);
    expect(adapter.bodyRequests, 4);
  });

  test('inflight body cannot be returned or marked read after removal',
      () async {
    await service.sync(SyncReason.manual);
    adapter.pendingBody = Completer<void>();
    final item = service.items.single;
    final load = service.loadBody(item);
    final rejected = expectLater(load, throwsA(isA<AnnouncementFailure>()));
    await Future<void>.delayed(Duration.zero);
    adapter.index = indexJson(2, []);
    await service.sync(SyncReason.manual);
    adapter.pendingBody!.complete();
    await rejected;
    await service.markRead(item);
    adapter.index = indexJson(3, [noticeJson('a')]);
    await service.sync(SyncReason.manual);
    expect(service.unreadCount, 1);
  });

  test('inflight old revision is rejected after index changes', () async {
    await service.sync(SyncReason.manual);
    adapter.pendingBody = Completer<void>();
    final load = service.loadBody(service.items.single);
    final rejected = expectLater(load, throwsA(isA<AnnouncementFailure>()));
    await Future<void>.delayed(Duration.zero);
    adapter.index = indexJson(2, [noticeJson('a', content: 2)]);
    await service.sync(SyncReason.manual);
    adapter.pendingBody!.complete();
    await rejected;
  });

  test('concurrent index and identical body requests are coalesced', () async {
    adapter.pendingIndex = Completer<void>();
    final a = service.sync(SyncReason.manual);
    final b = service.sync(SyncReason.inbox);
    await adapter.indexStarted.future;
    expect(adapter.requests, hasLength(1));
    adapter.pendingIndex!.complete();
    await Future.wait([a, b]);
    adapter.pendingBody = Completer<void>();
    final bodies = [
      service.loadBody(service.items.single),
      service.loadBody(service.items.single)
    ];
    await adapter.bodyStarted.future;
    expect(adapter.bodyRequests, 1);
    adapter.pendingBody!.complete();
    expect(await Future.wait(bodies), [sampleBody, sampleBody]);
  });

  test('startup once; resume 6h; inbox 15min; manual always bypasses',
      () async {
    await service.sync(SyncReason.coldStart);
    await service.sync(SyncReason.coldStart);
    await service.sync(SyncReason.inbox);
    await service.sync(SyncReason.resume);
    expect(adapter.requests, hasLength(1));
    now = now.add(const Duration(minutes: 15));
    await service.sync(SyncReason.inbox);
    expect(adapter.requests, hasLength(2));
    now = now.add(const Duration(hours: 5, minutes: 59));
    await service.sync(SyncReason.resume);
    expect(adapter.requests, hasLength(2));
    now = now.add(const Duration(minutes: 1));
    await service.sync(SyncReason.resume);
    expect(adapter.requests, hasLength(3));
    await service.sync(SyncReason.manual);
    expect(adapter.requests, hasLength(4));
  });

  test('failed automatic sync backs off; manual retry and disabled inbox work',
      () async {
    adapter.status = 503;
    await service.sync(SyncReason.inbox);
    await service.sync(SyncReason.resume);
    expect(adapter.requests, hasLength(1));
    adapter.status = 200;
    await service.sync(SyncReason.manual);
    expect(adapter.requests, hasLength(2));
    await service.setAutomaticEnabled(false);
    now = now.add(const Duration(days: 1));
    await service.sync(SyncReason.resume);
    expect(adapter.requests, hasLength(2));
    await service.sync(SyncReason.inbox);
    expect(adapter.requests, hasLength(3));
  });

  test('body cache retains at most 20 recently opened announcements', () async {
    adapter.index =
        indexJson(1, [for (var n = 0; n < 21; n++) noticeJson('item$n')]);
    await service.sync(SyncReason.manual);
    for (final item in service.items) {
      await service.loadBody(item);
    }
    expect(adapter.bodyRequests, 21);
    await service.loadBody(service.items.last);
    expect(adapter.bodyRequests, 21);
    await service.loadBody(service.items.first);
    expect(adapter.bodyRequests, 22);
  });
}
