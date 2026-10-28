import 'dart:io';

import 'package:c001apk_flutter/components/floating_dock_bar.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// miuix13 窄幅悬浮 Dock 的规格断言（用户看图拍板的效果图为验收标准）：
/// 水平居中、高 68dp 胶囊、选中项竖排图标+文字、未选中无文字；
/// 玻璃材质三档（毛玻璃/磨砂/液态）的参数映射与设置持久化。
/// 宽度口径 miuix19 改为按 Tab 数定宽（见 barWidthForTabCount），
/// 取代 miuix13–18 的固定屏宽 58%。
void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-dock-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
  });
  setUp(() async {
    await GStorage.settings.clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  Future<void> pumpDock(
    WidgetTester tester, {
    required int selectedIndex,
    required Brightness brightness,
    DockGlassMaterial material = DockGlassMaterial.frosted,
    bool useOverride = true,
    ValueChanged<int>? onTap,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        bottomNavigationBar: FloatingDockBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onTap ?? (_) {},
          materialOverride: useOverride ? material : null,
        ),
        body: const SizedBox.expand(),
      ),
    ));
    await tester.pump();
  }

  testWidgets('capsule width follows tab count, centered, 68dp high',
      (tester) async {
    await pumpDock(tester, selectedIndex: 0, brightness: Brightness.dark);
    final capsule = find.byKey(const Key('floatingDockCapsule'));
    expect(capsule, findsOneWidget);
    final size = tester.getSize(capsule);
    // miuix19 新口径：总宽 = Tab 数 × 单槽宽 + 两侧内距；miuix23
    // 四 Tab = 4×76 + 2×6 = 316（未触 320 上限与屏宽 −32 封顶）。
    expect(size.width, FloatingDockBar.barWidthForTabCount(4, 400));
    expect(size.width,
        4 * FloatingDockBar.slotWidth + 2 * FloatingDockBar.sidePadding);
    expect(size.width, lessThanOrEqualTo(400 - 32));
    expect(size.height, FloatingDockBar.height);
    expect(tester.getCenter(capsule).dx, closeTo(200, 0.5));
    // 真玻璃：fluid DrawBackdrop 在场（miuix22 起胶囊面与全应用
    // 玻璃面同为 fluid 引擎；药丸在静止/无 program 时不出滤镜）
    expect(find.byType(DrawBackdrop), findsOneWidget);
  });

  group('bar width formula', () {
    test('width grows with tab count and is capped', () {
      expect(FloatingDockBar.barWidthForTabCount(2, 400), 164);
      // 4 Tab：4×76+12 = 316，未触上限——旧 58% 下同屏宽仅 238，
      // 单槽被压到约 60dp 正是贴吧「太挤」的来源。
      expect(FloatingDockBar.barWidthForTabCount(4, 411), 316);
      // 5 Tab 触绝对上限 320。
      expect(FloatingDockBar.barWidthForTabCount(5, 411),
          FloatingDockBar.maxBarWidth);
      // 窄屏以屏宽 −32 封顶。
      expect(FloatingDockBar.barWidthForTabCount(4, 300), 268);
      expect(FloatingDockBar.barWidthForTabCount(2, 300), 164);
    });
  });

  testWidgets('selected shows icon over label, unselected icon only',
      (tester) async {
    await pumpDock(tester, selectedIndex: 0, brightness: Brightness.dark);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('我的'), findsNothing);
    final label = tester.getRect(find.text('首页'));
    final icon = tester.getRect(find.byIcon(Icons.home));
    expect(icon.bottom, lessThanOrEqualTo(label.top + 2));
    expect(icon.center.dx, closeTo(label.center.dx, 24));

    await pumpDock(tester, selectedIndex: 3, brightness: Brightness.dark);
    // miuix15：选中态由药丸弹簧位置连续驱动，切换后等弹簧到位再断言终态。
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('首页'), findsNothing);
  });

  testWidgets('tapping slots reports their indices', (tester) async {
    final tapped = <int>[];
    await pumpDock(tester,
        selectedIndex: 0, brightness: Brightness.dark, onTap: tapped.add);
    final rect = tester.getRect(find.byKey(const Key('floatingDockCapsule')));
    await tester.tapAt(Offset(rect.left + rect.width * 0.875, rect.center.dy));
    await tester.tapAt(Offset(rect.left + rect.width * 0.125, rect.center.dy));
    expect(tapped, [3, 0]);
  });

  testWidgets('light mode renders with label and icons', (tester) async {
    await pumpDock(tester, selectedIndex: 3, brightness: Brightness.light);
    expect(find.text('我的'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });

  testWidgets('all three glass materials render', (tester) async {
    for (final material in DockGlassMaterial.values) {
      await pumpDock(tester,
          selectedIndex: 0, brightness: Brightness.dark, material: material);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('floatingDockCapsule')), findsOneWidget,
          reason: '$material 应渲染出胶囊');
      expect(tester.takeException(), isNull, reason: '$material 不应抛异常');
    }
  });

  group('miuix15 draggable lens dock', () {
    final pillFinder = find.byKey(const Key('floatingDockPill'));

    Future<void> pumpFrames(WidgetTester tester, int frames) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<TestGesture> dragBy(
        WidgetTester tester, Offset start, double dx, int steps) async {
      final gesture = await tester.startGesture(start);
      final stepDx = dx / steps;
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(Offset(stepDx, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      return gesture;
    }

    testWidgets('drag past midpoint switches only on release', (tester) async {
      final tapped = <int>[];
      await pumpDock(tester,
          selectedIndex: 0, brightness: Brightness.dark, onTap: tapped.add);
      final rect = tester.getRect(find.byKey(const Key('floatingDockCapsule')));
      // 槽宽 76（miuix19 公式）；指距 100px（手势检测吃掉约一个 slop
      // 后仍约 1.1 槽，过中点）。
      final gesture = await dragBy(tester,
          Offset(rect.left + rect.width * 0.25, rect.center.dy), 100, 10);
      expect(tapped, isEmpty, reason: '拖动中不得触发切换');
      await gesture.up();
      await pumpFrames(tester, 45);
      expect(tapped, [1], reason: '松手吸附到最近索引并切换');
    });

    testWidgets('drag below midpoint springs back without switching',
        (tester) async {
      final tapped = <int>[];
      await pumpDock(tester,
          selectedIndex: 0, brightness: Brightness.dark, onTap: tapped.add);
      final rect = tester.getRect(find.byKey(const Key('floatingDockCapsule')));
      final restCenter = tester.getCenter(pillFinder).dx;
      final gesture = await dragBy(
          tester, Offset(rect.left + rect.width * 0.25, rect.center.dy), 30, 3);
      await gesture.up();
      await pumpFrames(tester, 45);
      expect(tapped, isEmpty, reason: '未过中点松手应弹回、不切换');
      expect(tester.getCenter(pillFinder).dx, closeTo(restCenter, 2),
          reason: '药丸应弹回原槽中心');
    });

    testWidgets('pill position follows with spring lag and converges',
        (tester) async {
      await pumpDock(tester, selectedIndex: 0, brightness: Brightness.dark);
      final rect = tester.getRect(find.byKey(const Key('floatingDockCapsule')));
      // 槽 1 中心 = 左缘 + 内距 + 1.5 槽宽（miuix19 公式几何）。
      final slot1Center = rect.left +
          FloatingDockBar.sidePadding +
          FloatingDockBar.slotWidth * 1.5;
      await tester.tapAt(Offset(slot1Center, rect.center.dy));
      final samples = <double>[];
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        samples.add(tester.getCenter(pillFinder).dx);
      }
      // 弹簧跟随：不瞬移（首帧仍未过中点）、单调趋近、终点收敛到槽 1 中心。
      expect(samples.first, lessThan(rect.center.dx),
          reason: '点按后药丸应从原位弹簧滑出而非瞬移');
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], greaterThanOrEqualTo(samples[i - 1] - 0.6),
            reason: '临界阻尼跟随应单调不回摆（帧 $i）');
      }
      expect(samples.last, closeTo(slot1Center, 2.5));
    });

    testWidgets('pressing the pill scales it up beyond rest size',
        (tester) async {
      await pumpDock(tester, selectedIndex: 0, brightness: Brightness.dark);
      final restSize = tester.getRect(pillFinder).size;
      final center = tester.getCenter(pillFinder);
      final gesture = await tester.startGesture(center);
      await pumpFrames(tester, 25);
      final pressedSize = tester.getRect(pillFinder).size;
      expect(pressedSize.width, greaterThan(restSize.width * 1.2),
          reason: '按压时药丸应向 pressedScale=78/56 膨胀');
      await gesture.up();
      await pumpFrames(tester, 45);
      expect(tester.getRect(pillFinder).width, closeTo(restSize.width, 2),
          reason: '松手后药丸应缩回静止尺寸');
    });

    testWidgets('drag switching works without the refraction shader',
        (tester) async {
      // 测试环境无可用 shader（三档都走无透镜回退路径），拖动行为必须一致。
      for (final material in [
        DockGlassMaterial.clear,
        DockGlassMaterial.frosted,
        DockGlassMaterial.liquid,
      ]) {
        final tapped = <int>[];
        // 每档材质卸载重挂，避免上一档的拖动态（_targetValue）残留。
        await tester.pumpWidget(const SizedBox());
        await pumpDock(tester,
            selectedIndex: 0,
            brightness: Brightness.dark,
            material: material,
            onTap: tapped.add);
        final rect =
            tester.getRect(find.byKey(const Key('floatingDockCapsule')));
        final gesture = await dragBy(tester,
            Offset(rect.left + rect.width * 0.25, rect.center.dy), 100, 10);
        expect(tapped, isEmpty, reason: '$material 拖动中不切换');
        await gesture.up();
        await pumpFrames(tester, 45);
        expect(tapped, [1], reason: '$material 松手后应切换');
        expect(tester.takeException(), isNull, reason: '$material 不应抛异常');
      }
    });
  });

  group('glass material mapping', () {
    test('storage values map with frosted as default', () {
      expect(DockGlassMaterial.fromStorage(null), DockGlassMaterial.frosted);
      expect(DockGlassMaterial.fromStorage(0), DockGlassMaterial.clear);
      expect(DockGlassMaterial.fromStorage(1), DockGlassMaterial.frosted);
      expect(DockGlassMaterial.fromStorage(2), DockGlassMaterial.liquid);
      expect(DockGlassMaterial.fromStorage(99), DockGlassMaterial.frosted);
      expect(DockGlassMaterial.fromStorage('x'), DockGlassMaterial.frosted);
    });

    test('specs follow the recipes', () {
      // miuix16 按「身份」重新拉开三档（miuix14 的 Kyant 校准在真机上
      // 三档几乎看不出区别，小乐反馈）：毛=最清透（模糊最轻/饱和最高/
      // 纱最薄/高光最亮）、磨砂=最哑光（模糊最重/纱最厚/饱和最低/透镜
      // 最弱）、液态=透镜最强（Kyant 24/24 + 色散）。三档底栏本体都带
      // circleMap 透镜（miuix16 起），深色纱基色仍一律 #121212。
      final clear = DockGlassMaterial.clear.spec;
      expect(clear.sigma, 6);
      expect(clear.saturate, 1.8);
      expect(clear.refraction, isTrue);
      expect(clear.refractionBandDp, 16);
      expect(clear.refractionAmountDp, 10);
      expect(clear.dispersion, 0);
      expect(clear.tintAlphaDark, 0.16);
      expect(clear.tintAlphaLight, 0.18);
      expect(clear.highlightAlphaDark, 0.60);
      expect(clear.highlightAlphaLight, 0.95);

      final frosted = DockGlassMaterial.frosted.spec;
      expect(frosted.sigma, 20);
      expect(frosted.saturate, 1.3);
      expect(frosted.refraction, isTrue);
      expect(frosted.refractionBandDp, 20);
      expect(frosted.refractionAmountDp, 6);
      expect(frosted.dispersion, 0);
      expect(frosted.tintAlphaDark, 0.55);
      expect(frosted.tintAlphaLight, 0.58);
      expect(frosted.highlightAlphaDark, 0.12);
      expect(frosted.highlightAlphaLight, 0.30);

      final liquid = DockGlassMaterial.liquid.spec;
      expect(liquid.sigma, 8);
      expect(liquid.saturate, 1.5);
      expect(liquid.refraction, isTrue);
      expect(liquid.refractionBandDp, 24);
      expect(liquid.refractionAmountDp, 24);
      expect(liquid.dispersion, 0.2);
      expect(liquid.tintAlphaDark, 0.32);
      expect(liquid.tintAlphaLight, 0.32);
      expect(glassTintColor(liquid, true),
          const Color(0xFF121212).withValues(alpha: 0.32));
      expect(glassTintColor(liquid, false),
          const Color(0xFFFAFAFA).withValues(alpha: 0.32));

      // 身份排序：并排一眼可辨的每条轴都不许交叉或并列。
      expect(clear.sigma, lessThan(liquid.sigma));
      expect(liquid.sigma, lessThan(frosted.sigma));
      expect(clear.saturate, greaterThan(liquid.saturate));
      expect(liquid.saturate, greaterThan(frosted.saturate));
      expect(clear.tintAlphaDark, lessThan(liquid.tintAlphaDark));
      expect(liquid.tintAlphaDark, lessThan(frosted.tintAlphaDark));
      expect(clear.tintAlphaLight, lessThan(liquid.tintAlphaLight));
      expect(liquid.tintAlphaLight, lessThan(frosted.tintAlphaLight));
      expect(clear.highlightAlphaDark, greaterThan(liquid.highlightAlphaDark));
      expect(
          liquid.highlightAlphaDark, greaterThan(frosted.highlightAlphaDark));
      expect(frosted.refractionAmountDp, lessThan(clear.refractionAmountDp));
      expect(clear.refractionAmountDp, lessThan(liquid.refractionAmountDp));
      expect(liquid.dispersion, greaterThan(0));
      // 深色模式三档一律深纱（121212），不再是乳白色
      for (final m in DockGlassMaterial.values) {
        final c = glassTintColor(m.spec, true);
        expect(c.r, const Color(0xFF121212).r, reason: '$m 深色纱应为 121212');
        expect(c.g, const Color(0xFF121212).g);
        expect(c.b, const Color(0xFF121212).b);
      }
      // 液态的边缘描边最亮；液态透镜常量仍 = Kyant lens 的 24/24dp
      expect(liquid.borderAlphaDark,
          greaterThan(DockGlassMaterial.frosted.spec.borderAlphaDark));
      expect(glassRefractionBandDp, 24);
      expect(glassRefractionAmountDp, 24);
      expect(liquid.refractionBandDp, glassRefractionBandDp);
      expect(liquid.refractionAmountDp, glassRefractionAmountDp);
    });

    test('saturation matrix is identity at 1.0', () {
      final m = dockSaturationMatrix(1.0);
      expect(m[0], closeTo(1, 1e-9));
      expect(m[6], closeTo(1, 1e-9));
      expect(m[12], closeTo(1, 1e-9));
      expect(m[1], closeTo(0, 1e-9));
    });
  });

  group('setting persistence', () {
    test('dock glass material round-trips through the settings box', () async {
      expect(
          DockGlassMaterial.fromStorage(
              GStorage.settings.get(SettingsBoxKey.dockGlassMaterial)),
          DockGlassMaterial.frosted,
          reason: '未设置时默认磨砂');
      await GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, 2);
      expect(
          DockGlassMaterial.fromStorage(
              GStorage.settings.get(SettingsBoxKey.dockGlassMaterial)),
          DockGlassMaterial.liquid);
      await GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, 0);
      expect(
          DockGlassMaterial.fromStorage(
              GStorage.settings.get(SettingsBoxKey.dockGlassMaterial)),
          DockGlassMaterial.clear);
    });

    testWidgets('dock without override follows the stored material',
        (tester) async {
      // Hive 写盘是真 IO，必须在 runAsync 里做（FakeAsync 区里直接 await 会死锁）。
      await tester.runAsync(
          () => GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, 0));
      await pumpDock(tester,
          selectedIndex: 0, brightness: Brightness.dark, useOverride: false);
      expect(find.byKey(const Key('floatingDockCapsule')), findsOneWidget);
      // 切换设置后 listenable 触发重建，不重启也生效、不抛异常
      await tester.runAsync(
          () => GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('floatingDockCapsule')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching the stored material changes the live tint',
        (tester) async {
      // miuix16 链路审计（小乐真机反馈「切换三种玻璃没什么区别」）：
      // 设置存储 → listenable → Dock 重建 → 实际生效的玻璃参数。
      // miuix22：胶囊面换 fluid DrawBackdrop 后，光学在引擎内写死、
      // 树上可观测的活参数只剩经唯一映射点 dockGlassColorsForSpec
      // 注入子树的 LiquidGlassColors（container=纱色）——逐档切换
      // 存储值，断言子树里的 container 逐档等于新 spec 的纱色且
      // 两两不同；映射函数本身另有纯函数组钉住（见下方 fluid 组）。
      Future<void> store(int v) => tester.runAsync(
          () => GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, v));

      Color captureTint() {
        final themeWidget = tester.widget<LiquidGlassTheme>(
          find
              .descendant(
                of: find.byKey(const Key('floatingDockCapsule')),
                matching: find.byType(LiquidGlassTheme),
              )
              .first,
        );
        return themeWidget.colors.container;
      }

      await store(0);
      await pumpDock(tester,
          selectedIndex: 0, brightness: Brightness.dark, useOverride: false);
      final clearTint = captureTint();
      expect(clearTint, glassTintColor(DockGlassMaterial.clear.spec, true));

      await store(2);
      await tester.pump(const Duration(milliseconds: 300));
      final liquidTint = captureTint();
      expect(liquidTint, glassTintColor(DockGlassMaterial.liquid.spec, true));
      expect(liquidTint, isNot(equals(clearTint)));

      await store(1);
      await tester.pump(const Duration(milliseconds: 300));
      final frostedTint = captureTint();
      expect(frostedTint, glassTintColor(DockGlassMaterial.frosted.spec, true));
      expect(frostedTint, isNot(equals(liquidTint)));
      expect(frostedTint, isNot(equals(clearTint)));
      expect(tester.takeException(), isNull);
    });
  });

  group('fluid glass kyant dock spike', () {
    test('spec maps into LiquidGlassColors through tint and accent only', () {
      // Kyant 组件的光学参数（blur/vibrancy/lens/色散）在组件内写死，
      // spec 只能经颜色进组件：container = glassTintColor（纱色+透明度，
      // 三预设身份经此可辨）、accent 原样透传。映射函数单独钉住，
      // 防止日后有人把字段静默吞掉。
      const accent = Color(0xFF3366FF);
      for (final material in DockGlassMaterial.values) {
        final colors =
            dockGlassColorsForSpec(material.spec, dark: true, accent: accent);
        expect(colors.accent, accent);
        expect(colors.container, glassTintColor(material.spec, true));
        final light =
            dockGlassColorsForSpec(material.spec, dark: false, accent: accent);
        expect(light.container, glassTintColor(material.spec, false));
      }
      // 三预设的 container 必须两两不同（Kyant 路上预设只剩纱色深浅
      // 一条身份线，连这条都丢了就是映射坏了）。
      final darkTints = DockGlassMaterial.values
          .map((m) => dockGlassColorsForSpec(m.spec, dark: true, accent: accent)
              .container)
          .toSet();
      expect(darkTints, hasLength(DockGlassMaterial.values.length));
    });

    test('unmapped LiquidGlassColors fields keep the library defaults', () {
      // content/track 等非映射字段必须等于库的明暗默认——映射函数只许
      // 动 accent 与 container。
      const accent = Color(0xFF3366FF);
      final colors = dockGlassColorsForSpec(DockGlassMaterial.frosted.spec,
          dark: true, accent: accent);
      final defaults = LiquidGlassColors.forBrightness(Brightness.dark);
      expect(colors.content, defaults.content);
      expect(colors.track, defaults.track);
      expect(colors.toggleAccent, defaults.toggleAccent);
      expect(colors.destructive, defaults.destructive);
      final lightColors = dockGlassColorsForSpec(DockGlassMaterial.frosted.spec,
          dark: false, accent: accent);
      final lightDefaults = LiquidGlassColors.forBrightness(Brightness.light);
      expect(lightColors.content, lightDefaults.content);
      expect(lightColors.track, lightDefaults.track);
    });

    testWidgets(
        'injected page backdrop still falls back without runtime shaders',
        (tester) async {
      // 测试环境无运行时 shader：即便主页注入了页面录制，Dock 也必须
      // 整栏回落现 Dock（几何/点按一致、不抛异常、LiquidBottomTabs
      // 不出现；胶囊面本身与全应用同为 fluid DrawBackdrop 出图）。
      // Kyant 路只能在真机 Impeller 上目视，本测试钉住回落门。
      final tapped = <int>[];
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backdrop = LayerBackdrop();
      addTearDown(backdrop.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          bottomNavigationBar: FloatingDockBar(
            selectedIndex: 0,
            onDestinationSelected: tapped.add,
            materialOverride: DockGlassMaterial.liquid,
            pageBackdrop: backdrop,
          ),
          body: BackdropLayer(
            backdrop: backdrop,
            child: const SizedBox.expand(),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(LiquidBottomTabs), findsNothing);
      final capsule = find.byKey(const Key('floatingDockCapsule'));
      expect(capsule, findsOneWidget);
      expect(
        find.descendant(of: capsule, matching: find.byType(DrawBackdrop)),
        findsOneWidget,
        reason: '回落路胶囊面应为 fluid DrawBackdrop 出图',
      );
      final rect = tester.getRect(capsule);
      expect(rect.width, FloatingDockBar.barWidthForTabCount(4, 400));
      expect(rect.height, FloatingDockBar.height);
      await tester.tapAt(Offset(rect.left + rect.width * 0.375, rect.center.dy));
      expect(tapped, [1]);
      expect(tester.takeException(), isNull);
    });
  });
}
