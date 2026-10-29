import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/cards/message_first_card.dart'
    show messageFirstCardRow;
import '../../pages/history/history_page.dart'
    show HistoryPage, HistoryType;
import '../../pages/ffflist/ffflist_page.dart'
    show FFFListPage, FFFListType;

/// 「我的」页资料卡内的功能入口行（miuix26）：浏览历史 / 我的收藏 /
/// 我的赞，横排三等分、图标在上文字在下，图标与跳转目标与旧 2x2
/// 功能格卡完全一致。旧卡里的「我的常去」格与下方同名展开列表
/// 重复，已随整张功能格卡移除，三入口并入上方资料卡组件。
Widget messageProfileEntriesRow(BuildContext context, bool isLogin) {
  return messageFirstCardRow(
    context,
    null,
    [
      '浏览历史',
      '我的收藏',
      '我的赞',
    ],
    [
      () => Get.toNamed(
            '/history',
            arguments: {'type': HistoryType.History},
          ),
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
      Icons.history,
      Icons.star_border,
      Icons.favorite_border,
    ],
    null,
    [
      const HistoryPage(type: HistoryType.History),
      isLogin ? const FFFListPage(type: FFFListType.COLLECTION) : null,
      isLogin ? const FFFListPage(type: FFFListType.LIKE) : null,
    ],
  );
}
