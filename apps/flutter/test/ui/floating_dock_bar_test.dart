import 'dart:io';
import 'dart:ui' as ui;

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
    // miuix19 新口径：总宽 = Tab 数 × 单槽宽 + 两侧内距
    // = 2×76 + 2×6 = 164，且必须小于旧固定 58% 口径（400×0.58=232，
    // 两个按钮摊那么宽是真机反馈「空/挤不合理」的来源）。
    expect(size.width, FloatingDockBar.barWidthForTabCount(2, 400));
    expect(size.width,
        2 * FloatingDockBar.slotWidth + 2 * FloatingDockBar.sidePadding);
    expect(size.width, lessThan(400 * FloatingDockBar.widthFactor));
    expect(size.height, FloatingDockBar.height);
    expect(tester.getCenter(capsule).dx, closeTo(200, 0.5));
    // 真毛玻璃：BackdropFilter 在场
    expect(find.byType(BackdropFilter), findsOneWidget);
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

    await pumpDock(tester, selectedIndex: 1, brightness: Brightness.dark);
    // miuix15：选中态由药丸弹簧位置连续驱动，切换后等弹簧到位再断言终态。
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('首页'), findsNothing);
  });

  testWidgets('tapping each half reports its index', (tester) async {
    final tapped = <int>[];
    await pumpDock(tester,
        selectedIndex: 0, brightness: Brightness.dark, onTap: tapped.add);
    final rect = tester.getRect(find.byKey(const Key('floatingDockCapsule')));
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.tapAt(Offset(rect.left + rect.width * 0.25, rect.center.dy));
    expect(tapped, [1, 0]);
  });

  testWidgets('light mode renders with label and icons', (tester) async {
    await pumpDock(tester, selectedIndex: 1, brightness: Brightness.light);
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

    testWidgets('switching the stored material changes the live filter',
        (tester) async {
      // miuix16 链路审计（小乐真机反馈「切换三种玻璃没什么区别」）：
      // 设置存储 → listenable → Dock 重建 → 实际挂到 BackdropFilter 上
      // 的 filter。逐档切换存储值，断言树上真实 filter 与纱色逐档等于
      // 新 spec 现算的结果——只断言规格表不同不算数。
      Future<void> store(int v) => tester.runAsync(
          () => GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, v));

      ({ui.ImageFilter filter, Color tint}) capture() {
        final filterWidget = tester.widget<BackdropFilter>(
          find
              .descendant(
                of: find.byKey(const Key('floatingDockCapsule')),
                matching: find.byType(BackdropFilter),
              )
              .first,
        );
        final tinted = filterWidget.child as Container;
        return (
          filter: filterWidget.filter!,
          tint: (tinted.decoration! as BoxDecoration).color!,
        );
      }

      ui.ImageFilter expectedFilter(DockGlassMaterial material) =>
          glassImageFilter(
            spec: material.spec,
            size: Size(FloatingDockBar.barWidthForTabCount(2, 400),
                FloatingDockBar.height),
            dpr: 1,
            refractionProgram: null,
            cornerRadii: BorderRadius.circular(FloatingDockBar.height / 2),
          );

      await store(0);
      await pumpDock(tester,
          selectedIndex: 0, brightness: Brightness.dark, useOverride: false);
      final clearShot = capture();
      expect(
          clearShot.tint, glassTintColor(DockGlassMaterial.clear.spec, true));
      expect(clearShot.filter, expectedFilter(DockGlassMaterial.clear));

      await store(2);
      await tester.pump(const Duration(milliseconds: 300));
      final liquidShot = capture();
      expect(
          liquidShot.tint, glassTintColor(DockGlassMaterial.liquid.spec, true));
      expect(liquidShot.filter, expectedFilter(DockGlassMaterial.liquid));
      expect(liquidShot.filter, isNot(equals(clearShot.filter)));

      await store(1);
      await tester.pump(const Duration(milliseconds: 300));
      final frostedShot = capture();
      expect(frostedShot.tint,
          glassTintColor(DockGlassMaterial.frosted.spec, true));
      expect(frostedShot.filter, expectedFilter(DockGlassMaterial.frosted));
      expect(frostedShot.filter, isNot(equals(liquidShot.filter)));
      expect(frostedShot.filter, isNot(equals(clearShot.filter)));
      expect(tester.takeException(), isNull);
    });
  });

  group('fluid glass dock spike', () {
    test(
        'sigma to fluid blur radius round-trips through the library conversion',
        () {
      // 本仓 sigma（直接喂 ImageFilter.blur）→ fluid blur() 的半径 →
      // 库自带 blurRadiusToSigma 必须还原同一个 sigma，否则三档模糊
      // 量在 fluid 引擎下会整体偏移。
      for (final sigma in [6.0, 8.0, 20.0, 30.0]) {
        for (final dpr in [1.0, 2.75]) {
          final radius = fluidBlurRadiusForSigma(sigma, dpr);
          expect(radius, greaterThan(0));
          expect(blurRadiusToSigma(radius, devicePixelRatio: dpr),
              closeTo(sigma, 1e-9));
        }
      }
      // sigma 0 钳 0（库内 blur 跳过）；色散开关只看 spec 正负。
      expect(fluidBlurRadiusForSigma(0, 2.75), 0);
      expect(fluidChromaticAberration(DockGlassMaterial.liquid.spec), isTrue);
      expect(fluidChromaticAberration(DockGlassMaterial.frosted.spec), isFalse);
      expect(fluidChromaticAberration(DockGlassMaterial.clear.spec), isFalse);
    });

    testWidgets(
        'injected page backdrop still falls back without runtime shaders',
        (tester) async {
      // 测试环境无运行时 shader：即便主页注入了页面录制，Dock 也必须
      // 整栏回落现引擎（BackdropFilter 出图、几何/点按一致、不抛异常）。
      // fluid 出图路径只能在真机 Impeller 上目视，本测试钉住回落门。
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
      final capsule = find.byKey(const Key('floatingDockCapsule'));
      expect(capsule, findsOneWidget);
      expect(
        find.descendant(of: capsule, matching: find.byType(BackdropFilter)),
        findsOneWidget,
        reason: '回落路径应仍是现引擎的 BackdropFilter 出图',
      );
      final rect = tester.getRect(capsule);
      expect(rect.width, FloatingDockBar.barWidthForTabCount(2, 400));
      expect(rect.height, FloatingDockBar.height);
      await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
      expect(tapped, [1]);
      expect(tester.takeException(), isNull);
    });
  });
}
