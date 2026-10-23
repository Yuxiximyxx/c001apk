import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:get/get.dart' hide Response;

import '../../components/cards/message_first_card.dart';
import '../../components/cards/message_header_card.dart';
import '../../components/cards/message_second_card.dart';
import '../../components/cards/message_third_card.dart';
import '../../pages/ffflist/ffflist_page.dart' show FFFListType;
import '../../pages/message/message_controller.dart';
import '../../pages/noitfication/notification_page.dart';
import '../../utils/extensions.dart';
import '../../utils/global_data.dart';

class MessagePage extends StatefulWidget {
  const MessagePage({super.key});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _backgroundList = [
    0xFF2196f3,
    0xFF00bcd4,
    0xFF4caf50,
    0xFFf44336,
    0xFFff9800,
  ];
  final _titleList = ['@我的动态', '@我的评论', '我收到的赞', '好友关注', '私信与信息'];
  final _iconList = [
    Icons.alternate_email,
    Icons.message_outlined,
    Icons.thumb_up_alt_outlined,
    Icons.person_add_outlined,
    Icons.mail_outline,
  ];
  late final MessageController _messageController =
      Get.put(MessageController());

  @override
  void dispose() {
    Get.delete<MessageController>();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (GlobalData().isLogin) {
      _onRefresh();
    }
  }

  Future<void> _onRefresh() async {
    if (!mounted || !GlobalData().isLogin) return;
    final generation = GlobalData().sessionGeneration;
    await _messageController.getProfile();
    if (!mounted || generation != GlobalData().sessionGeneration) return;
    await _messageController.checkCount();
  }

  /// 5 类消息的未读总数，用于"消息通知"角标
  int? _totalNotificationBadge() {
    int total = 0;
    bool hasAny = false;
    for (int i = 0; i < 5; i++) {
      final count = _messageController.thirdList.getOrNull(i);
      if (count != null) {
        hasAny = true;
        total += count;
      }
    }
    if (!hasAny) return null;
    return total;
  }

  /// 点"消息通知"弹出 5 类消息列表
  void _showNotificationSheet() {
    if (!GlobalData().isLogin) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < 5; i++) ...[
                Obx(
                  () => messageThirdCard(
                    context,
                    _backgroundList[i],
                    _iconList[i],
                    _titleList[i],
                    _messageController.thirdList.getOrNull(i),
                    () {
                      Get.back();
                      Get.toNamed('/notification', arguments: {
                        'type': NotificationType.values[i],
                        if (i == 4)
                          'notificationCount':
                              _messageController.notificationCount.value,
                        if (i == 4)
                          'onNotificationsRead': () => _messageController
                              .notificationCount.value = null,
                      });
                      int? count =
                          _messageController.thirdList.getOrNull(i);
                      if (count != null && count > 0) {
                        _messageController.thirdList[i] = null;
                      }
                    },
                  ),
                ),
                if (i < 4) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: MiuixTheme.of(context).colors.background,
      appBar: AppBar(
          backgroundColor: MiuixTheme.of(context).colors.background,
          surfaceTintColor: Colors.transparent,
          title: const Text('我的'), actions: [
        IconButton(
            onPressed: () => Get.toNamed('/accounts'),
            icon: const Icon(Icons.switch_account_outlined),
            tooltip: '账号管理'),
        IconButton(
            onPressed: () => Get.toNamed('/settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置'),
      ]),
      body: Column(
        children: [
          const SizedBox(height: 10),
          Obx(
            () => MessageHeaderCard(
              userInfo: _messageController.userInfo.value,
              onLogin: () => Get.toNamed('/login'),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (GlobalData().isLogin) {
                  await _onRefresh();
                } else {
                  return Future.value();
                }
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(10),
                    sliver: SliverList.separated(
                      itemCount: GlobalData().isLogin ? 3 : 2,
                      itemBuilder: (context, itemIndex) {
                        final index =
                            itemIndex + (GlobalData().isLogin ? 0 : 1);
                        if (index == 0) {
                          return Obx(
                            () => messageFirstCard(
                              GlobalData().isLogin,
                              context,
                              _messageController.firstList,
                            ),
                          );
                        } else if (index == 1) {
                          return Obx(() => messageSeconfCard(
                                GlobalData().isLogin,
                                context,
                                _showNotificationSheet,
                                _totalNotificationBadge(),
                              ));
                        } else if (index == 2) {
                          // 下半部分改为"我的常去"
                          return messageThirdCard(
                            context,
                            0xFF00bcd4,
                            Icons.my_location,
                            '我的常去',
                            null,
                            () {
                              if (GlobalData().isLogin) {
                                Get.toNamed(
                                  '/ffflist',
                                  arguments: {'type': FFFListType.RECENT},
                                );
                              }
                            },
                          );
                        }
                        return const SizedBox();
                      },
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
