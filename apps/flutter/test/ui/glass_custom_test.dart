import 'dart:io';
import 'package:c001apk_flutter/components/floating_dock_bar.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:fluid_glass/fluid_glass.dart' show LiquidGlassTheme;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// miuix17 玻璃参数可调：有效 spec 解析（预设 + 自定义滑杆值）、老用户
/// 迁移初值、变体/面积系数，以及 miuix16 运行时审计的扩展——改滑杆
/// 存储值后，实际生效的玻璃参数必须随之变化（miuix22 起 Dock 胶囊
/// 面换 fluid 引擎后，树上可观测的活参数是经唯一映射点注入的纱色，
/// 见 runtime audit 组的注记）。
void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-glass-custom-');
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

  group('effective spec resolution', () {
    test('no custom values: effective spec equals the stored preset', () {
      // 默认（未存）= 磨砂
      expect(currentDockGlassSpec(), DockGlassMaterial.frosted.spec);
      expect(readDockGlassCustom(), isNull);
      expect(dockGlassIsCustomized(), isFalse);
    });

    test('migration: legacy user with liquid stored keeps liquid values',
        () async {
      // 老用户只有 dockGlassMaterial=2、没有 dockGlassCustom：滑杆
      // 初值（=有效 spec）必须等于液态预设表，升级后观感不变。
      await GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, 2);
      expect(readDockGlassCustom(), isNull);
      expect(currentDockGlassSpec(), DockGlassMaterial.liquid.spec);
      expect(currentDockGlassSpec().sigma, 8);
      expect(currentDockGlassSpec().refractionAmountDp, 24);
      expect(currentDockGlassSpec().dispersion, 0.2);
      expect(dockGlassIsCustomized(), isFalse);
    });

    test('selecting a preset writes its values into the slider group',
        () async {
      await selectDockGlassPreset(DockGlassMaterial.liquid);
      expect(GStorage.settings.get(SettingsBoxKey.dockGlassMaterial), 2);
      expect(readDockGlassCustom(),
          dockGlassCustomFromSpec(DockGlassMaterial.liquid.spec));
      // 预设写入后有效值逐值等于预设表，且不算「自定义」态。
      expect(currentDockGlassSpec(), DockGlassMaterial.liquid.spec);
      expect(dockGlassIsCustomized(), isFalse);
    });

    test('moving a slider makes the effective spec follow', () async {
      await selectDockGlassPreset(DockGlassMaterial.liquid);
      final tweaked = DockGlassMaterial.liquid.spec.copyWith(
        sigma: 30,
        tintAlphaDark: 0.7,
        tintAlphaLight: 0.7,
        dispersion: 0.45,
      );
      await writeDockGlassCustom(tweaked);
      final effective = currentDockGlassSpec();
      expect(effective, tweaked);
      expect(effective.sigma, 30);
      expect(effective.dispersion, 0.45);
      expect(dockGlassIsCustomized(), isTrue);
      // 恢复预设值 = 把预设数值重新写入滑杆组。
      await writeDockGlassCustom(DockGlassMaterial.liquid.spec);
      expect(currentDockGlassSpec(), DockGlassMaterial.liquid.spec);
      expect(dockGlassIsCustomized(), isFalse);
    });

    test('partial custom map falls back per-field to the preset', () async {
      await GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, 0);
      await GStorage.settings
          .put(SettingsBoxKey.dockGlassCustom, {'sigma': 3.0});
      final effective = currentDockGlassSpec();
      expect(effective.sigma, 3);
      expect(effective.saturate, DockGlassMaterial.clear.spec.saturate);
      expect(effective.refractionAmountDp,
          DockGlassMaterial.clear.spec.refractionAmountDp);
    });
  });

  group('variant coefficients', () {
    final liquid = DockGlassMaterial.liquid.spec;

    test('regular small is the identity (dock/FAB keep full strength)', () {
      expect(
        liquid.adjustedForSurface(
            variant: GlassVariant.regular, sizeClass: GlassSizeClass.small),
        liquid,
      );
    });

    test('medium scales lens to 0.6, large to 0.35 with band cap', () {
      final medium = liquid.adjustedForSurface(
          variant: GlassVariant.regular, sizeClass: GlassSizeClass.medium);
      expect(medium.refractionAmountDp, closeTo(24 * 0.6, 1e-9));
      expect(medium.refractionBandDp, closeTo(24 * 0.6, 1e-9));
      // 其他分量不动。
      expect(medium.sigma, liquid.sigma);
      expect(medium.tintAlphaDark, liquid.tintAlphaDark);

      final large = liquid.adjustedForSurface(
          variant: GlassVariant.regular, sizeClass: GlassSizeClass.large);
      expect(large.refractionAmountDp, closeTo(24 * 0.35, 1e-9));
      expect(large.refractionBandDp, closeTo(24 * 0.35, 1e-9));

      // band 封顶：自定义把 band 拉到 40 时，large 只到 14、medium 20。
      final hot = liquid.copyWith(refractionBandDp: 40);
      expect(
          hot
              .adjustedForSurface(
                  variant: GlassVariant.regular,
                  sizeClass: GlassSizeClass.large)
              .refractionBandDp,
          14);
      expect(
          hot
              .adjustedForSurface(
                  variant: GlassVariant.regular,
                  sizeClass: GlassSizeClass.medium)
              .refractionBandDp,
          20);
    });

    test('clear variant: tint halved, sigma 0.85x, lens like large', () {
      final clear = liquid.adjustedForSurface(
          variant: GlassVariant.clear, sizeClass: GlassSizeClass.small);
      expect(clear.tintAlphaDark, closeTo(0.32 * 0.5, 1e-9));
      expect(clear.tintAlphaLight, closeTo(0.32 * 0.5, 1e-9));
      expect(clear.sigma, closeTo(8 * 0.85, 1e-9));
      expect(clear.refractionAmountDp, closeTo(24 * 0.35, 1e-9));
      expect(clear.refractionBandDp, closeTo(24 * 0.35, 1e-9));
    });

    test('lens strength ordering small > medium > large holds', () {
      double amount(GlassSizeClass size) => liquid
          .adjustedForSurface(variant: GlassVariant.regular, sizeClass: size)
          .refractionAmountDp;
      expect(amount(GlassSizeClass.small),
          greaterThan(amount(GlassSizeClass.medium)));
      expect(amount(GlassSizeClass.medium),
          greaterThan(amount(GlassSizeClass.large)));
    });
  });

  group('runtime audit with custom sliders', () {
    Future<void> pumpDock(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          bottomNavigationBar: FloatingDockBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
          body: const SizedBox.expand(),
        ),
      ));
      await tester.pump();
    }

    Color captureTint(WidgetTester tester) {
      // miuix22：胶囊面换 fluid DrawBackdrop 后，纱色经唯一映射点
      // dockGlassColorsForSpec 以 LiquidGlassColors 注入子树——树上
      // 可观测的活参数就是它。其余滑杆分量（sigma/dispersion 等）
      // 在 fluid 侧无入口（光学写死），不再有树上可断言的 filter，
      // 其解析正确性由上方 spec 解析组与映射纯函数组钉住。
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

    testWidgets('changing stored slider values changes the live tint',
        (tester) async {
      // 起点：液态预设、无自定义——纱色应与液态预设一致。
      await tester.runAsync(
          () => GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, 2));
      await pumpDock(tester);
      final before = captureTint(tester);
      expect(before, glassTintColor(DockGlassMaterial.liquid.spec, true));

      // 拖滑杆等价写入：纱 alpha 拉到 0.7（另带 sigma/色散，验证
      // 写入链不因 fluid 无入口而中断）。
      final custom = DockGlassMaterial.liquid.spec.copyWith(
        sigma: 30,
        tintAlphaDark: 0.7,
        tintAlphaLight: 0.7,
        dispersion: 0.45,
      );
      await tester.runAsync(() => writeDockGlassCustom(custom));
      await tester.pump(const Duration(milliseconds: 300));
      final after = captureTint(tester);
      expect(after, glassTintColor(custom, true));
      expect(after, isNot(equals(before)));
      expect(tester.takeException(), isNull);
    });
  });
}
