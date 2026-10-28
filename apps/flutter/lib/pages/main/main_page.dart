import 'dart:async';

import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../pages/home/return_top_controller.dart';
import '../../pages/home/home_page.dart';
import '../../pages/main/main_controller.dart';
import '../../pages/message/message_page.dart';
import '../../logic/accounts/account_store.dart';
import '../../components/adaptive_reading_pane.dart';
import '../../components/app_navigation_history.dart';
import '../../components/feed_reading_pane.dart';
import '../../components/expressive_loading_indicator.dart';
import '../../components/floating_dock_bar.dart';
import '../../../components/app_anim.dart';
import '../local_follow/local_follow_page.dart';
import '../../components/home_publish_action.dart';
import '../../components/scroll_hiding_action.dart';
import '../../utils/global_data.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage>
    with SingleTickerProviderStateMixin {
  bool _homeFeedSelected = true;
  late final _publishAnimation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300), value: 1);
  final ReturnTopController _pageScrollController =
      Get.put(ReturnTopController(), tag: 'home');
  int _selectedIndex = 0;
  final _indexSctream = StreamController<int>.broadcast();
  late final MainController _mainController = Get.put(MainController());
  var _contrller = PageController();
  bool _resetting = false;
  final _readingKey = GlobalKey<AdaptiveReadingPaneState>();

  /// fluid_glass 试验（分支 fluid-dock-spike）：正文录制句柄——正文
  /// 外包 BackdropLayer 录制、悬浮 Dock 经它采样出图。Dock 未注入
  /// （宽屏 rail）或 shader 不可用时 Dock 自动回落现引擎。
  final _dockPageBackdrop = LayerBackdrop();

  @override
  void initState() {
    super.initState();
    // 预热 fluid 的 shader 程序，避免 Dock 首帧无折射（可选优化，
    // 程序本来也会在首次使用时懒加载）。
    unawaited(FluidGlass.ensureInitialized());
    _mainController.checkLoginInfo();
    AccountStore.changes.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!mounted || _resetting) return;
    setState(() => _resetting = true);
    // Unmount old account pages for a complete frame before reusing the
    // existing Get controller tags. Routes containing old account data close.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Get.until((route) => route.isFirst);
      _contrller.dispose();
      _contrller = PageController(initialPage: _selectedIndex);
      setState(() => _resetting = false);
      _homeFeedSelected = true;
      _publishAnimation.value = 1;
      _mainController.checkLoginInfo();
    });
  }

  @override
  void dispose() {
    AccountStore.changes.removeListener(_sessionChanged);
    _indexSctream.close();
    _contrller.dispose();
    _dockPageBackdrop.dispose();
    _publishAnimation.dispose();
    Get.delete<ReturnTopController>(tag: 'home');
    Get.delete<MainController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // All destinations share the root route. Let Android handle back
    // to the launcher without changing the selected destination.
    return _resetting
        ? const Scaffold(body: Center(child: ExpressiveLoadingIndicator()))
        : LayoutBuilder(
            builder: (_, constraints) {
              final useRail = constraints.maxWidth -
                      MediaQuery.paddingOf(context).horizontal >=
                  600;
              final pages = [
                HomePage(
                  useRail: useRail,
                  onFeedSelected: (selected) {
                    if (_homeFeedSelected != selected) {
                      setState(() => _homeFeedSelected = selected);
                    }
                  },
                  onPublishVisibilityChanged: (visible) {
                    if (visible) {
                      _publishAnimation.forward();
                    } else {
                      _publishAnimation.reverse();
                    }
                  },
                ),
                const FollowFeedPage(),
                const MessagePage(),
              ];
              const railDestinations = <NavigationRailDestination>[
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.home),
                  icon: Icon(Icons.home_outlined),
                  label: Text('首页'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.feed),
                  icon: Icon(Icons.feed_outlined),
                  label: Text('关注'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.person),
                  icon: Icon(Icons.person_outline),
                  label: Text('我的'),
                ),
              ];
              return Scaffold(
                extendBody: true,
                body: SafeArea(
                  top: false,
                  bottom: false,
                  child: Row(children: [
                    if (useRail)
                      StreamBuilder(
                        initialData: _selectedIndex,
                        stream: _indexSctream.stream,
                        builder: (_, snapshot) => NavigationRail(
                          destinations: railDestinations,
                          selectedIndex: snapshot.data,
                          onDestinationSelected: onDestinationSelected,
                          labelType: NavigationRailLabelType.all,
                          trailing: GlobalData().isLogin &&
                                  snapshot.data == 0 &&
                                  _homeFeedSelected
                              ? ScrollHidingAction(
                                  animation: _publishAnimation,
                                  child:
                                      const HomePublishAction(extended: true))
                              : null,
                        ),
                      ),
                    Expanded(
                      child: BackdropLayer(
                        backdrop: _dockPageBackdrop,
                        child: FeedReadingPane(
                          paneKey: _readingKey,
                          leadingInset: useRail ? 80 : 0,
                          child: PageView(
                            physics: const NeverScrollableScrollPhysics(),
                            controller: _contrller,
                            children: pages,
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
                bottomNavigationBar: !useRail
                    ? StreamBuilder(
                        initialData: _selectedIndex,
                        stream: _indexSctream.stream,
                        builder: (_, snapshot) => FloatingDockBar(
                          selectedIndex: snapshot.data ?? _selectedIndex,
                          onDestinationSelected: onDestinationSelected,
                          pageBackdrop: _dockPageBackdrop,
                        ),
                      )
                    : null,
              );
            },
          );
  }

  void onDestinationSelected(int index) {
    if (_resetting || !_contrller.hasClients) return;
    AppNavigationHistoryScope.maybeOf(context)?.discardForward();
    _readingKey.currentState?.reset();
    if (index == 0 && _selectedIndex == 0) {
      _pageScrollController.setIndex(998);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _contrller.jumpToPage(index);
    } else {
      _contrller.animateToPage(
        index,
        duration: AppAnim.page,
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
    _selectedIndex = index;
    _indexSctream.add(index);
  }
}
