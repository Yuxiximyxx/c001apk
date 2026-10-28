// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../pages/carousel/carousel_page.dart';
import '../../pages/ffflist/ffflist_content.dart';
import '../../utils/global_data.dart';

enum FFFListType {
  FEED,
  FOLLOW,
  APK,
  USER_FOLLOW,
  FAN,
  RECENT,
  LIKE,
  REPLY,
  REPLYME,
  FAV,
  HISTORY,
  COLLECTION,
  COLLECTION_ITEM
}

class FFFListPage extends StatefulWidget {
  const FFFListPage(
      {super.key, this.uid, this.type, this.id, this.title, this.embedded = false});

  /// Direct-construction parameters (source-anchored container navigation).
  /// Fall back to the GetX route arguments when null.
  final String? uid;
  final FFFListType? type;
  final String? id;
  final String? title;

  /// 内嵌模式（消息 Tab「我的回复」分段）：不出 Scaffold/AppBar，
  /// 只保留 TabBar（回复/回复我）+ 列表本体，顶栏由宿主提供。
  final bool embedded;

  @override
  State<FFFListPage> createState() => _FFFListPageState();
}

class _FFFListPageState extends State<FFFListPage>
    with TickerProviderStateMixin {
  /// Arguments of the GetX route that pushed this page, or null when the
  /// page was opened by a source-anchored container. A container route is
  /// a plain Navigator route and carries no arguments, so [Get.arguments]
  /// itself is null there and must never be indexed directly (doing so
  /// throws and blanks the whole page). On the GetX path callers always
  /// pass a Map, so behaviour there is unchanged.
  static Map<dynamic, dynamic>? get _routeArguments {
    final arguments = Get.arguments;
    return arguments is Map ? arguments : null;
  }

  late final String? _uid =
      widget.uid ?? _routeArguments?['uid'] ?? GlobalData().uid;
  late final FFFListType _type = widget.type ?? _routeArguments?['type'];
  late final String? _id = widget.id ?? _routeArguments?['id'];
  late final String? _title = widget.title ?? _routeArguments?['title'];

  late final bool _isMe = GlobalData().uid == _uid;

  late final _followList = ['用户', '话题', '数码', '应用'];
  late final _replyList = ['我的回复', '我收到的回复'];

  late final _tabList = _type == FFFListType.FOLLOW
      ? _followList
      : _type == FFFListType.REPLY
          ? _replyList
          : null;
  late final _tabController =
      TabController(length: _tabList!.length, vsync: this);

  late final _titleText = _title ??
      switch (_type) {
        FFFListType.FEED => '我的动态',
        FFFListType.FOLLOW => '我的关注',
        FFFListType.USER_FOLLOW => _isMe ? '我关注的人' : 'TA关注的人',
        FFFListType.FAN => _isMe ? '关注我的人' : 'TA的粉丝',
        FFFListType.RECENT => '我的常去',
        FFFListType.LIKE => '我的赞',
        FFFListType.REPLY => '我的回复',
        FFFListType.COLLECTION => '我的收藏',
        FFFListType.APK => '',
        FFFListType.REPLYME => '',
        FFFListType.FAV => '',
        FFFListType.HISTORY => '',
        FFFListType.COLLECTION_ITEM => '',
      };

  @override
  Widget build(BuildContext context) {
    final Widget content = _tabList != null
          ? TabBarView(
              controller: _tabController,
              children: _type == FFFListType.REPLY
                  ? List.generate(
                      2,
                      (index) => FFFListContent(
                          uid: _uid,
                          id: _id,
                          type: index == 0
                              ? FFFListType.REPLY
                              : FFFListType.REPLYME)).toList()
                  : List.generate(4, (index) {
                      if (index == 0 || index == 3) {
                        return FFFListContent(
                            uid: _uid,
                            id: _id,
                            type: index == 0
                                ? FFFListType.FOLLOW
                                : FFFListType.APK);
                      } else {
                        return CarouselPage(
                          isInit: false,
                          url: index == 1
                              ? '#/topic/userFollowTagList'
                              : '#/product/followProductList',
                          title: index == 1 ? '我关注的话题' : '我关注的数码吧',
                        );
                      }
                    }).toList())
          : FFFListContent(
              uid: _type == FFFListType.COLLECTION ? null : _uid,
              id: _id,
              type: _type,
            );
    if (widget.embedded) {
      if (_tabList == null) return content;
      return Column(children: [
        TabBar(
            controller: _tabController,
            tabs: _tabList.map((item) => Tab(text: item)).toList()),
        Expanded(child: content),
      ]);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titleText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: _tabList != null
            ? TabBar(
                controller: _tabController,
                tabs: _tabList.map((item) => Tab(text: item)).toList())
            : const PreferredSize(
                preferredSize: Size.zero, child: Divider(height: 1)),
      ),
      body: content,
    );
  }
}
