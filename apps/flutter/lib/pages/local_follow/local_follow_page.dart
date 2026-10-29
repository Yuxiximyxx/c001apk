import 'dart:math' as math;

import 'package:fluid_glass/fluid_glass.dart'
    show BackdropLayer, LayerBackdrop;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../components/common_body.dart';
import '../../components/liquid_top_bar.dart';
import '../../components/liquid_navigation_bar.dart';
import '../../components/liquid_popup_menu.dart';
import '../../components/network_image.dart';
import '../../logic/local_follow/local_follow_store.dart';
import '../../utils/global_data.dart';
import '../../utils/storage_util.dart';
import '../home/feed/home_feed_page.dart';
import '../home/home_page.dart' show TabType;
import 'local_follow_controller.dart';

String get localFollowLabel => GlobalData().isLogin ? '悄悄关注' : '本地关注';

enum FollowFeedSelection {
  users(1, '用户关注'),
  topics(2, '话题关注'),
  products(3, '数码关注'),
  apps(4, '应用关注'),
  all(0, '全部关注'),
  local(5, '悄悄关注');

  const FollowFeedSelection(this.value, this.label);
  final int value;
  final String label;
  static const storageKey = 'followFeedSelectionV1';

  static FollowFeedSelection load() {
    // Preserve explicit legacy categories; the old mixed default becomes users.
    final legacy = GStorage.followType;
    final value = GStorage.settings
        .get(storageKey, defaultValue: legacy >= 1 && legacy <= 4 ? legacy : 1);
    return values.firstWhere((item) => item.value == value,
        orElse: () => users);
  }
}

/// The main timeline keeps server follows and local follows separate.
class FollowFeedPage extends StatefulWidget {
  const FollowFeedPage({super.key});
  @override
  State<FollowFeedPage> createState() => _FollowFeedPageState();
}

