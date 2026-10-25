import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../components/common_body.dart';
import '../../../pages/home/feed/home_feed_controller.dart';
import '../../../pages/home/home_page.dart' show TabType;
import '../../../pages/home/return_top_controller.dart';
import '../../../utils/storage_util.dart';
import '../../../utils/utils.dart';

class HomeFeedPage extends StatefulWidget {
  const HomeFeedPage({
    super.key,
    required this.tabType,
    this.followType,
  });

  final TabType tabType;
  final int? followType;

  @override
  State<HomeFeedPage> createState() => _HomeFeedPageState();
}

class _HomeFeedPageState extends State<HomeFeedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  StreamSubscription<int>? _returnTopSubscription;

  late final followType = widget.followType ?? GStorage.followType;
  late final _tag = widget.tabType == TabType.FOLLOW
      ? '${widget.tabType.name}-${UniqueKey()}'
      : widget.tabType.name;

  late final _homeFeedController = Get.put(
    HomeFeedController(
      tabType: widget.tabType,
      installTime: GStorage.installTime,
      url: switch (widget.tabType) {
        TabType.FOLLOW => Utils.getFollowUrl(followType),
        TabType.HOT => '/page?url=V9_HOME_TAB_RANKING',
        TabType.COOLPIC => '/page?url=V11_FIND_COOLPIC',
        _ => null,
      },
      title: switch (widget.tabType) {
        TabType.FOLLOW => Utils.getFollowTitle(followType),
        TabType.HOT => '热榜',
        TabType.COOLPIC => '酷图',
        _ => null,
      },
    ),
    tag: _tag,
  );

  @override
  void dispose() {
    _returnTopSubscription?.cancel();
    _homeFeedController.scrollController?.removeListener(() {});
    _homeFeedController.scrollController?.dispose();
    Get.delete<HomeFeedController>(
      tag: _tag,
    );
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _homeFeedController.refreshKey = GlobalKey<RefreshIndicatorState>();
    _homeFeedController.scrollController = ScrollController();
    _homeFeedController.returnTopController =
        Get.find<ReturnTopController>(tag: 'home');

    _returnTopSubscription =
        _homeFeedController.returnTopController?.index.listen((index) {
      if (index == TabType.values.indexOf(widget.tabType)) {
        _homeFeedController.animateToTop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // miuix16：首页发布悬浮按钮已按小乐要求去除（连同其滚动显隐动画
    // 与控制器一并删除）；发布入口保留在应用其他既有位置，不新造。
    return Scaffold(
      body: commonBody(_homeFeedController),
    );
  }
}
