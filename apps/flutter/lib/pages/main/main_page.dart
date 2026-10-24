import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:get/get.dart';

import '../../pages/home/return_top_controller.dart';
import '../../pages/home/home_page.dart';
import '../../pages/main/main_controller.dart';
import '../../pages/message/message_page.dart';
import '../../logic/accounts/account_store.dart';
import '../../components/adaptive_reading_pane.dart';
import '../../components/feed_reading_pane.dart';
import '../../components/expressive_loading_indicator.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final ReturnTopController _pageScrollController =
      Get.put(ReturnTopController(), tag: 'home');
  int _selectedIndex = 0;
  final _indexSctream = StreamController<int>.broadcast();
  late final MainController _mainController = Get.put(MainController());
  var _contrller = PageController();
  bool _resetting = false;
  final _readingKey = GlobalKey<AdaptiveReadingPaneState>();

  @override
  void initState() {
    super.initState();
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
      _mainController.checkLoginInfo();
    });
  }

  @override
  void dispose() {
    AccountStore.changes.removeListener(_sessionChanged);
    _indexSctream.close();
    _contrller.dispose();
    Get.delete<ReturnTopController>(tag: 'home');
    Get.delete<MainController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      HomePage(),
      MessagePage(),
    ];

    const railDestinations = <NavigationRailDestination>[
      NavigationRailDestination(
        selectedIcon: Icon(Icons.home),
        icon: Icon(Icons.home_outlined),
        label: Text('首页'),
      ),
      NavigationRailDestination(
        selectedIcon: Icon(Icons.person),
        icon: Icon(Icons.person_outline),
        label: Text('我的'),
      ),
    ];

    // All three destinations share the root route. Let Android handle back
    // to the launcher without changing the selected destination.
    return _resetting
        ? const Scaffold(body: Center(child: ExpressiveLoadingIndicator()))
        : LayoutBuilder(
            builder: (_, constriants) {
              final useRail = constriants.maxWidth -
                      MediaQuery.paddingOf(context).horizontal >=
                  600;

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
                        ),
                      ),
                    Expanded(
                      child: FeedReadingPane(
                        paneKey: _readingKey,
                        child: PageView(
                          physics: const NeverScrollableScrollPhysics(),
                          controller: _contrller,
                          children: pages,
                        ),
                      ),
                    ),
                  ]),
                ),
                bottomNavigationBar: !useRail
                    ? StreamBuilder(
                        initialData: _selectedIndex,
                        stream: _indexSctream.stream,
                        builder: (_, snapshot) => ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: MiuixNavigationBar(
                              color: MiuixTheme.of(context)
                                  .colors
                                  .surface
                                  .withValues(alpha: 0.86),
                              mode: MiuixNavigationBarDisplayMode.iconAndText,
                              children: [
                                MiuixNavigationBarItem(
                                  selected: snapshot.data == 0,
                                  onPressed: () => onDestinationSelected(0),
                                  icon: Icon(snapshot.data == 0
                                      ? Icons.home
                                      : Icons.home_outlined),
                                  label: '首页',
                                ),
                                MiuixNavigationBarItem(
                                  selected: snapshot.data == 1,
                                  onPressed: () => onDestinationSelected(1),
                                  icon: Icon(snapshot.data == 1
                                      ? Icons.person
                                      : Icons.person_outline),
                                  label: '我的',
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : null,
              );
            },
          );
  }

  void onDestinationSelected(int index) {
    if (_resetting || !_contrller.hasClients) return;
    _readingKey.currentState?.close();
    if (index == 0 && _selectedIndex == 0) {
      _pageScrollController.setIndex(998);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _contrller.jumpToPage(index);
    } else {
      _contrller.animateToPage(
        index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
    _selectedIndex = index;
    _indexSctream.add(index);
  }
}
