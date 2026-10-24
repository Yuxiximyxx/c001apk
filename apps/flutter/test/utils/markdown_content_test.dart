import 'package:c001apk_flutter/utils/markdown_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  test('table serialization whitespace does not turn into visible blank lines',
      () {
    final result = MarkdownContent.parse(
        '## 表格\n\n| 平台 | 文件 |\n| --- | --- |\n| Android | app.apk |\n| Windows | app.zip |');
    final dom = html.parseFragment(result.html);
    expect(dom.querySelectorAll('br'), isEmpty);
    expect(dom.querySelectorAll('tr'), hasLength(3));
  });
  test('recognizes common README blocks and inline formatting', () {
    final result = MarkdownContent.parse('''## 标题

**加粗**、*斜体*、~~删除~~、`inline`

> 引用

- 第一项
  - 子项
- 第二项
- [x] 已完成
- [ ] 待完成

| 平台 | 版本 |
| --- | --- |
| Android | 1.3.2 |

---

```dart
final value = 1;
```
''');
    expect(result.isMarkdown, isTrue);
    final dom = html.parseFragment(result.html);
    for (final tag in [
      'h2',
      'strong',
      'em',
      'del',
      'code',
      'blockquote',
      'ul',
      'table',
      'hr',
      'pre'
    ]) {
      expect(dom.querySelector(tag), isNotNull, reason: tag);
    }
    expect(dom.text, contains('☑'));
    expect(dom.text, contains('☐'));
  });

  test('ordinary topics, models and punctuation do not enable Markdown', () {
    for (final source in [
      '#一加13# 今天更新了',
      '@朋友 看看',
      'POCO_X3_GT',
      'a_b_c',
      '1. 今天更新',
      '价格 > 100',
      '*',
      '| 只是一个竖线',
      'https://example.com/a_b',
      r'\*不是斜体\*',
      '<a class="feed-link-tag" href="/t/test">#test#</a>',
    ]) {
      expect(MarkdownContent.parse(source).isMarkdown, isFalse, reason: source);
    }
    expect(MarkdownContent.parse('**重点**').isMarkdown, isTrue);
    expect(MarkdownContent.parse('`value`').isMarkdown, isTrue);
  });

  test('code keeps emoji, tags, entities, spacing and line breaks literal', () {
    const source =
        '## 代码\n\n```text\n[哈哈哈]  <tag>\n**原样** &gt;\n```\n\n`[哈哈哈] <b>` [哈哈哈]';
    final result = MarkdownContent.parse(source);
    final dom = html.parseFragment(result.html);
    expect(dom.querySelector('pre code')!.text, '[哈哈哈]  <tag>\n**原样** &gt;\n');
    expect(dom.querySelectorAll('code').last.text, '[哈哈哈] <b>');
    expect(dom.querySelectorAll('img[data-emoji]'), hasLength(1));
    expect(MarkdownContent.parse(source, showEmoji: false).html,
        isNot(contains('data-emoji')));
  });

  test('Coolapk entities and native anchors coexist with Markdown', () {
    final result = MarkdownContent.parse(
        '## 正文<br>\n\n&gt; 引用\n\n<a class="feed-link-tag" href="/t/test?type=12">#test#</a> **重点**');
    final dom = html.parseFragment(result.html);
    expect(dom.querySelector('blockquote')!.text, contains('引用'));
    expect(dom.querySelector('a')!.attributes['href'], '/t/test?type=12');
    expect(dom.querySelector('a')!.text, '#test#');
    expect(dom.querySelector('strong')!.text, '重点');
  });

  test('raw HTML stays text and local or executable resources are rejected',
      () {
    final result = MarkdownContent.parse('''## 内容
<script>alert(1)</script>
<iframe src="https://example.com"></iframe>
<img src="file:///secret">
[坏链接](javascript:alert%281%29)
![本地](asset:secret.png)
![网络](https://example.com/image.png)
''');
    final dom = html.parseFragment(result.html);
    expect(dom.querySelector('script,iframe'), isNull);
    expect(dom.text, contains('<script>alert(1)</script>'));
    expect(dom.querySelectorAll('a'), isEmpty);
    expect(dom.querySelectorAll('img'), hasLength(1));
    expect(result.imageUrls, ['https://example.com/image.png']);
  });

  test('preview is bounded readable text and input remains untouched', () {
    final source = '## 标题\n\n${List.filled(50, '- **一条信息**').join('\n')}';
    final result = MarkdownContent.parse(source);
    expect(result.source, source);
    expect(result.preview, startsWith('标题'));
    expect(result.preview, isNot(contains('**')));
    expect(result.preview.length, lessThanOrEqualTo(241));
  });

  test('explicit release notes use Markdown without Coolapk normalization', () {
    final result = MarkdownContent.parse('更新说明\n下一行\n\n- 单项',
        explicit: true, coolapk: false);
    expect(result.isMarkdown, isTrue);
    expect(result.html, contains('<ul>'));
    expect(result.html, isNot(contains('<br')));
  });

  test('code inside quotes and multiline spans keeps transport-looking text',
      () {
    final quoted =
        MarkdownContent.parse('## 示例\n\n> ```html\n> a<br>b &gt; [哈哈哈]\n> ```');
    expect(html.parseFragment(quoted.html).querySelector('pre code')!.text,
        'a<br>b &gt; [哈哈哈]\n');
    final multiline = MarkdownContent.parse('## 示例\n\n`a<br>b\n&lt;tag&gt;`');
    expect(html.parseFragment(multiline.html).querySelector('code')!.text,
        'a<br>b &lt;tag&gt;');
  });

  test('document heading links have a generated target', () {
    final result = MarkdownContent.parse('[跳到下载](#下载)\n\n## 下载',
        explicit: true, coolapk: false);
    final dom = html.parseFragment(result.html);
    expect(
        Uri.decodeComponent(dom.querySelector('h2')!.attributes['id']!), '下载');
    expect(Uri.decodeComponent(dom.querySelector('a')!.attributes['href']!),
        '#下载');
  });

  test('native Coolapk scheme links retain supported application routes', () {
    final result = MarkdownContent.parse(
        '**内容** <a class="feed-link-url" href="coolmarket://feed/123">动态</a>');
    expect(
        html.parseFragment(result.html).querySelector('a')!.attributes['href'],
        'coolmarket://feed/123');
    expect(MarkdownContent.allowsUrl('coolmarket://feed/123', image: true),
        isFalse);
    expect(MarkdownContent.allowsUrl('coolmarket://unknown/123'), isFalse);
  });

  test(
      'Coolapk break delimiter is hidden while raw source and other comments stay intact',
      () {
    const source = '## 示例\n\n`message<!--break-->` `<!--note-->`';
    final result = MarkdownContent.parse(source);
    final code = html.parseFragment(result.html).querySelectorAll('code');
    expect(code.first.text, 'message');
    expect(code.last.text, '<!--note-->');
    expect(result.source, source);
    final release =
        MarkdownContent.parse(source, explicit: true, coolapk: false);
    expect(html.parseFragment(release.html).querySelector('code')!.text,
        'message<!--break-->');
  });
}
