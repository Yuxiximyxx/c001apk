import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/logic/model/feed/user_info.dart';
import 'package:c001apk_flutter/logic/state/loading_state.dart';
import 'package:c001apk_flutter/utils/content_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('prepare asks for popular results without changing source and pins win',
      () async {
    final feed = Datum(id: 12, message: '正文', topReplyRows: [
      Datum(id: 1, message: '置顶', userInfo: UserInfo(username: '置顶作者'))
    ]);
    String? requested;
    final service = ContentExportService(
        loadPopular: (id) async {
          requested = id;
          return Success([
            Datum(id: 8, message: '热门第一'),
            Datum(id: 1),
            Datum(id: 4, message: '热门第二')
          ]);
        },
        blockedUids: () => {});
    final result = await service.prepare(feed, format: ExportFormat.markdown);
    final text = utf8.decode(result.bytes);
    expect(requested, '12');
    expect(result.commentIds, ['1', '8', '4']);
    expect(text.indexOf('置顶'), lessThan(text.indexOf('热门第一')));
    expect(text, contains('【置顶】'));
    expect(feed.topReplyRows!.single.isTop, isNull);
  });
  test(
      'failed comments produce a confirmation warning and a permanent file notice',
      () async {
    final service = ContentExportService(
        loadPopular: (_) async => const Error('需要验证'), blockedUids: () => {});
    final result = await service.prepare(Datum(id: 1, message: '正文'),
        format: ExportFormat.markdown);
    expect(result.warnings.join(), contains('评论'));
    expect(utf8.decode(result.bytes), contains('未能取得热门评论'));
  });
  test(
      'HTML embeds raster images, warns on failures, and never leaves remote img src',
      () async {
    final service = ContentExportService(
        loadPopular: (_) async => const Empty(),
        blockedUids: () => {},
        loadImage: (url) async => url.endsWith('a.png')
            ? await File('assets/icon/icon.png').readAsBytes()
            : null);
    final result = await service.prepare(
        Datum(id: 1, message: '正文', picArr: [
          'https://img.example/a.png',
          'https://img.example/b.png',
        ]),
        format: ExportFormat.html);
    final tree = html.parse(utf8.decode(result.bytes));
    expect(tree.querySelectorAll('img').single.attributes['src'],
        startsWith('data:image/png;base64,'));
    expect(result.warnings.join(), contains('1 张图片'));
    expect(tree.querySelectorAll('img[src^="http"]'), isEmpty);
  });
  test('Markdown does not download images and adds a link-only notice',
      () async {
    final service = ContentExportService(
        loadPopular: (_) async => const Empty(),
        blockedUids: () => {},
        loadImage: (_) async => throw StateError('must not fetch'));
    final result = await service.prepare(
        Datum(id: 1, message: '正文', picArr: ['https://img.example/a.png']),
        format: ExportFormat.markdown);
    expect(utf8.decode(result.bytes), contains('图片保留在线链接'));
    expect(result.warnings, isEmpty);
  });
  test('invalid image bytes never become embedded active content', () async {
    final service = ContentExportService(
        loadPopular: (_) async => const Empty(),
        blockedUids: () => {},
        loadImage: (_) async =>
            Uint8List.fromList(utf8.encode('<svg onload="bad()"/>')));
    final result = await service.prepare(
        Datum(id: 1, picArr: ['https://img.example/a.svg']),
        format: ExportFormat.html);
    expect(result.warnings, isNotEmpty);
    expect(
        html.parse(utf8.decode(result.bytes)).querySelectorAll('img'), isEmpty);
  });
  test('cancelled save returns false, writer receives exact name and bytes',
      () async {
    final service = ContentExportService(
        loadPopular: (_) async => const Empty(),
        blockedUids: () => {},
        saveBytes: (name, bytes) async {
          expect(name, endsWith('.md'));
          expect(utf8.decode(bytes), contains('正文'));
          return false;
        });
    final prepared = await service.prepare(Datum(id: 1, message: '正文'),
        format: ExportFormat.markdown);
    expect(await service.save(prepared), isFalse);
  });
  test('cancellation prevents file creation after pending work', () async {
    final service = ContentExportService(
        loadPopular: (_) async => const Empty(),
        blockedUids: () => {},
        saveBytes: (_, __) async => throw StateError('must not write'));
    final prepared = await service.prepare(Datum(id: 1, message: '正文'),
        format: ExportFormat.markdown);
    service.cancel();
    expect(() => service.save(prepared), throwsA(isA<ExportCancelled>()));
  });
  test('truncated image signature counts as missing and requires confirmation',
      () async {
    final service = ContentExportService(
        loadPopular: (_) async => const Empty(),
        blockedUids: () => {},
        loadImage: (_) async =>
            Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]));
    final result = await service.prepare(
        Datum(id: 1, picArr: ['https://img.example/truncated.png']),
        format: ExportFormat.html);
    expect(result.warnings, isNotEmpty);
    expect(
        html.parse(utf8.decode(result.bytes)).querySelectorAll('img'), isEmpty);
  });
}
