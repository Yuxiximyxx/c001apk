import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/cards/message_first_card.dart'
    show messageFirstCardRow;
import '../../pages/history/history_page.dart'
    show HistoryPage, HistoryType;
import '../../pages/ffflist/ffflist_page.dart'
    show FFFListPage, FFFListType;

Widget messageSeconfCard(bool isLogin, BuildContext context) {
  return Material(
    clipBehavior: Clip.hardEdge,
    borderRadius: const BorderRadius.all(Radius.circular(12)),
    color: Theme.of(context).colorScheme.onInverseSurface,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        messageFirstCardRow(
          context,
          null,
          [
            '浏览历史',
            '我的常去',
          ],
          [
            () => Get.toNamed(
                  '/history',
                  arguments: {'type': HistoryType.History},
                ),
            isLogin
                ? () => Get.toNamed(
                      '/ffflist',
                      arguments: {'type': FFFListType.RECENT},
                    )
                : () {},
          ],
          [
            Icons.history,
            Icons.my_location,
          ],
          null,
          [
            const HistoryPage(type: HistoryType.History),
            isLogin ? const FFFListPage(type: FFFListType.RECENT) : null,
          ],
        ),
        messageFirstCardRow(
          context,
          null,
          [
            '我的收藏',
            '我的赞',
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
          ],
          [
            Icons.star_border,
            Icons.favorite_border,
          ],
          null,
          [
            isLogin ? const FFFListPage(type: FFFListType.COLLECTION) : null,
            isLogin ? const FFFListPage(type: FFFListType.LIKE) : null,
          ],
        ),
      ],
    ),
  );
}
