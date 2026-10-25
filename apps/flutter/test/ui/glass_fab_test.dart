import 'dart:io';

import 'package:c001apk_flutter/components/glass_surface.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// miuix14：悬浮按钮玻璃化（GlassFab 与悬浮 Dock 共用 GlassSurface /
/// DockGlassSpec 同一套材质，跟随「玻璃材质」设置）。断言：几何与原
/// FAB 一致（56dp；圆形变体边长可调）、真毛玻璃在场、三档材质渲染、
/// 点击回调、禁用态变淡、无覆写时跟随设置切换即时生效。
void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-glassfab-');
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

  Future<void> pumpFab(
    WidgetTester tester, {
    DockGlassMaterial? material,
    VoidCallback? onPressed = _noop,
    bool circular = false,
    double size = 56,
    String? tooltip,
    Brightness brightness = Brightness.dark,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Center(
          child: GlassFab(
            onPressed: onPressed,
            icon: Icons.add,
            tooltip: tooltip,
            size: size,
            circular: circular,
            materialOverride: material,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('renders 56dp with real backdrop glass by default',
      (tester) async {
    await pumpFab(tester, material: DockGlassMaterial.frosted);
    expect(find.byType(GlassFab), findsOneWidget);
    expect(tester.getSize(find.byType(GlassFab)), const Size(56, 56));
    // 与 Dock 同一套真毛玻璃链
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all three materials render in both brightnesses',
      (tester) async {
    for (final material in DockGlassMaterial.values) {
      for (final brightness in Brightness.values) {
        await pumpFab(tester, material: material, brightness: brightness);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(BackdropFilter), findsOneWidget,
            reason: '$material/$brightness 应有玻璃层');
        expect(tester.takeException(), isNull,
            reason: '$material/$brightness 不应抛异常');
      }
    }
  });

  testWidgets('circular variant keeps its size (image viewer arrows)',
      (tester) async {
    await pumpFab(tester,
        material: DockGlassMaterial.clear, circular: true, size: 40);
    expect(tester.getSize(find.byType(GlassFab)), const Size(40, 40));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('tap fires onPressed, tooltip is exposed', (tester) async {
    var taps = 0;
    await pumpFab(tester,
        material: DockGlassMaterial.frosted,
        onPressed: () => taps++,
        tooltip: '发布动态');
    expect(find.byTooltip('发布动态'), findsOneWidget);
    await tester.tap(find.byType(GlassFab));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('disabled button dims the icon and swallows taps',
      (tester) async {
    await pumpFab(tester,
        material: DockGlassMaterial.frosted, onPressed: null);
    final disabledIcon = tester.widget<Icon>(find.byIcon(Icons.add));
    expect(disabledIcon.color!.a, lessThan(0.5));
    await tester.tap(find.byType(GlassFab));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await pumpFab(tester, material: DockGlassMaterial.frosted);
    final enabledIcon = tester.widget<Icon>(find.byIcon(Icons.add));
    expect(enabledIcon.color!.a, greaterThan(0.9));
  });

  testWidgets('icon color keeps contrast in light mode', (tester) async {
    await pumpFab(tester,
        material: DockGlassMaterial.frosted, brightness: Brightness.light);
    final icon = tester.widget<Icon>(find.byIcon(Icons.add));
    // 浅色玻璃上用深灰图标（与 Dock 未选中项一致）
    expect(icon.color, const Color(0xFF3F4145));
  });

  testWidgets('without override the button follows the stored material',
      (tester) async {
    // Hive 写盘是真 IO，必须在 runAsync 里做（FakeAsync 区会死锁）。
    await tester.runAsync(
        () => GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, 0));
    await pumpFab(tester);
    expect(find.byType(BackdropFilter), findsOneWidget);
    // 切换材质后 listenable 触发重建，不重启即生效、不抛异常
    await tester.runAsync(
        () => GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
