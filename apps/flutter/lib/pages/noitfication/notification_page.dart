import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/common_body.dart';
import '../../components/cards/message_card.dart';
import '../../pages/noitfication/notification_controller.dart';
import '../../components/announcement_entry.dart';
import '../../utils/global_data.dart';

// ignore: constant_identifier_names
enum NotificationType { AT, COMMENT, LIKE, FOLLOW, MESSAGE, SYSTEM }

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key, this.typeOverride, this.embedded = false});

  /// 直接构造参数（消息 Tab 的「私信」分段内嵌时用）；为空时回落到
  /// GetX 路由参数，与原路由打开行为一致。
  final NotificationType? typeOverride;

  /// 内嵌模式：只出列表本体，不带 Scaffold/AppBar（宿主自带顶栏）。
  final bool embedded;

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  late final NotificationType type =
      widget.typeOverride ?? Get.arguments['type'];
  late final VoidCallback? _onNotificationsRead =
      widget.typeOverride != null ? null : Get.arguments['onNotificationsRead'];
  late int _notificationCount =
      widget.typeOverride != null ? 0 : Get.arguments['notificationCount'] ?? 0;
  late final String _title = switch (type) {
    NotificationType.AT => '@我的动态',
    NotificationType.COMMENT => '@我的评论',
    NotificationType.LIKE => '我收到的赞',
    NotificationType.FOLLOW => '好友关注',
    NotificationType.MESSAGE => '私信与信息',
    NotificationType.SYSTEM => '酷安小秘书',
  };
  /// 内嵌实例与路由打开的同类页隔离控制器注册，避免互相 dispose 误删。
  String get _controllerTag =>
      widget.embedded ? '${type.name}_embedded' : type.name;

  late final _notificationController = Get.put(
    NotificationController(
      url: switch (type) {
        NotificationType.AT => '/v6/notification/atMeList',
        NotificationType.COMMENT => '/v6/notification/atCommentMeList',
        NotificationType.LIKE => '/v6/notification/feedLikeList',
        NotificationType.FOLLOW => '/v6/notification/contactsFollowList',
        NotificationType.MESSAGE => '/v6/message/list',
        NotificationType.SYSTEM => '/v6/notification/list',
      },
    ),
    tag: _controllerTag,
  );
  bool _controllerUsed = false;

  @override
  void dispose() {
    if (_controllerUsed) {
      _notificationController.scrollController?.dispose();
      Get.delete<NotificationController>(tag: _controllerTag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!GlobalData().isLogin) {
      final body = SafeArea(
          top: false,
          child: Column(children: [
            if (type == NotificationType.MESSAGE)
              const Padding(
                  padding: EdgeInsets.all(10), child: AnnouncementEntry()),
            Expanded(
                child: Center(
                    child: TextButton(
                        onPressed: () => Get.toNamed('/login'),
                        child: const Text('登录后查看私信与酷安通知')))),
          ]));
      if (widget.embedded) return body;
      return Scaffold(appBar: AppBar(title: Text(_title)), body: body);
    }
    _controllerUsed = true;
    final body = commonBody(
        _notificationController,
        itemBuilder: type == NotificationType.MESSAGE
            ? (data) => Obx(() => MessageCard(
                  data: data,
                  onPM: _notificationController.onPM,
                  busy: _notificationController.busyConversations
                      .contains(data.ukey),
                  onPin: () => _notificationController.updateConversation(data,
                      delete: false),
                  onDelete: () => _notificationController
                      .updateConversation(data, delete: true),
                ))
            : null,
        leading: type == NotificationType.MESSAGE
            ? Column(children: [
                const AnnouncementEntry(),
                const SizedBox(height: 8),
                Material(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    leading:
                        const CircleAvatar(child: Icon(Icons.support_agent)),
                    title: const Text('酷安小秘书'),
                    subtitle: const Text('系统通知与信息', maxLines: 1),
                    trailing: _notificationCount > 0
                        ? Badge.count(count: _notificationCount)
                        : null,
                    onTap: () {
                      _onNotificationsRead?.call();
                      Get.toNamed('/notification',
                          arguments: {
                            'type': NotificationType.SYSTEM,
                          },
                          preventDuplicates: false);
                      setState(() => _notificationCount = 0);
                    },
                  ),
                ),
              ])
            : null,
      );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        bottom: const PreferredSize(
          preferredSize: Size.zero,
          child: Divider(height: 1),
        ),
      ),
      body: body,
    );
  }
}
