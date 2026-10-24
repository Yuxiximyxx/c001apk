import 'package:flutter/material.dart';

import '../logic/announcements/announcement_service.dart';
import '../logic/announcements/app_announcements.dart';
import '../pages/announcements/announcement_inbox_page.dart';
import 'announcement_avatar.dart';

class AnnouncementEntry extends StatelessWidget {
  const AnnouncementEntry({super.key, this.service});
  final AnnouncementService? service;

  @override
  Widget build(BuildContext context) {
    final source = service ?? AppAnnouncements.service;
    Widget tile() => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          leading: const AnnouncementAvatar(),
          title: const Text('c001apk 小助手'),
          subtitle: Text(
              source?.items.firstOrNull?.summary.isNotEmpty == true
                  ? source!.items.first.summary
                  : '应用公告与使用提醒',
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          trailing: (source?.unreadCount ?? 0) > 0
              ? Badge.count(count: source!.unreadCount)
              : null,
          onTap: source == null
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => AnnouncementInboxPage(service: source))),
        );
    return Material(
        color: Theme.of(context).colorScheme.onInverseSurface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: source == null
            ? tile()
            : AnimatedBuilder(animation: source, builder: (_, __) => tile()));
  }
}