class _FollowFeedPageState extends State<FollowFeedPage>
    with AutomaticKeepAliveClientMixin {
  FollowFeedSelection _selection = FollowFeedSelection.load();

  /// 筛选胶囊的采样录制（miuix24）：信息流包进 BackdropLayer 录制、
  /// 胶囊作为 Stack 悬浮层在录制子树之外采样，与顶栏/Dock 同构。
  final LayerBackdrop _feedBackdrop = LayerBackdrop();

  @override
  void dispose() {
    _feedBackdrop.dispose();
    super.dispose();
  }

  Future<void> _select(FollowFeedSelection selection) async {
    if (selection != _selection) setState(() => _selection = selection);
    try {
      await GStorage.settings
          .put(FollowFeedSelection.storageKey, selection.value);
    } catch (_) {
      SmartDialog.showToast('关注分类保存失败，请重试');
    }
  }

  @override
  bool get wantKeepAlive => true;

  /// 关注页筛选段控（miuix23 玻璃四页覆盖）：与主页同款的
  /// LiquidNavigationBar.tabs 玻璃胶囊，悬浮在信息流顶部，段目与
  /// 顶栏的选择器共用同一 [_selection] 状态（全部/用户/话题/数码/
  /// 应用/悄悄）。玻璃关时不显示，顶栏选择器仍可切换。
  static const _segmentOrder = [
    FollowFeedSelection.all,
    FollowFeedSelection.users,
    FollowFeedSelection.topics,
    FollowFeedSelection.products,
    FollowFeedSelection.apps,
    FollowFeedSelection.local,
  ];
  static const _segmentLabels = ['全部', '用户', '话题', '数码', '应用', '悄悄'];

  Widget _bodyWithSegmentCapsule(BuildContext context, Widget body) {
    if (!GlobalData().isLogin ||
        !GStorage.floatingNavigation ||
        !GStorage.liquidGlass) {
      return body;
    }
    final isLocalView = _selection == FollowFeedSelection.local;
    final padding = MediaQuery.paddingOf(context);
    // 胶囊高度与 LiquidNavigationBar.tabs 的公式一致（48 起、
    // 随字号长高），间距一律走 TopBarMetrics（miuix24 收口）。
    final capsuleHeight =
        math.max(48.0, MediaQuery.textScalerOf(context).scale(14) + 24);
    final contentOffset =
        capsuleHeight + TopBarMetrics.rowGap + TopBarMetrics.contentGap;
    final padded = isLocalView
        ? Padding(padding: EdgeInsets.only(top: contentOffset), child: body)
        : MediaQuery(
            data: MediaQuery.of(context).copyWith(
                padding: padding.copyWith(top: padding.top + contentOffset)),
            child: body);
    return Stack(children: [
      Positioned.fill(
          child: BackdropLayer(backdrop: _feedBackdrop, child: padded)),
      // miuix24 修复：miuix23 把胶囊钉在 body 顶部 6dp——body 在
      // overlay 模式下从屏幕最上方起算，于是胶囊直接压进状态栏、
      // 与时钟/信号图标重叠且点不到。现按 body 的 MediaQuery 頂部
      // inset（= 状态栏 + 顶栏行高，LiquidTopBarScaffold 注入）下移
      // 到顶栏行下方，再加统一行距；六个段目均分整行、缩放兜底，
      // 「悄悄」不再被裁切。
      Positioned(
        top: padding.top + TopBarMetrics.rowGap,
        left: TopBarMetrics.horizontalPadding,
        right: TopBarMetrics.horizontalPadding,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: TopBarGlassScope(
              backdrop: _feedBackdrop,
              child: LiquidNavigationBar.tabs(
                labels: _segmentLabels,
                selectedIndex: _segmentOrder.indexOf(_selection),
                onDestinationSelected: (index) =>
                    _select(_segmentOrder[index]),
                level: GStorage.liquidGlassLevel,
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  List<PopupMenuEntry<FollowFeedSelection>> _menuItems() => [
        const PopupMenuItem<FollowFeedSelection>(
            enabled: false, height: 32, child: Text('账号关注')),
        for (final item in FollowFeedSelection.values) ...[
          if (item == FollowFeedSelection.local) const PopupMenuDivider(),
          CheckedPopupMenuItem(
              value: item,
              checked: item == _selection,
              child: Text(item.label)),
        ],
      ];

  Widget _label() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
              child: Text(_selection.label,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down),
        ]),
      );

  double _titleWidth(BuildContext context, String label, {bool arrow = true}) {
    final painter = TextPainter(
        text: TextSpan(
            text: label, style: Theme.of(context).textTheme.titleLarge),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context))
      ..layout();
    final width = painter.width + (arrow ? 56 : 40);
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder(
      valueListenable:
          GStorage.settings.listenable(keys: [SettingsBoxKey.isLogin]),
      builder: (context, _, __) => LiquidTopBarScaffold(
        compactTitle: true,
        floatWithoutGlass: true,
        glassTitle: (context) => GlobalData().isLogin
            ? LiquidPopupMenuButton<FollowFeedSelection>(
                height:
                    math.max(48, MediaQuery.textScalerOf(context).scale(20)),
                width: _titleWidth(context, _selection.label),
                tooltip: '切换关注内容',
                items: _menuItems(),
                onSelected: _select,
                child: _label())
            : Align(
                alignment: Alignment.centerLeft,
                child: LiquidGlassButton(
                    height: math.max(
                        48, MediaQuery.textScalerOf(context).scale(20)),
                    width: _titleWidth(context, '本地关注', arrow: false),
                    enabled: GStorage.liquidGlass,
                    level: GStorage.liquidGlassLevel,
                    tooltip: '本地关注',
                    onPressed: null,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                            child: Text('本地关注',
                                style:
                                    Theme.of(context).textTheme.titleLarge))))),
        titleSpacing: 8,
        title: GlobalData().isLogin
            ? PopupMenuButton<FollowFeedSelection>(
                tooltip: '切换关注内容',
                initialValue: _selection,
                position: PopupMenuPosition.under,
                onSelected: _select,
                itemBuilder: (context) => _menuItems(),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: _label()),
              )
            : const Text('本地关注'),
        onSearch: () => Get.toNamed('/search'),

        body: Builder(
          builder: (context) => _bodyWithSegmentCapsule(
            context,
            !GlobalData().isLogin || _selection == FollowFeedSelection.local
                ? const SafeArea(bottom: false, child: LocalFollowFeedView())
                : HomeFeedPage(
                    key: ValueKey(_selection),
                    tabType: TabType.FOLLOW,
                    followType: _selection.value,
                  ),
          ),
        ),
      ),
    );
  }
}

