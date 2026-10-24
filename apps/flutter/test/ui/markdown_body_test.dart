import 'dart:io';

import 'package:c001apk_flutter/components/markdown_body.dart';
import 'package:c001apk_flutter/components/cards/feed_card.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/components/update_dialog.dart';
import 'package:c001apk_flutter/logic/app_update/app_release.dart';
import 'package:c001apk_flutter/utils/markdown_content.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:get/get.dart';

void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-md-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  testWidgets('code remains readable after a live theme change',
      (tester) async {
    final content = MarkdownContent.parse('```text\nreadable code\n```');
    Future<void> show(ThemeMode mode) => tester.pumpWidget(MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.blue),
          darkTheme: ThemeData(
              colorSchemeSeed: Colors.blue, brightness: Brightness.dark),
          themeMode: mode,
          home: Scaffold(body: MarkdownBody(content: content)),
        ));
    await show(ThemeMode.light);
    await tester.pumpAndSettle();
    await show(ThemeMode.dark);
    await tester.pumpAndSettle();
    final codeFinder = find.byType(SelectableText);
    final code = tester.widget<SelectableText>(codeFinder);
    final foreground = code.style?.color ??
        DefaultTextStyle.of(tester.element(codeFinder)).style.color!;
    final box = tester
        .widgetList<Container>(
            find.ancestor(of: codeFinder, matching: find.byType(Container)))
        .firstWhere((w) =>
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color != null);
    final background = (box.decoration as BoxDecoration).color!;
    final a = foreground.computeLuminance();
    final b = background.computeLuminance();
    expect((a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
        greaterThanOrEqualTo(4.5));
  });

  testWidgets('code and wide tables scroll horizontally at narrow widths',
      (tester) async {
    final code = List.filled(80, 'long_word').join(' ');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
          child: SizedBox(
              width: 260,
              child: MarkdownBody(
                  content: MarkdownContent.parse(
                '## 标题\n\n```text\n$code\n```\n\n| 第一列 | 第二列 |\n| --- | --- |\n| ${'x' * 80} | value |',
              )))),
    ))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scrolls = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scrolls.where((w) => w.scrollDirection == Axis.horizontal).length,
        greaterThanOrEqualTo(2));
    final codeText =
        tester.widget<SelectableText>(find.byType(SelectableText).first);
    expect(codeText.data, contains(code));
    expect(tester.getSize(find.byType(MarkdownBody)).height, lessThan(500));
    expect(tester.getSize(find.byType(SelectableText).first).height,
        lessThan(100));
    expect(
        tester
            .widgetList<Scrollable>(find.byType(Scrollable))
            .where((w) => w.axisDirection == AxisDirection.right)
            .map((w) => tester
                .state<ScrollableState>(find.byWidget(w))
                .position
                .maxScrollExtent)
            .where((extent) => extent > 0)
            .length,
        greaterThanOrEqualTo(2));
  });

  testWidgets(
      'feed preview stays bounded and detail can show the original text',
      (tester) async {
    final source = '## 标题\n\n${List.filled(100, '- **信息**').join('\n')}';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                SizedBox(width: 260, child: FeedText(source, preview: true)))));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(FeedText)).height, lessThan(180));
    expect(find.byType(MarkdownBody), findsNothing);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: FeedText(source, forcePlain: true)))));
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data,
        source);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Markdown links keep the application callback', (tester) async {
    String? opened;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MarkdownBody(
      content: MarkdownContent.parse('[话题](/t/test) **内容**'),
      onTapUrl: (url) {
        opened = url;
        return true;
      },
    ))));
    await tester.pumpAndSettle();
    final paragraph = find.text('话题 内容', findRichText: true);
    await tester.tapAt(tester.getTopLeft(paragraph) + const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(opened, 'https://www.coolapk.com/t/test');
  });

  testWidgets('update notes render Markdown and dialog actions still return',
      (tester) async {
    final release = AppRelease.fromJson({
      'draft': false,
      'prerelease': false,
      'tag_name': '1.3.3-release',
      'html_url':
          'https://github.com/TG-Twilight/c001apk/releases/tag/1.3.3-release',
      'assets': <dynamic>[],
      'body': '## 更新说明\n\n- **修复问题**\n- 更好阅读',
    });
    UpdateAction? action;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      child: const Text('打开'),
                      onPressed: () async {
                        action = await showDialog<UpdateAction>(
                            context: context,
                            builder: (_) => AppUpdateDialog(
                                release: release,
                                currentVersion: '1.3.2',
                                onOpenRelease: () {}));
                      }),
                ))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text('更新说明', findRichText: true), findsOneWidget);
    expect(find.text(release.notes), findsNothing);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(action, UpdateAction.later);
  });

  testWidgets('native picture links still open the gallery', (tester) async {
    Map<dynamic, dynamic>? arguments;
    await tester.pumpWidget(GetMaterialApp(
      getPages: [
        GetPage(
            name: '/imageview',
            page: () {
              arguments = Get.arguments as Map;
              return const Scaffold(body: Text('图片查看'));
            })
      ],
      home: Scaffold(
          body: MarkdownBody(
        content: MarkdownContent.parse(
            '**图**\n\n<a class="feed-link-url" href="https://image.coolapk.com/a.jpg">查看图片</a>'),
        picArr: const ['https://image.coolapk.com/a.jpg'],
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tapAt(
        tester.getTopLeft(find.text('查看图片', findRichText: true)) +
            const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('图片查看'), findsOneWidget);
    expect(arguments?['imgList'], ['https://image.coolapk.com/a.jpg']);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
  });

  testWidgets('titleless forwarded Markdown uses a bounded preview',
      (tester) async {
    final data = Datum.fromJson({
      'id': 1,
      'uid': 1,
      'dateline': 1,
      'message': '转发',
      'forwardSourceType': 'feed',
      'forwardSourceFeed': {
        'id': 2,
        'uid': 2,
        'username': '合成用户',
        'message': '## 转发\n\n${List.filled(100, '- 正文').join('\n')}',
      },
    });
    await tester.pumpWidget(GetMaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: FeedCard(data: data),
    ))));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownBody), findsNothing);
    expect(tester.getSize(find.byType(FeedCard)).height, lessThan(500));
    expect(
        tester
            .widgetList<Text>(find.descendant(
                of: find.byType(FeedCard), matching: find.byType(Text)))
            .any((text) => text.data?.contains('## 转发') ?? false),
        isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
  });

  testWidgets('oversized explicit documents fall back to readable source',
      (tester) async {
    final source = '## 标题\n${'x' * 200001}';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: MarkdownBody(
          content:
              MarkdownContent.parse(source, explicit: true, coolapk: false)),
    ))));
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data,
        source);
  });
}
