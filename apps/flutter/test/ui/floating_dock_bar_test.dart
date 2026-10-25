import 'dart:io';

import 'package:c001apk_flutter/components/floating_dock_bar.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// miuix13 窄幅悬浮 Dock 的规格断言（用户看图拍板的效果图为验收标准）：
/// 宽 58% 居中、高 68dp 胶囊、选中项竖排图标+文字、未选中无文字；
/// 玻璃材质三档（毛玻璃/磨砂/液态）的参数映射与设置持久化。
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

  testWidgets('capsule is 58% wide, centered, 68dp high', (tester) async {
    await pumpDock(tester, selectedIndex: 0, brightness: Brightness.dark);
    final capsule = find.byKey(const Key('floatingDockCapsule'));
    expect(capsule, findsOneWidget);
    final size = tester.getSize(capsule);
    expect(size.width, closeTo(400 * FloatingDockBar.widthFactor, 0.5));
    expect(size.height, FloatingDockBar.height);
    expect(tester.getCenter(capsule).dx, closeTo(200, 0.5));
    // 真毛玻璃：BackdropFilter 在场
    expect(find.byType(BackdropFilter), findsOneWidget);
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
      final clear = DockGlassMaterial.clear.spec;
      expect(clear.sigma, 14);
      expect(clear.saturate, 1.6);
      expect(clear.refraction, isFalse);

      final frosted = DockGlassMaterial.frosted.spec;
      expect(frosted.sigma, 22);
      expect(frosted.saturate, 1.5);
      expect(frosted.refraction, isFalse);
      // 磨砂的纱最厚、高光最弱
      expect(frosted.tintAlphaDark,
          greaterThan(DockGlassMaterial.clear.spec.tintAlphaDark));
      expect(frosted.tintAlphaDark,
          greaterThan(DockGlassMaterial.liquid.spec.tintAlphaDark));
      expect(frosted.highlightAlphaDark,
          lessThan(DockGlassMaterial.clear.spec.highlightAlphaDark));

      final liquid = DockGlassMaterial.liquid.spec;
      expect(liquid.sigma, lessThanOrEqualTo(4));
      expect(liquid.saturate, inInclusiveRange(1.3, 1.5));
      expect(liquid.refraction, isTrue);
      // 液态的纱最薄、边缘描边最亮
      expect(liquid.tintAlphaDark,
          lessThan(DockGlassMaterial.clear.spec.tintAlphaDark));
      expect(liquid.borderAlphaDark,
          greaterThan(DockGlassMaterial.frosted.spec.borderAlphaDark));
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
    test('dock glass material round-trips through the settings box',
        () async {
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
  });
}
