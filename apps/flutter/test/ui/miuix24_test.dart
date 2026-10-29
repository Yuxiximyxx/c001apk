import 'dart:io';
import 'dart:typed_data';

import 'package:c001apk_flutter/components/app_anim.dart';
import 'package:c001apk_flutter/components/basic_glass.dart' as basic;
import 'package:c001apk_flutter/components/expressive_list_section.dart';
import 'package:c001apk_flutter/components/glass_surface.dart';
import 'package:c001apk_flutter/components/settings/navigation_appearance_settings.dart';
import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/pages/home/return_top_controller.dart';
import 'package:c001apk_flutter/pages/local_follow/local_follow_page.dart';
import 'package:c001apk_flutter/pages/main/main_page.dart';
import 'package:c001apk_flutter/pages/message/message_page.dart';
import 'package:c001apk_flutter/pages/message/messages_page.dart';
import 'package:c001apk_flutter/pages/settings/settings_page.dart';
import 'package:c001apk_flutter/router/app_pages.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// miuix24 返工的验收测试：顶栏玻璃胶囊（药丸可拖）、关注页顶栏
/// inset、消息分段转场与通知行无灰垫层、我的页资料卡保持悬浮 +
/// 我的常去全展开、设置下拉走玻璃菜单、首启无引导直达主页、
/// 设置详情页导航条沉浸。

class _NullDataAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? stream, Future<void>? cancelled) async =>
      ResponseBody.fromString('{"data":null}', 200, headers: {
        Headers.contentTypeHeader: ['application/json']
      });
  @override
  void close({bool force = false}) {}
}

class _RecentDataAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? stream, Future<void>? cancelled) async {
    if (options.path.contains('recentHistoryList')) {
      final items = [
        for (var i = 1; i <= 7; i++)
          '{"entityType":"recentHistory","entityId":$i,'
              '"title":"常去条目$i","logo":"",'
              '"url":"/t/话题$i","target_type":"topic",'
              '"target_type_title":"话题"}'
      ].join(',');
      return ResponseBody.fromString('{"data":[$items]}', 200, headers: {
        Headers.contentTypeHeader: ['application/json']
      });
    }
    return ResponseBody.fromString('{"data":null}', 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('miuix24-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
    GStorage.historyFeed = await Hive.openBox('historyFeed');
    GStorage.blackList = await Hive.openBox('blackList');
    Request();
    // 请求拦截器组装设备头时要读这两项，缺了会在适配器之前失败。
    await GStorage.settings.putAll({
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.xAppDevice: 'synthetic-test-device',
    });
  });

  tearDown(() {
    Get.reset();
    GlobalData().isLogin = false;
    Request.dio.httpClientAdapter = _NullDataAdapter();
  });

