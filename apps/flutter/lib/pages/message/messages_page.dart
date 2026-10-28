import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:hive_flutter/hive_flutter.dart';

import '../../components/cards/message_third_card.dart';
import '../../components/expressive_list_section.dart';
import '../../components/expressive_refresh_indicator.dart';
import '../../components/liquid_navigation_bar.dart';
import '../../components/liquid_top_bar.dart';
import '../../logic/announcements/app_announcements.dart';
import '../../utils/extensions.dart';
import '../../utils/global_data.dart';
import '../../utils/storage_util.dart';
import '../ffflist/ffflist_page.dart';
import '../noitfication/notification_page.dart';
import 'message_controller.dart';

/// 独立「消息」Tab（miuix23 从「我的」页拆出）：顶栏悬浮玻璃分段
/// 胶囊承载 通知 / 私信 / 我的回复 三个分段——通知是五类消息入口
/// （原 MessagePage 的内联列表机制，含公告未读叠加），私信内嵌
/// NotificationPage(MESSAGE)，我的回复内嵌 FFFListPage(REPLY)。
/// 玻璃只上顶栏控制层，分段本体走普通列表，不叠玻璃。
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const _segmentLabels = ['通知', '私信', '我的回复'];
  int _segment = 0;

  final _titleList = ['@我的动态', '@我的评论', '我收到的赞', '好友关注', '私信与信息'];
  final _backgroundList = [
    0xFF2196f3,
    0xFF00bcd4,
    0xFF4caf50,
    0xFFf44336,
    0xFFff9800,
  ];
  final _iconList = [
    Icons.alternate_email,
    Icons.message_outlined,
    Icons.thumb_up_alt_outlined,
    Icons.person_add_outlined,
    Icons.mail_outline,
  ];

  /// 与「我的」页共用同一 MessageController 实例（Get.put 幂等）：
  /// 角标与计数两页同步；生命周期沿用 MessagePage 的注册/删除，
  /// 本页不重复 delete。
  late final MessageController _messageController =
      Get.put(MessageController());

  @override
  void initState() {
    super.initState();
    if (GlobalData().isLogin) {
      _messageController.checkCount();
    }
  }

  Widget _notifications(BuildContext context) {
    final announcements = AppAnnouncements.service;
    Widget list() => ExpressiveListSection(
          padding: EdgeInsets.zero,
          children: [
            for (var index = 0; index < _titleList.length; index++)
              Obx(() => messageThirdCard(
                    context,
                    _backgroundList[index],
                    _iconList[index],
                    _titleList[index],
                    (_messageController.thirdList.getOrNull(index) ?? 0) +
                        (index == 4 ? announcements?.unreadCount ?? 0 : 0),
                    () {
                      if (!GlobalData().isLogin && index != 4) return;
                      Get.toNamed('/notification', arguments: {
                        'type': NotificationType.values[index],
                        if (index == 4)
                          'notificationCount':
                              _messageController.notificationCount.value,
                        if (index == 4)
                          'onNotificationsRead': () =>
                              _messageController.notificationCount.value = null,
                      });
                      final count =
                          _messageController.thirdList.getOrNull(index);
                      if (count != null && count > 0) {
                        _messageController.thirdList[index] = null;
                      }
                    },
                  )),
          ],
        );
    return announcements == null
        ? list()
        : AnimatedBuilder(animation: announcements, builder: (_, __) => list());
  }

  Widget _segmentBody(BuildContext context) {
    switch (_segment) {
      case 1:
        return const NotificationPage(
          typeOverride: NotificationType.MESSAGE,
          embedded: true,
        );
      case 2:
        if (!GlobalData().isLogin) {
          return Center(
            child: TextButton(
              onPressed: () => Get.toNamed('/login'),
              child: const Text('登录后查看我的回复'),
            ),
          );
        }
        return const FFFListPage(type: FFFListType.REPLY, embedded: true);
      default:
        return ExpressiveRefreshIndicator(
          onRefresh: () async {
            if (GlobalData().isLogin) {
              await _messageController.checkCount();
            }
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    10, 10, 10, 10 + MediaQuery.paddingOf(context).bottom),
                sliver: SliverToBoxAdapter(child: _notifications(context)),
              ),
            ],
          ),
        );
    }
  }

  /// 非玻璃模式（顶栏玻璃关）时的分段切换回落：普通文字按钮行。
  Widget _plainSegmentTitle(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _segmentLabels.length; i++)
            TextButton(
              onPressed: () => setState(() => _segment = i),
              child: Text(
                _segmentLabels[i],
                style: TextStyle(
                  fontWeight:
                      _segment == i ? FontWeight.bold : FontWeight.normal,
                  color: _segment == i
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder(
      valueListenable: GStorage.settings.listenable(keys: [
        SettingsBoxKey.floatingNavigation,
        SettingsBoxKey.liquidGlass,
        SettingsBoxKey.liquidGlassLevel,
      ]),
      builder: (context, _, __) => LiquidTopBarScaffold(
        overlayBody: false,
        title: _plainSegmentTitle(context),
        compactTitle: true,
        floatWithoutGlass: true,
        glassTitle: (_) => LiquidNavigationBar.tabs(
          labels: _segmentLabels,
          selectedIndex: _segment,
          onDestinationSelected: (index) =>
              setState(() => _segment = index),
          level: GStorage.liquidGlassLevel,
        ),
        onSearch: () => Get.toNamed('/search'),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: _segmentBody(context),
            ),
          ),
        ),
      ),
    );
  }
}
