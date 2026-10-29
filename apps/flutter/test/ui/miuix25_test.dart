import 'dart:io';

import 'package:c001apk_flutter/components/basic_glass.dart' as basic;
import 'package:c001apk_flutter/components/glass_surface.dart';
import 'package:c001apk_flutter/components/liquid_navigation_bar.dart';
import 'package:c001apk_flutter/components/liquid_top_bar.dart';
import 'package:c001apk_flutter/components/page_backdrop_scope.dart';
import 'package:c001apk_flutter/components/cards/message_header_card.dart';
import 'package:c001apk_flutter/pages/message/message_page.dart';
import 'package:c001apk_flutter/pages/message/messages_page.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:get/get.dart' show GetMaterialApp;
import 'package:fluid_glass/fluid_glass.dart'
    show BackdropLayer, LayerBackdrop;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// miuix25 钉子：①顶栏药丸与底栏药丸共用同一份光学/弹簧定义
/// （DockPillGlass，值 = fluid_glass 0.5.3 的 LiquidBottomTabs
/// 药丸基线）；②主页面玻璃录制去重——每页只剩一套录制，Dock 与
/// 顶栏同为该录制子树外的消费者（PageBackdropRegistry）。
void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('miuix25-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  setUp(() async {
    await GStorage.settings.clear();
  });

  test('dock pill shared definition matches the Kyant baseline values', () {
    // fluid_glass 0.5.3 LiquidBottomTabs 药丸：静止透镜为 0、按下
    // lens(10, 14, 色散开)；中性纱 α.10×(1−p) + 压暗 α.03×p；
    // 内阴影半径 8×p；按压放大 78/56；模糊与面板同值 8。
    expect(DockPillGlass.lensBand, 10);
    expect(DockPillGlass.lensAmount, 14);
    expect(DockPillGlass.lensChromaticAberration, isTrue);
    expect(DockPillGlass.restTintAlpha, 0.10);
    expect(DockPillGlass.pressShadeAlpha, 0.03);
    expect(DockPillGlass.innerShadowRadius, 8);
    expect(DockPillGlass.pressedScale, 78 / 56);
    expect(DockPillGlass.blurRadius, fluidGlassBlurRadius);
    // 弹簧组（DampedDragAnimation springOf(ζ, k)）。
    expect(DockPillGlass.valueZeta, 1.0);
    expect(DockPillGlass.valueStiffness, 1000);
    expect(DockPillGlass.pressZeta, 1.0);
    expect(DockPillGlass.pressStiffness, 1000);
    expect(DockPillGlass.velocityZeta, 0.5);
    expect(DockPillGlass.velocityStiffness, 300);
    expect(DockPillGlass.scaleXZeta, 0.6);
    expect(DockPillGlass.scaleXStiffness, 250);
    expect(DockPillGlass.scaleYZeta, 0.7);
    expect(DockPillGlass.scaleYStiffness, 250);
    // 静止态透镜恒为 0（带宽/量都乘 pressProgress）。
    const rest = 0.0;
    expect(DockPillGlass.lensBand * rest, 0);
    expect(DockPillGlass.lensAmount * rest, 0);
  });

  test('shared spring integrates and settles like the dock spring', () {
    final spring = DockSpring(
        DockPillGlass.valueZeta, DockPillGlass.valueStiffness, 0)
      ..target = 3;
    for (var i = 0; i < 480 && !spring.settled(0.0012, 0.01); i++) {
      spring.step(1 / 240);
    }
    expect(spring.settled(0.0012, 0.01), isTrue);
    expect(spring.value, closeTo(3, 0.01));
  });

  test('dock and top pill both read the shared definition (source pin)',
      () {
    final dock =
        File('lib/components/floating_dock_bar.dart').readAsStringSync();
    final basicGlass =
        File('lib/components/basic_glass.dart').readAsStringSync();
    // 底栏回落药丸：透镜/弹簧/纱 alpha 全部经共享常量，不留手抄值。
    expect(dock, contains('DockPillGlass.lensBand'));
    expect(dock, contains('DockPillGlass.restTintAlpha'));
    expect(dock, contains('DockPillGlass.pressShadeAlpha'));
    expect(dock, contains('DockPillGlass.valueZeta'));
    expect(dock, contains('DockPillGlass.scaleXZeta'));
    // 顶栏药丸：DockStylePill + 同一组弹簧常量。
    expect(basicGlass, contains('DockStylePill('));
    expect(basicGlass, contains('DockPillGlass.lensBand'));
    expect(basicGlass, contains('DockPillGlass.valueZeta'));
    expect(basicGlass, contains('DockPillGlass.velocityZeta'));
    // 顶栏药丸旧蓝纱不得回归：navigationLens 的 α.55 覆写路径不再
    // 被导航栏使用（药丸 key 只挂在 DockStylePill 上）。
    expect(basicGlass, contains("'liquid-tabs-pill'"));
  });

  test('main page no longer records the whole PageView for the dock', () {
    final mainPage =
        File('lib/pages/main/main_page.dart').readAsStringSync();
    expect(mainPage, isNot(contains('BackdropLayer(')),
        reason: 'MainPage 整页录制已删，去重后每页只录自己那套');
    expect(mainPage, contains('PageBackdropScope('));
    expect(mainPage, contains('_pageBackdrops.activeBackdrop'));
  });

  testWidgets('top pill is the shared dock-style pill and springs on tap',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LiquidNavigationBar.tabs(
          labels: const ['甲', '乙', '丙'],
          selectedIndex: 0,
          onDestinationSelected: selected.add,
        ),
      ),
    ));
    await tester.pump();
    final pill = find.byKey(const ValueKey('liquid-tabs-pill'));
    expect(pill, findsOneWidget);
    final pillWidget = tester.widget<basic.DockStylePill>(pill);
    // 静止态：按压进度 0 → 透镜/高光/阴影按共享定义全为 0。
    expect(pillWidget.pressProgress, 0);
    final startCenter = tester.getCenter(pill);
    // 点第三段：回调立即到，药丸走弹簧（不是瞬移也不是匀速补间）：
    // 50ms 后应已离开起点但还没到终点，静置后精确吸附到第三段中心。
    await tester.tap(find.text('丙'));
    expect(selected, [2]);
    // 弹簧 Ticker 首帧只记时刻（与底栏同一实现），两帧后应已在途中。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final midCenter = tester.getCenter(pill);
    expect(midCenter.dx, greaterThan(startCenter.dx + 4));
    await tester.pumpAndSettle();
    final barRect = tester.getRect(find.byType(LiquidNavigationBar));
    final slot = barRect.width / 3;
    expect(tester.getCenter(pill).dx,
        closeTo(barRect.left + slot * 2.5, 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('top pill drag springs back when released before halfway',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LiquidNavigationBar.tabs(
          labels: const ['甲', '乙', '丙'],
          selectedIndex: 0,
          onDestinationSelected: selected.add,
        ),
      ),
    ));
    await tester.pump();
    final pill = find.byKey(const ValueKey('liquid-tabs-pill'));
    final startCenter = tester.getCenter(pill);
    final barRect = tester.getRect(find.byType(LiquidNavigationBar));
    final slot = barRect.width / 3;
    // 拖动量 < 半槽：药丸跟指移动，松手吸附回第一段、回调仍报 0。
    await tester.dragFrom(startCenter, Offset(slot * 0.3, 0));
    await tester.pumpAndSettle();
    expect(selected.last, 0);
    expect(tester.getCenter(pill).dx, closeTo(startCenter.dx, 2));
    expect(tester.takeException(), isNull);
  });

  test('page backdrop registry publishes one recording per page', () {
    final registry = PageBackdropRegistry();
    final a = LayerBackdrop();
    final b = LayerBackdrop();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    expect(registry.activeBackdrop, isNull);
    registry.register(0, a);
    registry.register(1, b);
    expect(registry.registeredCount, 2);
    expect(registry.activeBackdrop, same(a));
    registry.setActive(1);
    expect(registry.activeBackdrop, same(b));
    registry.unregister(1, b);
    expect(registry.activeBackdrop, isNull);
    registry.dispose();
  });

  testWidgets('scaffold records its body once and registers it',
      (tester) async {
    final registry = PageBackdropRegistry();
    addTearDown(registry.dispose);
    await tester.pumpWidget(MaterialApp(
      home: PageBackdropScope(
        registry: registry,
        child: const LiquidTopBarScaffold(
          backdropIndex: 0,
          title: Text('标题'),
          body: Text('正文'),
        ),
      ),
    ));
    await tester.pump();
    // 一页恰一套录制（miuix24 时该页正文录制 + MainPage 整页录制
    // 两套并行；MainPage 那套已删，见源码钉子）。
    expect(find.byType(BackdropLayer), findsOneWidget);
    expect(registry.registeredCount, 1);
    expect(registry.activeBackdrop, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('messages page: no white board under the top bar',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GetMaterialApp(home: MessagesPage()));
    await tester.pumpAndSettle();
    // 与主页/关注同构：正文覆下（overlayBody）、滚动视口顶到 y=0，
    // 内容从玻璃顶栏之下穿过；首张通知卡仍落在顶栏下方原位——
    // 本 harness 状态栏 inset 为 0，顶栏高 64：通知列表的
    // SliverPadding 顶 = 64 + 10，卡内文字应在其下（≥74）。
    final scaffold = tester.widget<LiquidTopBarScaffold>(
        find.byType(LiquidTopBarScaffold));
    expect(scaffold.overlayBody, isTrue);
    expect(tester.getTopLeft(find.byType(CustomScrollView)).dy, 0);
    final sliverPadding = tester
        .widgetList<SliverPadding>(find.byType(SliverPadding))
        .map((w) => (w.padding as EdgeInsets).top)
        .fold<double>(0, (a, b) => a > b ? a : b);
    expect(sliverPadding, 74);
    expect(tester.getTopLeft(find.text('@我的动态')).dy,
        greaterThanOrEqualTo(74));
    expect(tester.takeException(), isNull);
  });

  testWidgets('my page: no white board, profile card keeps its place',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GetMaterialApp(home: MessagePage()));
    await tester.pumpAndSettle();
    final scaffold = tester.widget<LiquidTopBarScaffold>(
        find.byType(LiquidTopBarScaffold));
    expect(scaffold.overlayBody, isTrue);
    // 滚动视口顶到 y=0（内容覆到顶栏之下），资料卡仍悬浮在顶栏
    // 下方原位：置顶头顶部 padding = inset 64 + 10 = 74 起。
    expect(tester.getTopLeft(find.byType(CustomScrollView)).dy, 0);
    expect(
        tester.getTopLeft(find.byType(basic.LiquidGlassPanel)).dy,
        greaterThanOrEqualTo(74 - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('messages and my page: same structure in dark mode',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dark = ThemeData(brightness: Brightness.dark);
    // 深色下同理无顶板：正文覆下、视口顶到 0、AppBar 透明。
    await tester.pumpWidget(
        GetMaterialApp(theme: dark, home: const MessagesPage()));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LiquidTopBarScaffold>(
                find.byType(LiquidTopBarScaffold))
            .overlayBody,
        isTrue);
    expect(tester.getTopLeft(find.byType(CustomScrollView)).dy, 0);
    final messagesBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(messagesBar.backgroundColor, Colors.transparent);
    expect(messagesBar.forceMaterialTransparency, isTrue);
    await tester.pumpWidget(
        GetMaterialApp(theme: dark, home: const MessagePage()));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LiquidTopBarScaffold>(
                find.byType(LiquidTopBarScaffold))
            .overlayBody,
        isTrue);
    expect(tester.getTopLeft(find.byType(CustomScrollView)).dy, 0);
    final myBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(myBar.backgroundColor, Colors.transparent);
    expect(myBar.forceMaterialTransparency, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('my page: title and actions are glass, header has no board',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GetMaterialApp(home: MessagePage()));
    await tester.pumpAndSettle();
    // 标题「我的」坐在 LiquidGlassButton 玻璃片里（与关注页标题
    // 同款），不再是裸文字；右上两圆钮同为 LiquidGlassButton。
    expect(
        find.descendant(
            of: find.byType(LiquidGlassButton), matching: find.text('我的')),
        findsWidgets);
    expect(find.byType(LiquidGlassButton), findsAtLeast(3),
        reason: '标题片 + 账号管理 + 设置，三者同玻璃语言');
    // 资料卡头的底板在玻璃模式下透明（无不透明白/黑板垫在顶区）：
    // 取 MessageHeaderCard 最近的 ColoredBox 祖先即那块头底板。
    final headerBoxes = tester.widgetList<ColoredBox>(find.ancestor(
        of: find.byType(MessageHeaderCard),
        matching: find.byType(ColoredBox)));
    expect(headerBoxes.first.color, Colors.transparent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external backdrop: scaffold adds no second recording',
      (tester) async {
    final registry = PageBackdropRegistry();
    addTearDown(registry.dispose);
    final external = LayerBackdrop();
    addTearDown(external.dispose);
    await tester.pumpWidget(MaterialApp(
      home: PageBackdropScope(
        registry: registry,
        child: LiquidTopBarScaffold(
          backdropIndex: 1,
          externalBackdrop: external,
          title: const Text('标题'),
          body: BackdropLayer(
            backdrop: external,
            child: const Text('正文'),
          ),
        ),
      ),
    ));
    await tester.pump();
    // 关注页形态：正文内部录制是唯一一套，顶栏与 Dock 都采样它。
    expect(find.byType(BackdropLayer), findsOneWidget);
    registry.setActive(1);
    expect(registry.activeBackdrop, same(external));
    expect(tester.takeException(), isNull);
  });
}
