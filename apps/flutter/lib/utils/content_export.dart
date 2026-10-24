import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../logic/model/feed/datum.dart';
import '../logic/model/feed_article/feed_article.dart';
import 'markdown_content.dart';

// Generated toJson maps retain nested model instances; round-trip the JSON
// encoding so fromJson receives maps at every level without editing generators.
Datum snapshotExportFeed(Datum feed) =>
    Datum.fromJson(jsonDecode(jsonEncode(feed)) as Map<String, dynamic>);

/// Preserve the server's popular order. A pin always precedes an ordinary reply.
List<Datum> selectExportComments(List<Datum> pinned, List<Datum> popular,
    {Set<String> blockedUids = const {}}) {
  final seen = <String>{};
  final result = <Datum>[];
  for (final reply in [
    ...pinned,
    ...popular.where((e) => (e.isTop ?? 0) > 0),
    ...popular,
  ]) {
    final id = '${reply.id ?? ''}';
    if (id.isEmpty || blockedUids.contains('${reply.uid}') || !seen.add(id)) {
      continue;
    }
    result.add(reply);
    if (result.length == 3) break;
  }
  return result;
}

class ExportDocument {
  ExportDocument._(this.title, this.id, this._body);

  final String title;
  final String id;
  final String _body;
  static const _escape = HtmlEscape();
  static String _e(String value) => _escape.convert(value);

  factory ExportDocument.fromFeed(Datum feed,
      {List<FeedArticle> articles = const [],
      List<Datum> comments = const [],
      List<String> notices = const []}) {
    final id = '${feed.id ?? ''}';
    final name = _text(feed.messageTitle ?? '').trim();
    final title = name.isNotEmpty
        ? name
        : _text(feed.title ?? '').trim().isNotEmpty
            ? _text(feed.title!).trim()
            : '${_author(feed)}的动态';
    final out = StringBuffer('<h1>${_e(title)}</h1>')
      ..write(_metadata(feed))
      ..write(
          '<p><a href="https://www.coolapk.com/feed/${Uri.encodeComponent(id)}">'
          'https://www.coolapk.com/feed/${Uri.encodeComponent(id)}</a><br>'
          '<a href="https://www.coolapk1s.com/feed/${Uri.encodeComponent(id)}">'
          'https://www.coolapk1s.com/feed/${Uri.encodeComponent(id)}</a></p>');
    out.write(_feedBody(feed, articles: articles));
    if (comments.isNotEmpty) {
      out.write('<hr><h2>精选评论（置顶优先，其余按热门排序）</h2>');
      for (final reply in comments.take(3)) {
        out.write('<section><h3>${(reply.isTop ?? 0) > 0 ? '【置顶】' : ''}'
            '${_e(_author(reply))}</h3>${_metadata(reply)}'
            '<p>赞：${_e('${reply.likenum ?? 0}')}</p>${_feedBody(reply)}</section>');
      }
    }
    for (final notice in notices) {
      out.write('<p>保存说明：${_e(notice)}</p>');
    }
    return ExportDocument._(title, id, _sanitize(out.toString()));
  }

  List<String> get imageUrls => parser
      .parseFragment(_body)
      .querySelectorAll('img')
      .map((e) => e.attributes['src']!)
      .toSet()
      .toList();

