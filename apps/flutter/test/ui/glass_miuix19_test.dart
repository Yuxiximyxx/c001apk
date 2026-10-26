import 'dart:io';

import 'package:c001apk_flutter/components/floating_dock_bar.dart';
import 'package:c001apk_flutter/components/glass_menu.dart';
import 'package:fluid_glass/fluid_glass.dart' show DrawBackdrop;
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
///    program，首帧无透镜、回调后整条滤镜链被换掉。miuix19 的修法
///    （同步缓存 + 就绪门）在 miuix22 引擎迁移后对应为：DrawBackdrop
///    效果链同步构建、菜单就绪门改挂 fluid 程序加载。本组断言改为
///    新引擎的等价不变量：菜单面自第一帧起就是 fluid DrawBackdrop
///    （无异步换链的可能），且传给引擎的形状带真实圆角 20（第 2 条
///    在新引擎的对应钉法——fluid 的 lens 按形状真实角算 SDF）。
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
        cornerRadii: const BorderRadius.vertical(top: Radius.circular(28)),
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
                child:
                    Align(alignment: Alignment.centerLeft, child: Text('深色模式')),
              ),
            ),
          ),
        ),
      );
    }

    DrawBackdrop menuSurface(WidgetTester tester) {
      final surface = find.ancestor(
          of: find.text('始终关闭'), matching: find.byType(GlassSurface));
      return tester.widget<DrawBackdrop>(
        find.descendant(of: surface, matching: find.byType(DrawBackdrop)),
      );
    }

    testWidgets('menu surface is the fluid draw from the first frame',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text('深色模式'));
      await tester.pump();
      // 第一帧：菜单面已是 fluid DrawBackdrop（效果链同步构建，
      // 不存在旧引擎「首帧无透镜、回调后换链」的窗口），且形状
      // 带菜单的真实圆角 20——fluid 的 lens 据此算 SDF，面内不会
      // 再出现 miuix19 的假弧线。
      final first = menuSurface(tester);
      final corners =
          first.shape().corners(const Size(200, 152), TextDirection.ltr);
      expect(corners.topLeft, 20);
      expect(corners.topRight, 20);
      expect(corners.bottomRight, 20);
      expect(corners.bottomLeft, 20);
      // 入场全程不得换引擎/换形状。
      await tester.pump(const Duration(milliseconds: 60));
      expect(
          menuSurface(tester)
              .shape()
              .corners(const Size(200, 152), TextDirection.ltr),
          corners);
      await tester.pumpAndSettle();
      expect(
          menuSurface(tester)
              .shape()
              .corners(const Size(200, 152), TextDirection.ltr),
          corners);
      expect(find.text('始终关闭'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
