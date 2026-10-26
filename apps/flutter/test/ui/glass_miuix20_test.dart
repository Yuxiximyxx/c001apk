import 'dart:io';

import 'package:c001apk_flutter/components/custom_toast.dart';
import 'package:c001apk_flutter/components/glass_dialog.dart';
import 'package:c001apk_flutter/components/glass_snackbar.dart';
import 'package:c001apk_flutter/components/glass_surface.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// miuix20 补漏回归测试：审计漏网的悬浮面换玻璃——
/// 通用对话框面 [GlassDialogSurface]、SnackBar 体系 [showGlassSnackBar]、
/// SmartDialog loading [CustomLoading]。断言钉住：面是 GlassSurface、
/// 文案/动作语义不变、滤镜首帧即在（BackdropFilter 构建期同步挂上，
/// 不重犯 miuix19 修掉的入场闪烁）。
void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-miuix20-');
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

  testWidgets('GlassDialogSurface 是透明 Dialog 壳 + 玻璃面，内容原样',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: GlassDialogSurface(child: Text('选择内容')),
      ),
    ));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.text('选择内容'), findsOneWidget);
    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.backgroundColor, Colors.transparent);
    expect(dialog.elevation, 0);
  });

  testWidgets('showGlassSnackBar 首帧即带玻璃滤镜，动作回调与文案不变',
      (tester) async {
    var actionTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showGlassSnackBar(
              context,
              message: '当前网页将要打开外部链接，是否打开',
              actionLabel: '打开',
              onAction: () => actionTaps++,
              showCloseIcon: true,
            ),
            child: const Text('触发'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('触发'));
    // 只 pump 一帧（不 settle）：玻璃面与滤镜必须已经在场。
    await tester.pump();
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.text('当前网页将要打开外部链接，是否打开'), findsOneWidget);
    // 入场动画走完再点动作（动画只动面板位移、滤镜不动，miuix19 口径）。
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pump();
    expect(actionTaps, 1);
  });

  testWidgets('CustomLoading 是玻璃面 + 指示器 + 文案', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CustomLoading(msg: '正在发布')),
    ));
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('正在发布'), findsOneWidget);
  });
}
