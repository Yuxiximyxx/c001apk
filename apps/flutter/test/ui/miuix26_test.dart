import 'dart:io';
import 'dart:typed_data';

import 'package:c001apk_flutter/components/cards/message_header_card.dart';
import 'package:c001apk_flutter/components/liquid_top_bar.dart';
import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/pages/ffflist/ffflist_page.dart';
import 'package:c001apk_flutter/pages/message/message_page.dart';
import 'package:c001apk_flutter/pages/message/messages_page.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:dio/dio.dart';
import 'package:fluid_glass/fluid_glass.dart' show BackdropLayer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// miuix26 验收：①我的页 2x2 功能格卡移除、三入口（浏览历史/
/// 我的收藏/我的赞）并入资料卡统计行下方、「我的常去」格消失；
/// ②消息页「我的回复」分段的子 TabBar（我的回复/我收到的回复，
/// REPLY 与 REPLYME 两张真实列表）不再顶进状态栏——吃宿主顶部
/// inset 落在玻璃分段栏下方，列表不再双倍顶距；
/// ③主页面玻璃录制滚动期动态降级（motionPixelRatio = dpr/2、
/// 静止 pixelRatio 不动）。

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

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('miuix26-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
    Request();
    await GStorage.settings.putAll({
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.xAppDevice: 'synthetic-test-device',
    });
    Request.dio.httpClientAdapter = _NullDataAdapter();
  });

  tearDown(() {
    Get.reset();
    GlobalData().isLogin = false;
  });

  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await Hive.close().timeout(const Duration(seconds: 10));
    } catch (_) {}
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await GStorage.settings.clear();
    await GStorage.settings.putAll({
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.xAppDevice: 'synthetic-test-device',
    });
  });

  /// 有界 pump：列表在空数据下停在加载动画上，pumpAndSettle 不收敛。
  Future<void> pumpBounded(WidgetTester tester, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('my page: three entries live inside the profile card, '
      'no standalone function grid', (tester) async {
    GlobalData().isLogin = true;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GetMaterialApp(home: MessagePage()));
    await tester.pumpAndSettle();
    final header = find.byType(MessageHeaderCard);
    expect(header, findsOneWidget);
    // 三入口都在资料卡组件内部。
    for (final label in ['浏览历史', '我的收藏', '我的赞']) {
      expect(
          find.descendant(of: header, matching: find.text(label)),
          findsOneWidget,
          reason: '$label 应并入资料卡');
    }
    // 入口行在统计行下方（「粉丝」是统计行最后一项）。
    expect(tester.getTopLeft(find.text('浏览历史')).dy,
        greaterThan(tester.getTopLeft(find.text('粉丝')).dy));
    // 「我的常去」格已删：全页只剩下方同名展开区块一处文字。
    expect(find.text('我的常去'), findsOneWidget,
        reason: '功能格里的「我的常去」与下方列表重复，已移除');
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded replies: sub TabBar sits below the host top '
      'inset instead of under the status bar', (tester) async {
    GlobalData().isLogin = true;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GetMaterialApp(
      home: MediaQuery(
        // 模拟 LiquidTopBarScaffold 覆下模式改写后的正文环境：
        // padding.top = 状态栏 24 + 玻璃顶栏 64 = 88。
        data: const MediaQueryData(
          size: Size(400, 800),
          padding: EdgeInsets.only(top: 88, bottom: 24),
          viewPadding: EdgeInsets.only(top: 24, bottom: 24),
        ),
        child: const Scaffold(
          body: FFFListPage(type: FFFListType.REPLY, embedded: true),
        ),
      ),
    ));
    await pumpBounded(tester);
    final tabBar = find.byType(TabBar);
    expect(tabBar, findsOneWidget);
    // 子 TabBar 落在玻璃分段栏下方（≥88），不再顶进状态栏。
    expect(tester.getTopLeft(tabBar).dy, greaterThanOrEqualTo(88 - 1));
    // 两个子页签都在场（真实切换功能保留）。
    expect(find.text('我收到的回复'), findsOneWidget);
    // 列表侧 MediaQuery 的 top 已清零，不再双倍顶距。
    final listMedia = tester
        .widgetList<MediaQuery>(find.descendant(
            of: find.byType(FFFListPage),
            matching: find.byType(MediaQuery)))
        .where((m) => m.data.padding.top == 0);
    expect(listMedia, isNotEmpty,
        reason: 'TabBar 已吃掉 inset，列表不应再按 padding.top 加顶距');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('messages page: switching to 我的回复 keeps the sub '
      'TabBar below the glass segment bar (dark too)', (tester) async {
    GlobalData().isLogin = true;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(GetMaterialApp(
        theme: ThemeData(brightness: brightness),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.only(top: 24, bottom: 24),
            viewPadding: EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: const MessagesPage(),
        ),
      ));
      await pumpBounded(tester);
      await tester.tap(find.text('我的回复').first);
      await pumpBounded(tester);
      final tabBar = find.byType(TabBar);
      expect(tabBar, findsOneWidget,
          reason: '子 TabBar 应在场（$brightness）');
      // 顶栏 inset = 状态栏 24 + 顶栏高 64 = 88：子 TabBar 必须在其下，
      // 与状态栏时钟/图标零重叠。
      expect(tester.getTopLeft(tabBar).dy, greaterThanOrEqualTo(88 - 1),
          reason: '子 TabBar 不得顶进状态栏（$brightness）');
      expect(find.text('我收到的回复'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('backdrop capture degrades only while in motion',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: LiquidTopBarScaffold(
        title: Text('标题'),
        body: Text('正文'),
      ),
    ));
    await tester.pump();
    final layer = tester.widget<BackdropLayer>(find.byType(BackdropLayer));
    // 静止捕获分辨率不设限（全分辨率、观感零变化）；只有连帧运动
    // （滚动）时降到 dpr 的一半（像素数 1/4），停下自动全分辨率重捕。
    expect(layer.pixelRatio, isNull);
    expect(layer.motionPixelRatio, 0.5,
        reason: '测试 dpr=1，motionPixelRatio 应为 dpr×0.5');
    expect(tester.takeException(), isNull);
  });

  test('follow page recording uses the same motion degradation (pin)',
      () {
    final follow =
        File('lib/pages/local_follow/local_follow_page.dart')
            .readAsStringSync();
    expect(follow, contains('motionPixelRatio'));
    final topBar =
        File('lib/components/liquid_top_bar.dart').readAsStringSync();
    expect(topBar, contains('motionPixelRatio: media.devicePixelRatio * 0.5'));
  });
}
