import 'package:c001apk_flutter/components/network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../logic/model/feed/datum.dart';
import '../../utils/global_data.dart';
import '../../utils/storage_util.dart';
import '../liquid_glass_surface.dart';
import 'message_first_card.dart';
import 'message_second_card.dart';

class MessageHeaderCard extends StatelessWidget {
  const MessageHeaderCard({
    super.key,
    this.userInfo,
    required this.onLogin,
    this.floating = false,
    this.counts,
  });

  final Datum? userInfo;
  final Function() onLogin;
  final bool floating;
  final List<int?>? counts;

  String get _username {
    final name = userInfo?.username ?? GlobalData().username;
    try {
      return Uri.decodeComponent(name);
    } catch (_) {
      return name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final experience = userInfo?.experience ?? GStorage.exp;
    final nextExperience = userInfo?.nextLevelExperience ?? GStorage.nextExp;
    final content = Padding(
      padding: EdgeInsets.symmetric(
          horizontal: floating ? 18 : 20, vertical: floating ? 16 : 0),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!GlobalData().isLogin) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Center(
              child: FilledButton.tonal(
                onPressed: onLogin,
                child: const Text('点击登录'),
              ),
            ),
          ),
          // 未登录时三入口同样归资料卡内（与旧功能格卡未登录可见
          // 的行为一致；收藏/赞未登录点击为空操作，历史可正常进）。
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 6),
          messageProfileEntriesRow(context, false),
          if (!floating) const SizedBox(height: 6),
        ] else ...[
          Row(
            children: [
              Semantics(
                button: true,
                label: '查看个人主页',
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: () =>
                      Get.toNamed('/u/${userInfo?.uid ?? GlobalData().uid}'),

                  child: clipNetworkImage(
                    userInfo?.userAvatar ?? GStorage.userAvatar,
                    isAvatar: true,
                    width: floating ? 52 : 45,
                    height: floating ? 52 : 45,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Lv.${userInfo?.level ?? GStorage.level}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Expanded(
                            child: Text(
                          '$experience/$nextExperience',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 13),
                        )),
                      ],
                    ),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(
                      value: nextExperience > 0
                          ? (experience / nextExperience).clamp(0.0, 1.0)
                          : 0,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (floating) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 6),
            messageFirstCard(true, context, counts, transparent: true),
            // 功能入口并入资料卡（miuix26）：原资料卡下方 2x2 功能
            // 格卡整张移除——「我的常去」格与下方同名列表重复，
            // 剩浏览历史/我的收藏/我的赞三入口移到统计行下方。
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            messageProfileEntriesRow(context, GlobalData().isLogin),
          ] else ...[
            // 非悬浮模式下统计行不在卡内（页面另行渲染），但三入口
            // 同样归资料卡内部，紧随头像行/登录按钮下方。
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 6),
            messageProfileEntriesRow(context, GlobalData().isLogin),
            const SizedBox(height: 6),
          ],
        ],
      ]),
    );
    return Material(
      type: MaterialType.transparency,
      child: floating
          ? LiquidGlassPanel(
              enabled: GStorage.liquidGlass,
              level: GStorage.liquidGlassLevel,
              child: content,
            )
          : ColoredBox(
              color: Theme.of(context).colorScheme.surface, child: content),
    );
  }
}
