import 'dart:io';

import 'package:c001apk_flutter/components/glass_dialog.dart';
import 'package:c001apk_flutter/components/glass_menu.dart';
import 'package:c001apk_flutter/components/glass_sheet.dart';
import 'package:c001apk_flutter/components/glass_surface.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// miuix18 回归测试：
/// 1. 玻璃菜单尺寸——miuix17 的菜单被 Column(stretch) 撑到上限宽
///    320dp（真机截图近全屏宽），且高度不贴合内容；新口径：宽度贴合
///    内容（168–280dp），高度 = 条目数 × 48 + 组内距。
/// 2. 玻璃面动画规范——菜单/对话框/sheet 打开时首帧应处于动画中间
///    态（opacity/scale/位置都未到位），到时后落在终态。
void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-menu-size-');
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

  /// 宽锚点（整行 760dp，像设置页的一行）+ 给定条目的菜单宿主。
  Widget host(List<PopupMenuEntry<String>> items) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: GlassPopupMenuButton<String>(
            onSelected: (_) {},
            itemBuilder: (_) => items,
            child: const SizedBox(
              width: 760,
              height: 52,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('跟随系统'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Size menuSize(WidgetTester tester, String label) => tester.getSize(
        find.ancestor(
            of: find.text(label), matching: find.byType(GlassSurface)),
      );

  testWidgets('glass menu width fits content, not the anchor row',
      (tester) async {
    await tester.pumpWidget(host(const [
      PopupMenuItem(value: 'a', child: Text('始终关闭')),
      PopupMenuItem(value: 'b', child: Text('始终开启')),
      PopupMenuItem(value: 'c', child: Text('跟随系统')),
    ]));
    await tester.tap(find.text('跟随系统').first);
    await tester.pumpAndSettle();
    final size = menuSize(tester, '始终关闭');
    // 宽度贴合内容：不许再等于锚点行宽/近全屏，也不能撑到旧上限 320。
    expect(size.width, lessThanOrEqualTo(280));
    expect(size.width, greaterThanOrEqualTo(168));
    expect(size.width, lessThan(380));
    // 高度贴合内容：3 条 × 48dp + 组内距 8 ≈ 152。
    expect(size.height, inInclusiveRange(146, 160));
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass menu height grows with item count', (tester) async {
    await tester.pumpWidget(host([
      for (var i = 0; i < 6; i++)
        PopupMenuItem(value: '$i', child: Text('条目 $i')),
    ]));
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    final size = menuSize(tester, '条目 0');
    expect(size.height, inInclusiveRange(290, 302));
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass menu width is capped for very long items',
      (tester) async {
    await tester.pumpWidget(host([
      PopupMenuItem(value: 'x', child: Text('长' * 60)),
    ]));
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    final size = menuSize(tester, '长' * 60);
    expect(size.width, lessThanOrEqualTo(280));
    expect(size.width, greaterThan(250));
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass menu entrance is mid-animation shortly after open',
      (tester) async {
    await tester.pumpWidget(host(const [
      PopupMenuItem(value: 'a', child: Text('始终关闭')),
      PopupMenuItem(value: 'b', child: Text('始终开启')),
    ]));
    await tester.tap(find.text('跟随系统'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('始终关闭'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, greaterThan(0.3));
    expect(opacity.opacity, lessThan(1));
    final transform = tester.widget<ScaleTransition>(
      find
          .ancestor(
              of: find.text('始终关闭'), matching: find.byType(ScaleTransition))
          .first,
    );
    expect(transform.scale.value, greaterThan(0.95));
    expect(transform.scale.value, lessThan(1));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    final done = tester.widget<Opacity>(
      find.ancestor(of: find.text('始终关闭'), matching: find.byType(Opacity)),
    );
    expect(done.opacity, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass dialog entrance scales from 0.96 with fade',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showGlassDialog<void>(
                context: context,
                builder: (_) => const GlassAlertDialog(
                  title: Text('删除？'),
                  content: Text('正文'),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final scaleTransition = tester.widget<ScaleTransition>(
      find
          .ancestor(
              of: find.byType(GlassAlertDialog),
              matching: find.byType(ScaleTransition))
          .first,
    );
    expect(scaleTransition.scale.value, greaterThan(0.96));
    expect(scaleTransition.scale.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(find.byType(GlassAlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass bottom sheet slides up over time', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showGlassBottomSheet<void>(
                context: context,
                builder: (_) => const SizedBox(
                  height: 120,
                  child: Center(child: Text('sheet 内容')),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midTop = tester.getTopLeft(find.byType(GlassSheetSurface)).dy;
    await tester.pumpAndSettle();
    final endTop = tester.getTopLeft(find.byType(GlassSheetSurface)).dy;
    expect(midTop, greaterThan(endTop),
        reason: 'sheet 打开中途应还在终点位置下方（自下滑动）');
    expect(find.text('sheet 内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
