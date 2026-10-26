import 'dart:io';
import 'dart:ui' as ui;

import 'package:c001apk_flutter/components/glass_dialog.dart';
import 'package:c001apk_flutter/components/glass_menu.dart';
import 'package:c001apk_flutter/components/glass_sheet.dart';
import 'package:c001apk_flutter/components/glass_surface.dart';
import 'package:c001apk_flutter/components/settings/glass_settings_item.dart';
import 'package:c001apk_flutter/pages/feed/reply/reply_page.dart';
import 'package:c001apk_flutter/pages/others/imageview_page.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' as miuix;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// miuix17 新玻璃面的 widget 断言：对话框、弹出菜单、底部 sheet、
/// 回复输入悬浮卡、图片查看器 Clear 控制层、设置页滑杆组——每个面
/// 都必须由 GlassSurface/BackdropFilter 构成（真玻璃，不是实色仿造）。
void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-glass-surfaces-');
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

  testWidgets('glass dialog renders on a GlassSurface', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const GlassAlertDialog(
                  title: Text('删除此会话？'),
                  content: Text('此操作无法撤销。'),
                  actions: [TextButton(onPressed: null, child: Text('删除'))],
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassAlertDialog), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(GlassAlertDialog),
            matching: find.byType(GlassSurface)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(GlassAlertDialog),
            matching: find.byType(BackdropFilter)),
        findsOneWidget);
    expect(find.text('删除此会话？'), findsOneWidget);
    expect(find.text('此操作无法撤销。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass popup menu opens on glass and returns the value',
      (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [
          GlassPopupMenuButton<String>(
            onSelected: (v) => selected = v,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', height: 50, child: Text('复制链接')),
              PopupMenuItem(value: 'share', height: 50, child: Text('分享')),
            ],
          ),
        ]),
        body: const SizedBox.expand(),
      ),
    ));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('复制链接'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.text('复制链接'), matching: find.byType(GlassSurface)),
        findsOneWidget);
    await tester.tap(find.text('分享'));
    await tester.pumpAndSettle();
    expect(selected, 'share');
    expect(find.text('复制链接'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass bottom sheet wraps its content in a GlassSurface',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showGlassBottomSheet<void>(
                context: context,
                builder: (_) => const SafeArea(
                  child: ListTile(title: Text('置顶会话')),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassSheetSurface), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(GlassSheetSurface),
            matching: find.byType(BackdropFilter)),
        findsOneWidget);
    expect(find.text('置顶会话'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reply input card is a glass surface', (tester) async {
    await tester.pumpWidget(miuix.MiuixTheme(
      data: appMiuixThemeData(Brightness.light),
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: const ReplyPage(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        find.descendant(
            of: find.byType(ReplyPage), matching: find.byType(GlassSurface)),
        findsWidgets);
    expect(
        find.descendant(
            of: find.byType(ReplyPage),
            matching: find.byType(BackdropFilter)),
        findsWidgets);
    expect(find.byType(TextField), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image viewer arrows use the clear glass variant',
      (tester) async {
    const urls = [
      'https://synthetic.invalid/viewer/one.png',
      'https://synthetic.invalid/viewer/two.png',
    ];
    for (final url in urls) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 180),
          Paint()..color = Colors.blue);
      final picture = recorder.endRecording();
      final bitmap =
          await tester.runAsync(() => picture.toImage(300, 180));
      picture.dispose();
      final key = await CachedNetworkImageProvider(url)
          .obtainKey(const ImageConfiguration());
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: bitmap!))),
      );
    }
    await tester.pumpWidget(const MaterialApp(
      home: ImageViewPage(imgList: urls, initialPage: 0),
    ));
    await tester.pumpAndSettle();
    final fabs = tester.widgetList<GlassFab>(find.byType(GlassFab)).toList();
    expect(fabs, hasLength(2),
        reason: '桌面端图片查看器应有左右两颗翻页玻璃钮');
    for (final fab in fabs) {
      expect(fab.variant, GlassVariant.clear,
          reason: '浮在图片上的控制层必须用 Clear 变体');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass settings show preset chips and seven sliders',
      (tester) async {
    // 预置「自定义」态：有效值偏离预设 → chips 显示自定义、无预设选中。
    await tester.runAsync(() => writeDockGlassCustom(
        DockGlassMaterial.frosted.spec.copyWith(sigma: 12)));
    await tester.pumpWidget(miuix.MiuixTheme(
      data: appMiuixThemeData(Brightness.light),
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(child: GlassSettingsItem()),
        ),
      ),
    ));
    await tester.pump();
    for (final label in ['毛玻璃', '磨砂玻璃', '液态玻璃', '自定义']) {
      expect(find.text(label), findsOneWidget, reason: '应有 chip：$label');
    }
    for (final title in [
      '透明度',
      '折射强度',
      '折射范围',
      '模糊强度',
      '饱和度',
      '色散强度',
      '高光强度',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '应有滑杆：$title');
    }
    expect(find.textContaining('恢复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