  tearDownAll(() async {
    // 用例在 FakeAsync 区里发起的 Hive 写（关注筛选落盘等）要先在
    // 真实事件循环上排空，否则 Hive.close() 会一直等未完成的写。
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      await Hive.close().timeout(const Duration(seconds: 10));
    } catch (_) {
      // 个别写未排空时不吊死整个套件；临时目录清理失败可忽略。
    }
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('glass tab capsule: tap selects and pill drag selects',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 360,
            child: basic.LiquidNavigationBar.tabs(
              labels: const ['全部', '用户', '话题', '数码', '应用', '悄悄'],
              selectedIndex: selected,
              onDestinationSelected: (index) =>
                  setState(() => selected = index),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 底面 + 选中药丸两层 basic 玻璃都在场（药丸不再是平色块）。
    expect(find.byType(basic.GlassSurface), findsWidgets);
    await tester.tap(find.text('话题'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    // 从中央横拖到右缘：药丸跟随、松手吸附到最后一槽。
    await tester.drag(
        find.byKey(const ValueKey('liquid-tabs-surface')),
        const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(selected, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('follow page segment capsule sits below the status bar '
      'and stays tappable', (tester) async {
    GlobalData().isLogin = true;
    // 与 MainPage 的生产注册一致：信息流子组件会 Get.find 它。
    Get.put(ReturnTopController(), tag: 'home');
    Request.dio.httpClientAdapter = _NullDataAdapter();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 784);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GetMaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 784),
          padding: EdgeInsets.only(top: 24, bottom: 24),
          viewPadding: EdgeInsets.only(top: 24, bottom: 24),
        ),
        child: const FollowFeedPage(),
      ),
    ));
    // 信息流在空数据下会停在无限加载动画上，pumpAndSettle 永不
    // 收敛——用有界 pump 等胶囊出现即可。
    for (var i = 0;
        i < 20 && find.byKey(const ValueKey('liquid-tabs-surface')).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final capsule = find.byKey(const ValueKey('liquid-tabs-surface'));
    expect(capsule, findsOneWidget);
    // inset = 状态栏 24 + 顶栏 64；胶囊必须在其下（旧实现是 6dp，
    // 直接压进状态栏）。留 1dp 容差给取整。
    expect(tester.getTopLeft(capsule).dy, greaterThanOrEqualTo(24 + 64 - 1));
    await tester.tap(find.text('话题'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    expect(GStorage.settings.get(FollowFeedSelection.storageKey), 2,
        reason: '点按筛选段应切换到话题关注（value=2）并落盘');
    expect(tester.takeException(), isNull);
    // 切换分段会新建信息流控制器并发起 Dio 请求：先在真实事件循环
    // 上把它排空（本仓 home_feed 测试同款），否则 Dio 的计时器会
    // 被测试框架判为 pending timer；再卸载整树收尾。
    await tester.runAsync(() async {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('messages page: segment switch animates and notification '
      'rows have no grey backing', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: MessagesPage()));
    await tester.pumpAndSettle();
    expect(find.text('@我的动态'), findsOneWidget);
    final section =
        tester.widget<ExpressiveListSection>(find.byType(ExpressiveListSection));
    expect(section.connectedBackground, isFalse,
        reason: '通知行自带卡片底，垫层灰矩形会从圆角后探出（图三）');
    // 分段切换器：时长走 AppAnim.standard 的那一个（页面里另有
    // 子组件自己的 150ms 切换器，不在此断言范围）。
    final segmentSwitcher = find.byWidgetPredicate((widget) =>
        widget is AnimatedSwitcher && widget.duration == AppAnim.standard);
    expect(segmentSwitcher, findsOneWidget);
    await tester.tap(find.text('我的回复'));
    await tester.pump(const Duration(milliseconds: 120));
    // 转场进行中不硬切：切换器仍在场，动画结束后落到目标分段。
    expect(segmentSwitcher, findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('登录后查看我的回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('my page: profile card stays a floating glass panel',
      (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: MessagePage()));
    await tester.pumpAndSettle();
    // 资料卡仍是悬浮玻璃 panel 形态（按小乐纠正：不改流内排布）。
    expect(find.byType(basic.LiquidGlassPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('my page: recent visits render in full without 查看全部',
      (tester) async {
    Request.dio.httpClientAdapter = _RecentDataAdapter();
    await tester.pumpWidget(const GetMaterialApp(home: MessagePage()));
    await tester.pump();
    // 常去列表走真实 Dio 请求：先在真实事件循环上排空再断言。
    await tester.runAsync(() async {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('话题: 常去条目1'), findsOneWidget);
    expect(find.text('话题: 常去条目7'), findsOneWidget,
        reason: '第 7 条也必须渲染——旧实现 take(5) 截断');
    expect(find.text('查看全部'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings glass level picker opens a glass menu, '
      'no material DropdownButton remains', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NavigationAppearanceSettings())));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton), findsNothing);
    await tester.tap(find.text('中档'));
    await tester.pumpAndSettle();
    // 菜单面是 fork GlassSurface（玻璃菜单），条目齐全。
    expect(
        find.ancestor(
            of: find.text('低档'), matching: find.byType(GlassSurface)),
        findsOneWidget);
    expect(find.text('完全'), findsOneWidget);
    await tester.tap(find.text('高档'));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    expect(GStorage.liquidGlassLevel.label, '高档');
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings detail page extends under the navigation bar',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 784),
          padding: EdgeInsets.only(bottom: 34),
          viewPadding: EdgeInsets.only(bottom: 34),
        ),
        child: const SettingsDetailPage(section: SettingsSection.appearance),
      ),
    ));
    await tester.pumpAndSettle();
    final safeArea = tester.widget<SafeArea>(find
        .descendant(
            of: find.byType(SettingsDetailPage),
            matching: find.byType(SafeArea))
        .first);
    expect(safeArea.bottom, isFalse,
        reason: 'SafeArea 底部垫层就是设置页那条不透明带');
    final list = tester.widget<ListView>(find
        .descendant(
            of: find.byType(SettingsDetailPage),
            matching: find.byType(ListView))
        .first);
    expect((list.padding as EdgeInsets).bottom, 8 + 34,
        reason: '底部留白改由列表 padding（原 8 + 导航栏 inset）承担');
    expect(tester.takeException(), isNull);
  });

  test('first launch goes straight to main: no onboarding route or gate',
      () {
    final names = AppPages.getPages.map((page) => page.name).toList();
    expect(names, isNot(contains('/onboarding')));
    final root = AppPages.getPages.firstWhere((page) => page.name == '/');
    expect(root.page(), isA<MainPage>());
    expect(AppPages.canReplay('/onboarding'), isFalse);
  });
}
