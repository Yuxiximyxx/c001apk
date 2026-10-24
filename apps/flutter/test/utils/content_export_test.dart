import 'dart:convert';

import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/logic/model/feed_article/feed_article.dart';
import 'package:c001apk_flutter/utils/content_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;

void main() {
  Datum reply(int id, {int? top, String? uid}) => Datum(
      id: id, uid: uid ?? '$id', message: '评论$id', isTop: top, likenum: id);

  test('pinned comments precede server popular order, deduplicate and cap at 3',
      () {
    final result = selectExportComments(
      [reply(1)],
      [reply(8), reply(1), reply(4, top: 1), reply(100)],
    );
    expect(result.map((e) => e.id), [1, 4, 8]);
  });
  test('multiple pins outrank all popular replies and blocked authors stay out',
      () {
    expect(
        selectExportComments(
            [reply(1), reply(2), reply(3), reply(4)], [reply(50)],
            blockedUids: {'2'}).map((e) => e.id),
        [1, 3, 4]);
  });
  test(
      'plain HTML exports paragraphs, links and metadata without tags in markdown',
      () {
    final doc = ExportDocument.fromFeed(Datum(
        id: 12,
        username: '作者',
        messageTitle: '标题',
        dateline: 1700000000,
        message: '<p>第一段<br>换行</p><p><a href="/u/7">用户</a> &amp; 正文</p>'));
    expect(doc.markdown, contains('第一段  \n换行'));
    expect(doc.markdown, contains('[用户](https://www.coolapk.com/u/7)'));
    expect(doc.markdown, contains('作者'));
    expect(doc.markdown, contains('https://www.coolapk1s.com/feed/12'));
    expect(doc.markdown, isNot(contains('<p>')));
  });
  test('Markdown retains code, task lists and tables', () {
    final doc = ExportDocument.fromFeed(Datum(
        id: 1,
        message:
            '# 正文\n\n```dart\nfinal x = "<script>";\n```\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n- [x] 已完成'));
    expect(doc.markdown, contains('```dart\nfinal x = "<script>";'));
    expect(doc.markdown, contains('| A | B |'));
    expect(doc.markdown, contains('- [x] 已完成'));
    expect(doc.html, contains('<table>'));
  });
  test(
      'structured articles retain ordered text images captions and shared links',
      () {
    final doc = ExportDocument.fromFeed(Datum(id: 1, message: '摘要'), articles: [
      FeedArticle(type: 'text', message: '前段'),
      FeedArticle(
          type: 'image', url: 'https://img.example/a.png', description: '图注'),
      FeedArticle(type: 'text', message: '后段'),
      FeedArticle(type: 'shareUrl', title: '引用', url: 'https://example.com/a'),
    ]);
    expect(doc.markdown.indexOf('前段'), lessThan(doc.markdown.indexOf('图注')));
    expect(doc.markdown.indexOf('图注'), lessThan(doc.markdown.indexOf('后段')));
    expect(doc.markdown, isNot(contains('摘要')));
    expect(doc.imageUrls, ['https://img.example/a.png']);
    expect(doc.markdown, contains('[引用](https://example.com/a)'));
  });
  test(
      'forwards, picture galleries and top comments are included without subreplies',
      () {
    final doc = ExportDocument.fromFeed(
        Datum(
            id: 1,
            message: '转发',
            forwardSourceFeed: Datum(
                id: 2,
                username: '原作者',
                message: '**原文**',
                picArr: ['https://img.example/f.png'])),
        comments: [
          Datum(
              id: 7,
              username: '读者',
              message: '置顶内容',
              isTop: 1,
              replyRows: [Datum(id: 8, message: '不要楼中楼')]),
        ]);
    expect(doc.markdown, contains('原作者'));
    expect(doc.markdown, contains('**原文**'));
    expect(doc.markdown, contains('置顶'));
    expect(doc.markdown, isNot(contains('不要楼中楼')));
    expect(doc.imageUrls, contains('https://img.example/f.png'));
  });
  test('active HTML and unsafe URLs are removed, literal code stays readable',
      () {
    final doc = ExportDocument.fromFeed(Datum(
        id: 1,
        message: '<p onclick="bad()">正文<script>secret()</script></p>'
            '<iframe src="https://bad.example"></iframe><img src="file:///secret">'
            '<a href="javascript:bad()">链接</a><img src="https://img.example/a.png" onerror="bad()">'));
    final tree = html.parse(doc.html);
    expect(tree.querySelectorAll('script,iframe,[onclick],[onerror]'), isEmpty);
    expect(doc.html, isNot(contains('secret()')));
    expect(doc.html, isNot(contains('javascript:')));
    expect(doc.html, isNot(contains('file:///')));
    expect(doc.imageUrls, ['https://img.example/a.png']);
  });
  test(
      'offline HTML embeds images and replaces missing images with source links',
      () {
    final doc = ExportDocument.fromFeed(Datum(id: 1, message: '内容', picArr: [
      'https://img.example/a.png',
      'https://img.example/b.png',
    ]));
    final offline = doc.offlineHtml(
        {'https://img.example/a.png': 'data:image/png;base64,AAAA'});
    final tree = html.parse(offline);
    expect(tree.querySelectorAll('img').single.attributes['src'],
        'data:image/png;base64,AAAA');
    expect(
        tree.querySelector('a[href="https://img.example/b.png"]'), isNotNull);
    expect(offline, contains('图片未保存'));
    expect(tree.querySelectorAll('link,script,iframe'), isEmpty);
  });
  test('file name cleans Windows characters and falls back from reserved names',
      () {
    expect(
        ExportDocument.fromFeed(Datum(id: 12, messageTitle: 'A:/B*?"<>|'))
            .fileName,
        isNot(matches(RegExp(r'[<>:"/\\|?*]'))));
    expect(ExportDocument.fromFeed(Datum(id: 12, messageTitle: 'CON')).fileName,
        isNot('CON'));
  });

  test('exported Markdown renders explicit line breaks', () {
    final doc =
        ExportDocument.fromFeed(Datum(id: 1, message: '<p>第一行<br>第二行</p>'));
    final rendered = html.parse(md.markdownToHtml(doc.markdown));
    final paragraph = rendered
        .querySelectorAll('p')
        .firstWhere((e) => e.text.contains('第一行'));
    expect(paragraph.querySelector('br'), isNotNull);
  });
  test('image captions cannot inject raw HTML into exported Markdown', () {
    final doc = ExportDocument.fromFeed(Datum(id: 1), articles: [
      FeedArticle(
          type: 'image',
          url: 'https://img.example/a.png',
          description: '\n\n<script>alert(1)</script>\n\n[caption]'),
    ]);
    final rendered = html.parse(md.markdownToHtml(doc.markdown));
    expect(rendered.querySelectorAll('script'), isEmpty);
    expect(
        rendered.querySelector('img')?.attributes['alt'], contains('<script>'));
  });
  test('forwards retain available structured long-form body instead of summary',
      () {
    final doc = ExportDocument.fromFeed(Datum(
        id: 1,
        message: '转发',
        forwardSourceFeed: Datum(
            id: 2,
            message: '不应取摘要',
            messageRawOutput: jsonEncode([
              {'type': 'text', 'message': '完整首段'},
              {
                'type': 'image',
                'url': 'https://img.example/full.png',
                'description': '完整图'
              },
              {'type': 'text', 'message': '完整末段'},
            ]))));
    expect(doc.markdown, contains('完整末段'));
    expect(doc.markdown, isNot(contains('不应取摘要')));
    expect(doc.imageUrls, contains('https://img.example/full.png'));
  });
  test('ordered list start survives both formats', () {
    final doc =
        ExportDocument.fromFeed(Datum(id: 1, message: '5. 第五步\n6. 第六步'));
    expect(html.parse(doc.html).querySelector('ol')?.attributes['start'], '5');
    expect(doc.markdown, contains('5. 第五步'));
    expect(doc.markdown, contains('6. 第六步'));
  });
}
