import 'dart:async';

import 'package:c001apk_flutter/components/content_export_button.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/logic/model/feed/user_info.dart';
import 'package:c001apk_flutter/logic/state/loading_state.dart';
import 'package:c001apk_flutter/utils/content_export_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(WidgetTester tester, ContentExportService service) async {
    await tester.pumpWidget(MaterialApp(
        builder: FlutterSmartDialog.init(),
        home: Scaffold(
            appBar: AppBar(actions: [
          ContentExportButton(
            feed:
                Datum(id: 1, message: '正文', userInfo: UserInfo(username: '作者')),
            serviceFactory: () => service,
          )
        ]))));
  }

  testWidgets('format selection and incomplete export require explicit consent',
      (tester) async {
    var saves = 0;
    final service = ContentExportService(
        loadPopular: (_) async => const Error('需要验证'),
        blockedUids: () => {},
        saveBytes: (_, __) async {
          saves++;
          return true;
        });
    await mount(tester, service);
    await tester.tap(find.byTooltip('保存内容'));
    await tester.pumpAndSettle();
    expect(find.text('离线 HTML (.html)'), findsOneWidget);
    await tester.tap(find.text('Markdown (.md)'));
    await tester.pumpAndSettle();
    expect(find.text('部分内容未能保存'), findsOneWidget);
    expect(saves, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(saves, 0);
  });
  testWidgets(
      'save cancellation is silent and write failures show Chinese message',
      (tester) async {
    final service = ContentExportService(
        loadPopular: (_) async => const Empty(),
        blockedUids: () => {},
        saveBytes: (_, __) async => throw StateError('disk failure'));
    await mount(tester, service);
    await tester.tap(find.byTooltip('保存内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markdown (.md)'));
    await tester.pumpAndSettle();
    expect(find.text('保存失败，请检查目录权限和剩余空间后重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('leaving while preparing cancels without opening file picker',
      (tester) async {
    final pending = Completer<LoadingState>();
    var saves = 0;
    final service = ContentExportService(
        loadPopular: (_) => pending.future,
        blockedUids: () => {},
        saveBytes: (_, __) async {
          saves++;
          return true;
        });
    await mount(tester, service);
    await tester.tap(find.byTooltip('保存内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markdown (.md)'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
    pending.complete(const Empty());
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });
}
