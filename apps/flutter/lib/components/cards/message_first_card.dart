import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:get/get.dart';

import '../../components/source_container.dart';
import '../../pages/ffflist/ffflist_page.dart' show FFFListPage, FFFListType;
import '../../utils/extensions.dart';
import '../../utils/miuix_palette.dart';

Widget messageFirstCard(
  bool isLogin,
  BuildContext context,
  List<int?>? values,
) {
  return MiuixCard(
    cornerRadius: 24,
    child: messageFirstCardRow(
      context,
      values,
      ['动态', '关注', '粉丝'],
      [
        isLogin
            ? () => Get.toNamed(
                  '/ffflist',
                  arguments: {'type': FFFListType.FEED},
                )
            : () {},
        isLogin
            ? () => Get.toNamed(
                  '/ffflist',
                  arguments: {'type': FFFListType.FOLLOW},
                )
            : () {},
        isLogin
            ? () => Get.toNamed(
                  '/ffflist',
                  arguments: {'type': FFFListType.FAN},
                )
            : () {},
      ],
      null,
      null,
      [
        isLogin ? const FFFListPage(type: FFFListType.FEED) : null,
        isLogin ? const FFFListPage(type: FFFListType.FOLLOW) : null,
        isLogin ? const FFFListPage(type: FFFListType.FAN) : null,
      ],
    ),
  );
}

Widget messageFirstCardRow(
  BuildContext context,
  List<int?>? values,
  List<String> titles,
  List<Function()> onTaps, [
  List<IconData>? icons,
  List<int?>? badges,
  List<Widget?>? targets,
]) {
  // A slot with an anchored target grows into its page from the slot's own
  // rect and shrinks back into it; slots without a target keep their
  // legacy tap (login-gated entries, the notification-sheet entry).
  Widget slot(int index) {
    // Read the (possibly reactive) slot data NOW, while this row is being
    // built inside the caller's Obx closure: GetX only subscribes an Obx
    // to observables read during that synchronous pass. The anchored item
    // is constructed later, inside OpenContainer's closedBuilder, which
    // would be too late — the Obx would see zero reads, throw its
    // improper-use error and never rebuild on data changes.
    final value = values?.getOrNull(index);
    final icon = icons?.getOrNull(index);
    final badge = badges?.getOrNull(index);
    Widget item(VoidCallback onTap) => _messageFirstCardItem(
          context,
          value,
          titles[index],
          onTap,
          icon,
          badge,
        );
    final target = targets?.getOrNull(index);
    if (target == null) return item(onTaps[index]);
    return AnchoredContainer(
      closedColor: MiuixTheme.of(context).colors.surfaceContainer,
      openColor: miuixPageBackground(context),
      closedShape: const RoundedRectangleBorder(),
      closedBuilder: (context, open) => item(open),
      openBuilder: (context, close) => target,
    );
  }

  return IntrinsicHeight(
    child: Row(
      children: [
        Expanded(flex: 1, child: slot(0)),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: VerticalDivider(width: 1),
        ),
        Expanded(flex: 1, child: slot(1)),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: VerticalDivider(width: 1),
        ),
        Expanded(flex: 1, child: slot(2)),
      ],
    ),
  );
}

Widget _messageFirstCardItem(
  BuildContext context,
  int? value,
  String title,
  Function() onTap, [
  IconData? icon,
  int? badge,
]) {
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Visibility(
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        visible: icon != null ? true : value != null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Badge(
                isLabelVisible: badge != null && badge > 0,
                label: Text(badge.toString()),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            if (icon == null)
              Text(
                value.toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontFamily: 'sans-serif',
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}
