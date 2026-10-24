import 'dart:io';

import 'package:c001apk_flutter/logic/announcements/announcement_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('explicit public GitHub index and one body can be read independently',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('announcement-live-');
    Hive.init(directory.path);
    final box = await Hive.openBox('announcements-live');
    final service = AnnouncementService(box);
    try {
      expect(await service.sync(SyncReason.manual), isNull);
      final testNotice =
          service.items.singleWhere((e) => e.id == '2026-10-23-test');
      final body = await service.loadBody(testNotice);
      expect(body, contains('欢迎来到 c001apk 小助手'));
      expect(body, contains('这是一篇用于验收公告功能的'));
      expect(service.unreadCount, greaterThanOrEqualTo(1));
    } finally {
      service.dispose();
      await box.close();
      await directory.delete(recursive: true);
    }
  },
      skip: Platform.environment['C001APK_LIVE_ANNOUNCEMENTS'] != '1',
      timeout: const Timeout(Duration(seconds: 40)));
}