class LocalFollowFeedView extends StatefulWidget {
  const LocalFollowFeedView({super.key});
  @override
  State<LocalFollowFeedView> createState() => _LocalFollowFeedViewState();
}

class _LocalFollowFeedViewState extends State<LocalFollowFeedView> {
  final _tag = UniqueKey().toString();
  late final LocalFollowController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(LocalFollowController(), tag: _tag);
  }

  @override
  void dispose() {
    Get.delete<LocalFollowController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        ListTile(
          dense: true,
          title: Text('$localFollowLabel动态'),
          subtitle: const Text('读取本机名单中的用户动态，不会同步账号关注'),
          trailing: TextButton(
            onPressed: () => Get.to(() => const LocalFollowListPage()),
            child: const Text('管理'),
          ),
        ),
        Obx(() => _controller.warning.value == null
            ? const SizedBox.shrink()
            : ListTile(
                dense: true,
                title: Text(_controller.warning.value!),
                trailing: TextButton(
                    onPressed: () {
                      _controller.isEnd = false;
                      _controller.onGetData(false);
                    },
                    child: const Text('重试')),
              )),
        Expanded(
            child: ValueListenableBuilder(
          valueListenable:
              GStorage.settings.listenable(keys: [LocalFollowStore.usersKey]),
          builder: (context, _, __) => LocalFollowStore().users.isEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                      GlobalData().isLogin
                          ? '还没有悄悄关注的用户\n在设置中开启后，长按用户主页的关注按钮即可添加'
                          : '还没有本地关注的用户\n在用户主页点击“本地关注”，即可在这里查看动态',
                      textAlign: TextAlign.center),
                ))
              : commonBody(_controller),
        )),
      ]);
}

class LocalFollowListPage extends StatelessWidget {
  const LocalFollowListPage({super.key});

  Future<void> _remove(String uid) async {
    try {
      await LocalFollowStore().unfollow(uid);
      SmartDialog.showToast('已取消$localFollowLabel，仅修改本机名单');
    } catch (_) {
      SmartDialog.showToast('本地关注保存失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('管理$localFollowLabel')),
        body: ValueListenableBuilder(
          valueListenable:
              GStorage.settings.listenable(keys: [LocalFollowStore.usersKey]),
          builder: (context, _, __) {
            final users = LocalFollowStore().users;
            return Column(children: [
              const ListTile(
                  subtitle: Text('名单仅保存在本机，登录、退出或关闭悄悄关注开关后仍会保留。不会自动同步到账号。')),
              Expanded(
                  child: users.isEmpty
                      ? const Center(child: Text('还没有关注的用户'))
                      : ListView.builder(
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final user = users[index];
                            return ListTile(
                              leading: clipNetworkImage(user.avatar,
                                  isAvatar: true, width: 40, height: 40),
                              title: Text(user.name.isEmpty
                                  ? '用户 ${user.uid}'
                                  : user.name),
                              subtitle: Text('UID：${user.uid}'),
                              onTap: () => Get.toNamed('/u/${user.uid}'),
                              trailing: IconButton(
                                tooltip: '取消$localFollowLabel',
                                onPressed: () => _remove(user.uid),
                                icon: const Icon(Icons.person_remove_outlined),
                              ),
                            );
                          },
                        )),
            ]);
          },
        ),
      );
}
