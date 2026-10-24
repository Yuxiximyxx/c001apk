import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:get/get.dart';

import '../../components/cards/message_first_card.dart'
    show messageFirstCardRow;
import '../../pages/history/history_page.dart' show HistoryType;
import '../../pages/ffflist/ffflist_page.dart' show FFFListType;

Widget messageSeconfCard(
    bool isLogin, BuildContext context, Function() onNotificationTap,
    [int? notificationBadge]) {
  return MiuixCard(
    cornerRadius: 24,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        messageFirstCardRow(
          context,
          null,
          [
            '本地收藏',
            '浏览历史',
            '消息通知',
          ],
          [
            () => Get.toNamed(
                  '/history',
                  arguments: {'type': HistoryType.Favorite},
                ),
            () => Get.toNamed(
                  '/history',
                  arguments: {'type': HistoryType.History},
                ),
            // The notification sheet itself gates each entry: guests may
            // only open 私信与信息 (which hosts the announcement inbox).
            onNotificationTap,
          ],
          [
            Icons.archive_outlined,
            Icons.history,
            Icons.notifications_outlined,
          ],
          [null, null, notificationBadge],
        ),
        messageFirstCardRow(
          context,
          null,
          [
            '我的收藏',
            '我的赞',
            '我的回复',
          ],
          [
            isLogin
                ? () => Get.toNamed(
                      '/ffflist',
                      arguments: {'type': FFFListType.COLLECTION},
                    )
                : () {},
            isLogin
                ? () => Get.toNamed(
                      '/ffflist',
                      arguments: {'type': FFFListType.LIKE},
                    )
                : () {},
            isLogin
                ? () => Get.toNamed(
                      '/ffflist',
                      arguments: {'type': FFFListType.REPLY},
                    )
                : () {},
          ],
          [
            Icons.star_border,
            Icons.favorite_border,
            Icons.messenger_outline,
          ],
        ),
      ],
    ),
  );
}
