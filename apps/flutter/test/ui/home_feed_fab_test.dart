import 'dart:io';

import 'package:c001apk_flutter/components/glass_surface.dart';
import 'package:c001apk_flutter/pages/home/feed/home_feed_page.dart';
import 'package:c001apk_flutter/pages/home/home_page.dart' show TabType;
import 'package:c001apk_flutter/pages/home/return_top_controller.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// miuix16：首页动态流的「发布动态」悬浮按钮按小乐要求去除（连同滚动
/// 显隐动画与控制器）。本测试在登录态下渲染 FEED 页——旧实现恰在
/// 「已登录 && FEED」时显示该 FAB——断言页面正常渲染且不再有任何
/// 悬浮发布按钮。其他页面的 GlassFab（动态详情回复、话题发布、应用
/// 详情发布、已装应用更新、图片翻页箭头）本版未动，其组件行为由
/// glass_fab_test 覆盖。
void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-homefab-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    GStorage.historyFeed = await Hive.openBox('historyFeed');
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  setUp(() async {
    await GStorage.settings.clear();
    GlobalData().isLogin = true;
    Get.put(ReturnTopController(), tag: 'home');
  });
  tearDown(() {
    GlobalData().isLogin = false;
    Get.reset();
  });

  testWidgets('home feed renders without the publish FAB when logged in',
      (tester) async {
    await tester.pumpWidget(const GetMaterialApp(
      home: HomeFeedPage(tabType: TabType.FEED),
    ));
    await tester.pump();
    // 让传输被阻断的首屏加载落到空/错误态（与 anchored 页测试同款）。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {});
    await tester.pump();

    expect(find.byType(HomeFeedPage), findsOneWidget);
    expect(find.byType(GlassFab), findsNothing,
        reason: '首页不应再有玻璃发布按钮');
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('发布动态'), findsNothing,
        reason: '首页不应再有发布动态悬浮入口');
    expect(tester.takeException(), isNull);
  });
}
