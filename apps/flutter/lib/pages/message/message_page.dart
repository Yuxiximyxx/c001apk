import '../../components/expressive_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:hive_flutter/hive_flutter.dart';

import '../../components/cards/message_first_card.dart';
import '../../components/cards/message_header_card.dart';
import '../../components/cards/message_second_card.dart';
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

  Widget _shortcuts(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (GlobalData().isLogin && !GStorage.floatingNavigation) ...[
            Obx(() =>
                messageFirstCard(true, context, _messageController.firstList)),
            const SizedBox(height: 10),
          ],
          messageSeconfCard(GlobalData().isLogin, context),
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
        title: const Text('我的'),
        compactTitle: true,
        floatWithoutGlass: true,
        glassTitle: (_) =>
            const Align(alignment: Alignment.centerLeft, child: Text('我的')),
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
                    padding: EdgeInsets.fromLTRB(
                        GStorage.floatingNavigation ? 12 : 0,
                        10,
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
                          _shortcuts(context),
                          const SizedBox(height: 10),
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
