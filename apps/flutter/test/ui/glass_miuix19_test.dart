import 'dart:io';
import 'dart:ui' as ui;

import 'package:c001apk_flutter/components/floating_dock_bar.dart';
import 'package:c001apk_flutter/components/glass_menu.dart';
// glass_surface.dart 由 floating_dock_bar.dart re-export，不再直引。
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// miuix19 回归测试（小乐真机反馈）：
/// 2. 玻璃 sheet/菜单面上的同心圆弧线——根因是折射 shader 的 SDF
///    写死胶囊半径（= 短边一半），与面的真实圆角不符时，假 cap 弧
///    切过面内、rim/折射沿假弧显形。修法：shader 改按真实四角半径
///    的圆角矩形 SDF，半径经 uniform 管线直传。本组断言钉住这条
///    管线：sheet 的 (28,28,0,0)、菜单的 20、Dock 胶囊的 34 都必须
///    原样到达 shader uniform（物理像素）。
/// 3. 玻璃菜单入场闪烁——根因是 GlassSurface 异步 .then 取 shader
///    program，首帧无透镜、回调后整条滤镜链被换掉。修法：
///    RefractionSupport 同步缓存 + 菜单面板的滤镜就绪门。本组断言
///    菜单 BackdropFilter 的 filter 自第一帧起就是终态（与按缓存
///    program 现算的一致），且入场全程不再被换。
void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-miuix19-');
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

  group('shader uniform plumbing (true corner radii)', () {
    test('sheet radii 28/28/0/0 reach the shader in physical pixels', () {
      final sheetSpec = DockGlassMaterial.liquid.spec.adjustedForSurface(
        variant: GlassVariant.regular,
        sizeClass: GlassSizeClass.large,
      );
      final values = glassShaderUniformValues(
        spec: sheetSpec,
        size: const Size(411, 262),
        dpr: 2,
        cornerRadii:
            const BorderRadius.vertical(top: Radius.circular(28)),
      );
      expect(values, hasLength(11));
      expect(values[0], 411 * 2);
      expect(values[1], 262 * 2);
      // large 收敛：band = min(24×0.35, 14) = 8.4、amount = 24×0.35。
      expect(values[2], closeTo(8.4 * 2, 1e-9));
      expect(values[3], closeTo(8.4 * 2, 1e-9));
      // 液态身份：色散不随面积档收敛。
      expect(values[4], 0.2);
      // 顺序 TL/TR/BR/BL：顶部 28dp×dpr、底部直角 0——SDF 据此贴
      // 真实轮廓，面内不再有假 cap 弧。
      expect(values.sublist(7), [56.0, 56.0, 0.0, 0.0]);
    });

    test('menu radii 20 and dock capsule radii 34 pass through', () {
      final menu = glassShaderUniformValues(
        spec: DockGlassMaterial.frosted.spec,
        size: const Size(252, 248),
        dpr: 3,
        cornerRadii: BorderRadius.circular(20),
      );
      expect(menu.sublist(7), [60.0, 60.0, 60.0, 60.0]);

      final dock = glassShaderUniformValues(
        spec: DockGlassMaterial.liquid.spec,
        size: const Size(164, FloatingDockBar.height),
        dpr: 1,
        cornerRadii: BorderRadius.circular(FloatingDockBar.height / 2),
      );
      expect(dock.sublist(7), [34.0, 34.0, 34.0, 34.0]);
      // 胶囊半径 = 短边一半时新圆角矩形 SDF 与旧胶囊 SDF 恒等，
      // 小面（Dock/药丸/FAB）观感不回退的数值前提。
    });
  });

  group('glass menu entrance filter readiness', () {
    Widget host() {
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: GlassPopupMenuButton<String>(
              onSelected: (_) {},
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'a', child: Text('始终关闭')),
                PopupMenuItem(value: 'b', child: Text('始终开启')),
                PopupMenuItem(value: 'c', child: Text('跟随系统')),
              ],
              child: const SizedBox(
                width: 200,
                height: 52,
                child: Align(
                    alignment: Alignment.centerLeft, child: Text('深色模式')),
              ),
            ),
          ),
        ),
      );
    }

    ui.ImageFilter menuFilter(WidgetTester tester) {
      final surface = find.ancestor(
          of: find.text('始终关闭'), matching: find.byType(GlassSurface));
      return tester
          .widget<BackdropFilter>(
            find.descendant(
                of: surface, matching: find.byType(BackdropFilter)),
          )
          .filter!;
    }

    testWidgets('menu backdrop filter is final from the first frame',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text('深色模式'));
      await tester.pump();
      // 第一帧：滤镜必须已是终态——按 RefractionSupport 的同步缓存
      // program 与菜单面真实参数（medium 收敛、圆角 20、浅色 rim）
      // 现算的滤镜链，两者必须一致。
      final first = menuFilter(tester);
      final surface = find.ancestor(
          of: find.text('始终关闭'), matching: find.byType(GlassSurface));
      final expected = glassImageFilter(
        spec: DockGlassMaterial.frosted.spec.adjustedForSurface(
          variant: GlassVariant.regular,
          sizeClass: GlassSizeClass.medium,
        ),
        size: tester.getSize(surface),
        dpr: tester.view.devicePixelRatio,
        refractionProgram: RefractionSupport.cachedProgram,
        cornerRadii: BorderRadius.circular(20),
        rimStrength: glassHighlightAlpha(
            DockGlassMaterial.frosted.spec.adjustedForSurface(
              variant: GlassVariant.regular,
              sizeClass: GlassSizeClass.medium,
            ),
            false),
        innerShadow: 0.3,
      );
      expect(first, expected,
          reason: '菜单首帧的滤镜就应是终态，不许入场中途换链');
      // 入场全程（量尺寸/就绪门放行/动画结束）滤镜不得被换掉。
      await tester.pump(const Duration(milliseconds: 60));
      expect(menuFilter(tester), first, reason: '入场中滤镜不许被换');
      await tester.pumpAndSettle();
      expect(menuFilter(tester), first, reason: '入场结束滤镜仍是同一条链');
      expect(find.text('始终关闭'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
