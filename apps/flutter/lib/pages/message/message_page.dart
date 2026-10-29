import 'dart:math' as math;

import '../../components/expressive_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:hive_flutter/hive_flutter.dart';

import '../../components/cards/message_first_card.dart';
import '../../components/cards/message_header_card.dart';
import '../../components/cards/recent_visits_card.dart';
import '../../components/liquid_top_bar.dart';
import '../../pages/message/message_controller.dart';
import '../../utils/global_data.dart';
import '../../utils/storage_util.dart';

class MessagePage extends StatefulWidget {
  const MessagePage({super.key});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late final MessageController _messageController =
      Get.put(MessageController());
  final ValueNotifier<int> _recentRefresh = ValueNotifier<int>(0);

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
    _recentRefresh.value++;
  }

  // miuix26：原 2x2 功能格卡（浏览历史/我的常去/我的收藏/我的赞）
  // 整张移除——「我的常去」格与下方同名展开列表重复，其余三入口
  // 已并入上方资料卡组件（MessageHeaderCard 统计行下方）。此处只剩
  // 非悬浮模式下独立渲染的统计卡（悬浮模式统计行在资料卡内）。
  Widget _shortcuts(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (GlobalData().isLogin && !GStorage.floatingNavigation) ...[
            Obx(() =>
                messageFirstCard(true, context, _messageController.firstList)),
            const SizedBox(height: 10),
          ],
        ],
      );

  /// 标题玻璃片宽度（与关注页 _titleWidth 同口径：文字宽 + 40）。
  double _titleWidth(BuildContext context, String label) {
    final painter = TextPainter(
        text: TextSpan(
            text: label, style: Theme.of(context).textTheme.titleLarge),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context))
      ..layout();
    final width = painter.width + 40;
    painter.dispose();
    return width;
  }

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
        backdropIndex: 3,
        // 顶区与主页/关注同构（miuix25 第三条）：去掉白色底板，
        // 滚动内容覆到玻璃顶栏之下；置顶资料卡头靠自身顶部
        // padding 吃掉顶栏 inset，首屏位置与布局不变（卡片仍
        // 悬浮在内容上方，不改流内排布）。
        title: const Text('我的'),
        compactTitle: true,
        floatWithoutGlass: true,
        // 标题融进悬浮玻璃语言（miuix25 第三条口径①）：与关注页
        // 标题同款的 LiquidGlassButton 玻璃片（纯展示、不可点），
        // 不再是裸文字浮在顶区；右上两圆钮同为 LiquidGlassButton。
        glassTitle: (context) => Align(
          alignment: Alignment.centerLeft,
          child: LiquidGlassButton(
            height:
                math.max(48, MediaQuery.textScalerOf(context).scale(20)),
            width: _titleWidth(context, '我的'),
            enabled: GStorage.liquidGlass,
            level: GStorage.liquidGlassLevel,
            tooltip: '我的',
            onPressed: null,
            child: Text('我的',
                style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        glassActions: (context) => [
          for (final action in [
            (Icons.switch_account_outlined, '账号管理', '/accounts'),
            (Icons.settings_outlined, '设置', '/settings'),
          ]) ...[
            const SizedBox(width: 10),
            LiquidGlassButton(
              height: (MediaQuery.textScalerOf(context).scale(20) + 0.0)
                  .clamp(48.0, double.infinity),
              width: (MediaQuery.textScalerOf(context).scale(20) + 0.0)
                  .clamp(48.0, double.infinity),
              level: GStorage.liquidGlassLevel,
              enabled: GStorage.liquidGlass,
              tooltip: action.$2,
              onPressed: () => Get.toNamed(action.$3),
              child: Center(child: Icon(action.$1)),
            ),
          ],
        ],
        actions: [
          IconButton(
              onPressed: () => Get.toNamed('/accounts'),
              icon: const Icon(Icons.switch_account_outlined),
              tooltip: '账号管理'),
          IconButton(
              onPressed: () => Get.toNamed('/settings'),
              icon: const Icon(Icons.settings_outlined),
              tooltip: '设置'),
        ],
        body: SafeArea(
          top: false,
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: LayoutBuilder(builder: (context, bounds) {
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                final header = ColoredBox(
                  color: GStorage.floatingNavigation
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.surface,
                  child: Padding(
                    // 顶部再吃脚手架给的 inset（玻璃覆下模式 = 顶栏
                    // 高，非覆下时为 0）：置顶头钉在视口顶时，资料卡
                    // 仍落在顶栏下方原位，顶栏玻璃悬浮在头的留白区
                    // 之上，滚动内容从其下穿过。
                    padding: EdgeInsets.fromLTRB(
                        GStorage.floatingNavigation ? 12 : 0,
                        10 + MediaQuery.paddingOf(context).top,
                        GStorage.floatingNavigation ? 12 : 0,
                        10),
                    child: Obx(() => MessageHeaderCard(
                          floating: GStorage.floatingNavigation,
                          userInfo: _messageController.userInfo.value,
                          counts: _messageController.firstList.toList(),
                          onLogin: () => Get.toNamed('/login'),
                        )),
                  ),
                );
                // A short landscape window must still reach the messages at
                // enlarged text sizes instead of pinning the entire viewport.
                final pinHeader = bounds.maxHeight >= 320 * scale;
                return ExpressiveRefreshIndicator(
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
                      if (pinHeader)
                        PinnedHeaderSliver(child: header)
                      else
                        SliverToBoxAdapter(child: header),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(10, 10, 10,
                            10 + MediaQuery.paddingOf(context).bottom),
                        sliver: SliverToBoxAdapter(
                            child: Column(children: [
                          // 悬浮模式下 _shortcuts 为空（统计与三入口
                          // 都在资料卡内），不留空白间隔。
                          if (GlobalData().isLogin &&
                              !GStorage.floatingNavigation) ...[
                            _shortcuts(context),
                            const SizedBox(height: 10),
                          ],
                          // 「我的常去」直接内嵌展示最近访问（fork 定制）
                          RecentVisitsCard(refreshSignal: _recentRefresh),
                        ])),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
