import 'package:hive/hive.dart';

import 'announcement_service.dart';

class AppAnnouncements {
  static AnnouncementService? service;

  static Future<void> initialize() async {
    service ??= AnnouncementService(await Hive.openBox('announcements'));
  }
}