  String get fileName {
    var safe = title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'[.\s]+$'), '')
        .trim();
    safe = String.fromCharCodes(safe.runes.take(70));
    if (safe.isEmpty ||
        RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
                caseSensitive: false)
            .hasMatch(safe)) {
      safe = '动态';
    }
    return '$safe-${id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
  }

  String get markdown => '${_md(parser.parseFragment(_body)).trim()}\n';
  String get html => _page(_body);

  String offlineHtml(Map<String, String> images) {
    final body = parser.parseFragment(_body);
    for (final image in body.querySelectorAll('img')) {
      final url = image.attributes['src']!;
      final data = images[url];
      if (data != null &&
          RegExp(r'^data:image/(png|jpeg|gif|webp);base64,').hasMatch(data)) {
        image.attributes['src'] = data;
      } else {
        final link = dom.Element.tag('a')
          ..attributes['href'] = url
          ..text = '图片未保存：${image.attributes['alt'] ?? '查看来源'}';
        image.replaceWith(link);
      }
    }
    return _page(body.outerHtml);
  }

  String _page(String body) => '<!doctype html><html lang="zh-CN"><head>'
      '<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
      '<meta http-equiv="Content-Security-Policy" content="default-src &#39;none&#39;; '
      'img-src data:; style-src &#39;unsafe-inline&#39;; base-uri &#39;none&#39;; form-action &#39;none&#39;">'
      '<title>${_e(title)}</title><style>'
      'body{max-width:840px;margin:32px auto;padding:0 20px;color:#202124;background:#fff;'
      'font:16px/1.7 system-ui,sans-serif;overflow-wrap:anywhere}'
      'img{max-width:100%;height:auto}a{color:#1756a9}pre{overflow:auto;padding:16px;'
      'background:#f2f3f5;white-space:pre}code{font-family:monospace}'
      'table{border-collapse:collapse;display:block;overflow:auto}td,th{border:1px solid #bbb;padding:6px 12px}'
      'blockquote{border-left:4px solid #bbb;padding-left:16px;margin-left:0;color:#555}'
      'figcaption{color:#555}section{border-bottom:1px solid #ddd;padding-bottom:16px}'
      '@media print{body{margin:0;max-width:none}pre{white-space:pre-wrap}img{break-inside:avoid}}'
      '</style></head><body>$body</body></html>';

  static String _author(Datum data) =>
      data.userInfo?.username ?? data.username ?? '未知作者';

  static String _metadata(Datum data) {
    final seconds = int.tryParse('${data.dateline}');
    String date = '';
    if (seconds != null && seconds > 0 && seconds < 8640000000000) {
      date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
          .toLocal()
          .toIso8601String()
          .split('.')
          .first
          .replaceFirst('T', ' ');
    }
    return '<p>作者：${_e(_author(data))}${date.isEmpty ? '' : '<br>发布时间：$date'}</p>';
  }

  static String _feedBody(Datum data,
      {List<FeedArticle> articles = const [], int depth = 0}) {
    final out = StringBuffer();
    if (articles.isEmpty &&
        (data.messageRawOutput ?? '').isNotEmpty &&
        data.messageRawOutput != 'null') {
      try {
        final raw = jsonDecode(data.messageRawOutput!);
        if (raw is! List) throw const FormatException();
        articles = raw
            .map((e) =>
                FeedArticle.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((e) => {'text', 'image', 'shareUrl'}.contains(e.type))
            .toList();
        if (articles.isNotEmpty && (data.messageCover ?? '').isNotEmpty) {
          articles = [
            FeedArticle(type: 'image', url: data.messageCover),
            ...articles
          ];
        }
      } catch (_) {
        out.write('<p>图文结构未能解析，以下仅保存已取得的摘要。</p>');
      }
    }
    if (articles.isNotEmpty) {
      for (final part in articles) {
        switch (part.type) {
          case 'title':
            // The document already has its own title.
            break;
          case 'text':
            out.write(_content(part.message ?? ''));
          case 'image':
            out.write(_image(part.url ?? '', part.description ?? ''));
          case 'shareUrl':
            out.write(
                '<p><a href="${_e(part.url ?? '')}">${_e(part.title ?? part.url ?? '')}</a></p>');
        }
      }
    } else {
      out.write(_content(data.message ?? ''));
      for (final url in data.picArr ?? <String>[]) {
        out.write(_image(url, ''));
      }
    }
    final forward = data.forwardSourceFeed;
    if (forward != null && depth < 3) {
      out.write('<blockquote><p>转发自：${_e(_author(forward))}</p>');
      if ((forward.messageTitle ?? '').isNotEmpty) {
        out.write('<h2>${_e(_text(forward.messageTitle!))}</h2>');
      }
      out.write(_feedBody(forward, depth: depth + 1));
      out.write('</blockquote>');
    } else if (forward == null && (data.forwardSourceType ?? '').isNotEmpty) {
      out.write('<p>转发内容已不可用</p>');
    }
    return out.toString();
  }

  static String _image(String url, String caption) =>
      '<figure><img src="${_e(url)}" alt="${_e(caption)}">'
      '${caption.isEmpty ? '' : '<figcaption>${_e(caption)}</figcaption>'}</figure>';

  static String _content(String value) {
    final parsed =
        MarkdownContent.parse(value, showEmoji: false, forExport: true);
    if (parsed.isMarkdown) return parsed.html;
    // Native bodies mix HTML and plain newlines. Do not modify preformatted code.
    final tree = parser.parseFragment(value.replaceAll('<!--break-->', ''));
    void lineBreaks(dom.Node node) {
      if (node is dom.Element && ['pre', 'code'].contains(node.localName)) {
        return;
      }
      for (final child in node.nodes.toList()) {
        if (child is dom.Text && child.data.contains('\n')) {
          final parts = child.data.split('\n');
          final fragment = dom.DocumentFragment();
          for (var i = 0; i < parts.length; i++) {
            if (i > 0) fragment.append(dom.Element.tag('br'));
            fragment.append(dom.Text(parts[i]));
          }
          child.replaceWith(fragment);
        } else {
          lineBreaks(child);
        }
      }
    }

    lineBreaks(tree);
    return '<div>${tree.outerHtml}</div>';
  }

  static String _text(String value) => parser.parseFragment(value).text ?? '';

  static String? _url(String value, {bool image = false}) {
    if (value.isEmpty) return null;
    if (!image && value.startsWith('/') && !value.startsWith('//')) {
      value = 'https://www.coolapk.com$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        value.contains(RegExp(r'[\x00-\x20\x7f\\]'))) {
      return null;
    }
    return uri.toString();
  }

  static String _sanitize(String value) {
    final root = parser.parseFragment(value);
    const allowed = {
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'p',
      'br',
      'div',
      'section',
      'strong',
      'b',
      'em',
      'i',
      'del',
      's',
      'u',
      'blockquote',
      'pre',
      'code',
      'ul',
      'ol',
      'li',
      'hr',
      'table',
      'thead',
      'tbody',
      'tfoot',
      'tr',
      'th',
      'td',
      'a',
      'img',
      'figure',
      'figcaption',
      'input'
    };
    void clean(dom.Node node) {
      for (final child in node.nodes.toList()) {
        if (child is dom.Comment) {
          child.remove();
          continue;
        }
        if (child is! dom.Element) continue;
        final tag = child.localName;
        if ({
          'script',
          'style',
          'iframe',
          'object',
          'embed',
          'svg',
          'math',
          'form',
          'video',
          'audio'
        }.contains(tag)) {
          child.remove();
          continue;
        }
        clean(child);
        if (!allowed.contains(tag)) {
          child.replaceWith(
              dom.DocumentFragment()..nodes.addAll(child.nodes.toList()));
          continue;
        }
        final attrs = Map<Object, String>.from(child.attributes);
        child.attributes.clear();
        if (tag == 'a' || tag == 'img') {
          final key = tag == 'img' ? 'src' : 'href';
          final url = _url(attrs[key] ?? '', image: tag == 'img');
          if (url != null) child.attributes[key] = url;
          if (tag == 'img') {
            if (url == null) {
              child.remove();
              continue;
            }
            child.attributes['alt'] = attrs['alt'] ?? '';
          }
        }
        if (tag == 'input') {
          if (attrs['type'] != 'checkbox') {
            child.remove();
            continue;
          }
          child.attributes.addAll({'type': 'checkbox', 'disabled': ''});
          if (attrs.containsKey('checked')) child.attributes['checked'] = '';
        }
        if (tag == 'ol' && int.tryParse(attrs['start'] ?? '') != null) {
          child.attributes['start'] = '${int.parse(attrs['start']!)}';
        }
        if (tag == 'code' &&
            RegExp(r'^language-[\w+-]+$').hasMatch(attrs['class'] ?? '')) {
          child.attributes['class'] = attrs['class']!;
        }
      }
    }

    clean(root);
    return root.outerHtml;
  }

  static String _md(dom.Node node, {int indent = 0}) {
    if (node is dom.Text) {
      return node.data
          .replaceAll('\\', r'\\')
          .replaceAllMapped(RegExp(r'([`*_[\]<>])'), (m) => '\\${m[0]}');
    }
    if (node is! dom.Element) {
      return node.nodes.map((e) => _md(e, indent: indent)).join();
    }
    String children() => node.nodes.map((e) => _md(e, indent: indent)).join();
    switch (node.localName) {
      case 'br':
        return '  \n';
      case 'hr':
        return '\n\n---\n\n';
      case 'p':
      case 'div':
      case 'section':
      case 'figure':
        return '\n\n${children().trim()}\n\n';
      case 'figcaption':
        return '\n\n${children().trim()}\n\n';
      case 'strong':
      case 'b':
        return '**${children()}**';
      case 'em':
      case 'i':
        return '*${children()}*';
      case 'del':
      case 's':
        return '~~${children()}~~';
      case 'a':
        final href = node.attributes['href'];
        return href == null ? children() : '[${children()}](${_mdUrl(href)})';
      case 'img':
        final caption = (node.attributes['alt'] ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        return '![${_md(dom.Text(caption))}](${_mdUrl(node.attributes['src']!)})';
      case 'input':
        return node.attributes.containsKey('checked') ? '[x] ' : '[ ] ';
      case 'pre':
        final code = node.querySelector('code');
        final text = code?.text ?? node.text;
        var fence = '```';
        while (text.contains(fence)) {
          fence += '`';
        }
        final language =
            (code?.attributes['class'] ?? '').replaceFirst('language-', '');
        return '\n\n$fence$language\n${text.replaceFirst(RegExp(r'\n$'), '')}\n$fence\n\n';
      case 'code':
        var ticks = '`';
        while (node.text.contains(ticks)) {
          ticks += '`';
        }
        return '$ticks ${node.text} $ticks';
      case 'blockquote':
        return '\n\n${children().trim().split('\n').map((e) => '> $e').join('\n')}\n\n';
      case 'ul':
      case 'ol':
        var count = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        final lines = <String>[];
        for (final item in node.children.where((e) => e.localName == 'li')) {
          final marker = node.localName == 'ol' ? '${count++}. ' : '- ';
          final content =
              item.nodes.map((e) => _md(e, indent: indent + 1)).join().trim();
          final parts = content.split('\n');
          lines.add('$marker${parts.first}');
          lines.addAll(parts.skip(1).map((e) => '${' ' * marker.length}$e'));
        }
        return '\n\n${lines.join('\n')}\n\n';
      case 'table':
        final rows = node.querySelectorAll('tr');
        if (rows.isEmpty) return '';
        final values = rows
            .map((row) => row.children
                .where((e) => ['th', 'td'].contains(e.localName))
                .map((cell) => _md(cell)
                    .replaceAll('|', r'\|')
                    .replaceAll('\n', ' ')
                    .trim())
                .toList())
            .toList();
        final columns =
            values.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
        String row(List<String> cells) => '| ${[
              ...cells,
              ...List.filled(columns - cells.length, '')
            ].join(' | ')} |';
        return '\n\n${row(values.first)}\n${row(List.filled(columns, '---'))}\n'
            '${values.skip(1).map(row).join('\n')}\n\n';
      default:
        if (RegExp(r'^h[1-6]$').hasMatch(node.localName ?? '')) {
          return '\n\n${'#' * int.parse(node.localName![1])} ${children().trim()}\n\n';
        }
        return children();
    }
  }

  static String _mdUrl(String value) =>
      value.replaceAll('(', '%28').replaceAll(')', '%29');
}
