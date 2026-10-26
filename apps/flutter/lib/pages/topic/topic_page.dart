import '../../components/expressive_loading_indicator.dart';
// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:get/get.dart';
import 'package:get/get_navigation/src/dialog/dialog_route.dart';

import '../../components/glass_surface.dart';
import '../../components/glass_menu.dart';
import '../../components/network_image.dart';
import '../../logic/state/loading_state.dart';
import '../../pages/home/return_top_controller.dart';
import '../../pages/feed/reply/reply_page.dart';
import '../../pages/topic/topic_content.dart';
import '../../pages/topic/topic_controller.dart';
import '../../pages/topic/topic_order_controller.dart';
import '../../utils/device_util.dart';
import '../../utils/extensions.dart';
import '../../utils/global_data.dart';
import '../../utils/storage_util.dart';
import '../../utils/utils.dart';
import '../../../components/app_anim.dart';

enum TopicMenuItem {
  Copy,
  Share,
  Block;

  String get label => switch (this) {
        TopicMenuItem.Copy => '复制',
        TopicMenuItem.Share => '分享',
        TopicMenuItem.Block => '屏蔽',
      };
}

enum TopicSortType {
  DEFAULT,
  DATELINE,
  HOT;

  String get label => switch (this) {
        TopicSortType.DEFAULT => '默认',
        TopicSortType.DATELINE => '最新',
        TopicSortType.HOT => '热度',
      };
}

/// miuix5 起头部底色、发帖 FAB 改用应用主题色（MIUIX primary，
/// 浅 #3482FF / 深 #277AF7，随主题取值），不再用 miuix4 的采样绿；
/// 关注按钮改为白底/半透明白底以保证在主题色头部上的可读性。

class TopicPage extends StatefulWidget {
  const TopicPage({super.key, this.tag, this.id});

  /// Direct-construction parameters (source-anchored container navigation).
  /// Fall back to the GetX route parameters when null. [tag] uses the same
  /// percent-encoded form the route parameter carries; initState decodes it.
  final String? tag;
  final String? id;

  @override
  State<TopicPage> createState() => _TopicPageState();
}

class _TopicPageState extends State<TopicPage> with TickerProviderStateMixin {
  late String? _tag = widget.tag ?? Get.parameters['tag'];
  late final String? _id = widget.id ?? Get.parameters['id'];

  bool _shouldShowActions = false;

  TabController? _tabController;
  late final ReturnTopController _pageScrollController;
  late final TopicOrderController _topicOrderController;
  late final TopicController _topicController;

  late final String _random = DeviceUtil.randHexString(8);

  @override
  void initState() {
    super.initState();

    if (!_tag.isNullOrEmpty) {
      try {
        _tag = Uri.decodeComponent(_tag!);
      } catch (e) {
        debugPrint('topic: failed to decode tag: $_tag');
      }
    }

    _pageScrollController =
        Get.put(ReturnTopController(), tag: (_tag ?? _id!) + _random);
    _topicOrderController =
        Get.put(TopicOrderController(), tag: (_tag ?? _id!) + _random);
    _topicController =
        Get.put(TopicController(tag: _tag, id: _id), tag: '$_tag$_id$_random');
    _topicController.initialIndex.listen((initialIndex) {
      _tabController = TabController(
        vsync: this,
        initialIndex: initialIndex < 0 ? 0 : initialIndex,
        length: _topicController.tabList!.length,
      );
      setShouldShowActions(initialIndex);
      // Ensure the sheet swaps from its loading placeholder to the tab
      // content once the controller exists.
      if (mounted) setState(() {});
      _tabController?.addListener(() {
        if (!mounted) return;
        // The sort selector only applies to the product discussion tab;
        // rebuild so it appears/disappears as tabs change.
        setState(() {
          setShouldShowActions(_tabController!.index);
        });
      });
    });
  }

  @override
  void dispose() {
    _tabController?.removeListener(() {});
    _tabController?.dispose();
    Get.delete<ReturnTopController>(tag: (_tag ?? _id!) + _random);
    Get.delete<TopicOrderController>(tag: (_tag ?? _id!) + _random);
    Get.delete<TopicController>(tag: '$_tag$_id$_random');
    super.dispose();
  }

  void setShouldShowActions(int index) {
    _shouldShowActions = _topicController.entityType == 'product' &&
        _topicController.tabList![index].title == '讨论';
  }

  Widget _buildBody(LoadingState topicState) {
    switch (topicState) {
      case Empty():
        return GestureDetector(
          onTap: _topicController.onReGetTopicData,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(10.0),
            child: const Text('暂无内容'),
          ),
        );
      case Error():
        return GestureDetector(
          onTap: _topicController.onReGetTopicData,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(10.0),
            child: Text(topicState.errMsg),
          ),
        );
    }
    return const ExpressiveLoadingIndicator();
  }

  String get _statsText {
    final parts = <String>[];
    final hot = _topicController.hotNumTxt;
    if (hot != null && '$hot'.isNotEmpty) {
      parts.add('$hot热度');
    }
    final discuss = _topicController.entityType == 'product'
        ? (_topicController.feedCommentNumTxt ?? _topicController.commentnumTxt)
        : (_topicController.commentnumTxt ??
            _topicController.feedCommentNumTxt);
    if (discuss != null && '$discuss'.isNotEmpty) {
      parts.add('$discuss讨论');
    }
    return parts.join('   ');
  }

  Future<void> _onFollowPressed() async {
    if (!GlobalData().isLogin) return;
    if (_topicController.entityType == 'topic') {
      await _topicController.onGetFollow(
        _topicController.isFollow,
        _topicController.isFollow
            ? "/v6/feed/unFollowTag"
            : "/v6/feed/followTag",
        tag: _topicController.title,
      );
    } else {
      await _topicController.postLikeDeleteFollow(
        _topicController.id,
        null,
        isProduct: true,
        isFollow: _topicController.isFollow,
      );
    }
    // The controller flips isFollow inside handleGetFollow(); refresh the
    // header button's two states.
    if (mounted) setState(() {});
  }

  Widget _buildHeader(BuildContext context) {
    final followNum = _topicController.followNum;
    return Container(
      color: MiuixTheme.of(context).colors.primary,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Get.back(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: '返回',
              ),
              const Spacer(),
              if (!_topicController.isBlocked)
                IconButton(
                  onPressed: () => Get.toNamed('/search', parameters: {
                    'title': _topicController.title!,
                    'pageType': _topicController.entityType == 'topic'
                        ? 'tag'
                        : 'product_phone',
                    'pageParam': _topicController.entityType == 'topic'
                        ? _topicController.title!
                        : _topicController.id!,
                  }),
                  icon: const Icon(Icons.search, color: Colors.white),
                  tooltip: '搜索',
                ),
              GlassPopupMenuButton<TopicMenuItem>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (TopicMenuItem item) {
                  switch (item) {
                    case TopicMenuItem.Copy:
                      Utils.copyText(Utils.getShareUrl(
                        _topicController.entityType == 'topic'
                            ? _topicController.title!
                            : _topicController.id!,
                        _topicController.entityType == 'topic'
                            ? ShareType.t
                            : ShareType.product,
                      ));
                      break;
                    case TopicMenuItem.Share:
                      Utils.shareContent(
                        _topicController.entityType == 'topic'
                            ? _topicController.title!
                            : _topicController.id!,
                        _topicController.entityType == 'topic'
                            ? ShareType.t
                            : ShareType.product,
                        title: _topicController.title,
                        context: context,
                      );
                      break;
                    case TopicMenuItem.Block:
                      GStorage.onBlock(
                        _topicController.title!,
                        isUser: false,
                        isDelete: _topicController.isBlocked,
                      );
                      setState(() {
                        _topicController.isBlocked =
                            !_topicController.isBlocked;
                      });
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    value: TopicMenuItem.Copy,
                    child: Text(TopicMenuItem.Copy.label),
                  ),
                  PopupMenuItem(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    value: TopicMenuItem.Share,
                    child: Text(TopicMenuItem.Share.label),
                  ),
                  PopupMenuItem(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    value: TopicMenuItem.Block,
                    child: Text(_topicController.isBlocked ? '取消屏蔽' : '屏蔽'),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                clipNetworkImage(
                  _topicController.logo ?? '',
                  radius: 12,
                  width: 58,
                  height: 58,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _topicController.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_statsText.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          _statsText,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (followNum != null && '$followNum'.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$followNum关注',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 13,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 14,
                              color: Colors.white.withOpacity(0.75),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!_topicController.isBlocked)
                  TextButton(
                    onPressed: _onFollowPressed,
                    style: TextButton.styleFrom(
                      backgroundColor: _topicController.isFollow
                          ? Colors.white.withOpacity(0.25)
                          : Colors.white,
                      foregroundColor: _topicController.isFollow
                          ? Colors.white
                          : MiuixTheme.of(context).colors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(_topicController.isFollow ? '已关注' : '关注'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortSelector(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final current = _topicOrderController.topicSortType.value;
      return Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color:
              isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFF4F3F8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: TopicSortType.values.map((type) {
            final selected = type == current;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _topicOrderController.setTopicSortType(type),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                decoration: selected
                    ? BoxDecoration(
                        color: isDark ? const Color(0xFF3A3A3C) : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      )
                    : null,
                child: Text(
                  type.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color:
                        selected ? colorScheme.onSurface : colorScheme.outline,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    });
  }

  Widget _buildSheet(BuildContext context) {
    final tabList = _topicController.tabList!;
    final currentIndex = _tabController?.index ?? 0;
    final currentTitle = tabList[currentIndex].title.toString();
    return Container(
      decoration: BoxDecoration(
        color: MiuixTheme.of(context).colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.hardEdge,
      child: _topicController.isBlocked
          ? Center(
              child: Text('已屏蔽 ${_topicController.title}'),
            )
          : _tabController == null
              ? const Center(child: ExpressiveLoadingIndicator())
              : Column(
                  children: [
                    if (tabList.length > 1)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          dividerColor: Colors.transparent,
                          tabs: tabList
                              .map((item) => Tab(text: item.title.toString()))
                              .toList(),
                          onTap: (value) {
                            if (!_tabController!.indexIsChanging) {
                              _pageScrollController.setIndex(value);
                            }
                          },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                      child: Row(
                        children: [
                          Text(
                            currentTitle == '讨论' ? '全部讨论' : currentTitle,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          if (_shouldShowActions) _buildSortSelector(context),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: tabList
                            .map((item) => TopicContent(
                                  random: _random,
                                  tag: _topicController.tag,
                                  id: _topicController.id,
                                  index: tabList.indexOf(item),
                                  entityType: _topicController.entityType!,
                                  url: item.url.toString(),
                                  title: item.title.toString(),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => _topicController.topicState.value is Success
          ? AnnotatedRegion<SystemUiOverlayStyle>(
              // The green header needs light status-bar icons regardless of
              // the app theme; the nav bar stays transparent (immersive).
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    Theme.of(context).brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark,
                systemNavigationBarContrastEnforced: false,
                systemStatusBarContrastEnforced: false,
              ),
              child: Scaffold(
                backgroundColor: MiuixTheme.of(context).colors.primary,
                floatingActionButton:
                    GlobalData().isLogin && !_topicController.isBlocked
                        ? GlassFab(
                            onPressed: () {
                              Navigator.of(context).push(
                                GetDialogRoute(
                                  // 无变暗层：ReplyPage 不带变暗层（miuix10
                                  // 摘除），路线 barrier 保持透明。
                                  barrierColor: Colors.transparent,
                                  pageBuilder: (buildContext, animation,
                                      secondaryAnimation) {
                                    return ReplyPage(
                                      targetType:
                                          _topicController.entityType == 'topic'
                                              ? 'tag'
                                              : 'product_phone',
                                      targetId: _topicController.id,
                                      title: _topicController.title,
                                    );
                                  },
                                  transitionDuration: AppAnim.page,
                                  transitionBuilder: (context, animation,
                                      secondaryAnimation, child) {
                                    const begin = Offset(0.0, 1.0);
                                    const end = Offset.zero;
                                    const curve = AppAnim.enterCurve;

                                    var tween = Tween(begin: begin, end: end)
                                        .chain(CurveTween(curve: curve));

                                    return SlideTransition(
                                      position: animation.drive(tween),
                                      child: child,
                                    );
                                  },
                                ),
                              );
                            },
                            tooltip: '发布动态',
                            // 原为主题色实心圆钮，现统一改玻璃材质（正圆保持）。
                            circular: true,
                            icon: Icons.add,
                          )
                        : null,
                body: Column(
                  children: [
                    _buildHeader(context),
                    Expanded(child: _buildSheet(context)),
                  ],
                ),
              ),
            )
          : Scaffold(
              appBar: AppBar(),
              body:
                  Center(child: _buildBody(_topicController.topicState.value)),
            ),
    );
  }
}
