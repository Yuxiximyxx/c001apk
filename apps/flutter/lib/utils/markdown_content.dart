import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

import 'emoji_util.dart';

/// Display-only conversion. Never writes the source back to a feed or Hive.
class MarkdownContent {
  const MarkdownContent._(
      this.source, this.html, this.isMarkdown, this.preview, this.imageUrls);

  final String source;
  final String html;
  final bool isMarkdown;
  final String preview;
  final List<String> imageUrls;

  static final _cache = <(String, bool, bool, bool, bool), MarkdownContent>{};
  static int _cachedCharacters = 0;
  static const _escape = HtmlEscape(HtmlEscapeMode.element);

  static MarkdownContent parse(String source,
      {bool explicit = false,
      bool coolapk = true,
      bool showEmoji = true,
      bool forExport = false}) {
    final key = (source, explicit, coolapk, showEmoji, forExport);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    // Bound synchronous parsing and retained source on scrolling feed cards.
    if (source.length > 200000) return _plain(source);
    MarkdownContent result;
    try {
      final links = <md.Element>[];
      final input = coolapk ? _normalize(source, links) : source;
      final document = md.Document(
        withDefaultBlockSyntaxes: false,
        extensionSet: md.ExtensionSet(const [
          md.EmptyBlockSyntax(),
          md.FencedCodeBlockSyntax(),
          md.TableSyntax(),
          md.UnorderedListWithCheckboxSyntax(),
          md.OrderedListWithCheckboxSyntax(),
          md.SetextHeaderWithIdSyntax(),
          md.HeaderWithIdSyntax(),
          md.CodeBlockSyntax(),
          md.BlockquoteSyntax(),
          md.HorizontalRuleSyntax(),
          md.UnorderedListSyntax(),
          md.OrderedListSyntax(),
          md.LinkReferenceDefinitionSyntax(),
          md.ParagraphSyntax(),
        ], [
          _NativeLinkSyntax(links),
          md.StrikethroughSyntax(),
          md.AutolinkExtensionSyntax(),
        ]),
      );
      final nodes = document.parse(input);
      final detected = explicit || _detect(nodes, input);
      if (!detected) {
        result = _plain(source);
      } else {
        final fragment = html_parser.parseFragment(md.renderToHtml(nodes));
        final headingIds = <String, int>{};
        for (final heading in fragment.querySelectorAll('h1,h2,h3,h4,h5,h6')) {
          final slug = heading.text
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}_\s-]', unicode: true), '')
              .replaceAll(RegExp(r'\s'), '-');
          final count = headingIds[slug] ?? 0;
          headingIds[slug] = count + 1;
          heading.attributes['id'] =
              Uri.encodeComponent(count == 0 ? slug : '$slug-$count');
        }
        final images = <String>[];
        _clean(fragment, images,
            coolapk: coolapk, showEmoji: showEmoji, forExport: forExport);
        final readable = _readable(fragment).trim();
        final preview = readable.runes.take(240).toList();
        result = MarkdownContent._(
          source,
          fragment.outerHtml,
          true,
          String.fromCharCodes(preview) +
              (readable.runes.length > 240 ? '…' : ''),
          List.unmodifiable(images),
        );
      }
    } catch (_) {
      // A malformed/unsupported document must not hide the original post.
      result = _plain(source);
    }
    _cache[key] = result;
    _cachedCharacters += source.length;
    while (_cache.length > 64 || _cachedCharacters > 500000) {
      _cachedCharacters -= _cache.keys.first.$1.length;
      _cache.remove(_cache.keys.first);
    }
    return result;
  }

  static MarkdownContent _plain(String source) =>
      MarkdownContent._(source, '', false, source, const []);

  static bool _detect(List<md.Node> nodes, String input) {
    var listItems = 0;
    var found = false;
    void visit(md.Node node) {
      if (node is! md.Element || node.attributes['data-native'] == '1') return;
      if (RegExp(r'^h[1-6]$').hasMatch(node.tag) ||
          ['pre', 'table', 'strong', 'em', 'del', 'code', 'img', 'input']
              .contains(node.tag)) {
        found = true;
      }
      if (node.tag == 'a' && RegExp(r'\[[^\]]+\]').hasMatch(input)) {
        found = true;
      }
      if (node.tag == 'blockquote' &&
          RegExp(r'^\s*>\s', multiLine: true).hasMatch(input)) {
        found = true;
      }
      if (node.tag == 'li') listItems++;
      for (final child in node.children ?? <md.Node>[]) {
        visit(child);
      }
    }

    for (final node in nodes) {
      visit(node);
    }
    return found || listItems >= 2;
  }

  /// Only HTTP(S), document anchors and app-relative links enter this renderer.
  static bool allowsUrl(String value, {bool image = false}) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        value.contains(RegExp(r'[\x00-\x20\x7f\\]')) ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    if (uri.scheme == 'coolmarket' && !image) {
      const routes = {'feed', 'event', 'u', 'apk', 'game', 't', 'product'};
      final segments = {
        'coolapk.com',
        'www.coolapk.com',
        'm.coolapk.com',
        'com.coolapk.market',
      }.contains(uri.host)
          ? uri.pathSegments
          : [uri.host, ...uri.pathSegments];
      return segments.length >= 2 &&
          routes.contains(segments.first) &&
          segments[1].trim().isNotEmpty;
    }
    if (!uri.hasScheme) {
      return !image && !value.startsWith('//') && value.isNotEmpty;
    }
    return ['https', 'http'].contains(uri.scheme) && uri.host.isNotEmpty;
  }

  static String _normalize(String source, List<md.Element> links) {
    // Coolapk's body carries this exact display delimiter, even inside code
    // spans in real articles. Keep source intact and do not strip other HTML
    // comments or apply this transport rule to release notes.
    final input =
        source.replaceAll('<!--break-->', '').replaceAll('\r\n', '\n');
    final out = StringBuffer();
    String? fenceCharacter;
    var fenceLength = 0;
    String? inlineDelimiter;
    final fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');
    final runs = RegExp(r'`+');
    var lineOffset = 0;
    for (final line in input.split('\n')) {
      final containerLine = line
          .replaceFirst(RegExp(r'^(?: {0,3}>[ \t]?)+'), '')
          .replaceFirst(RegExp(r'^ {0,3}(?:[-+*]|[0-9]+[.)])[ \t]+'), '');
      final opening = fence.firstMatch(containerLine);
      if (fenceCharacter != null) {
        out.writeln(line);
        if (opening != null &&
            opening[1]![0] == fenceCharacter &&
            opening[1]!.length >= fenceLength &&
            containerLine.substring(opening.end).trim().isEmpty) {
          fenceCharacter = null;
        }
      } else if (inlineDelimiter == null && opening != null) {
        fenceCharacter = opening[1]![0];
        fenceLength = opening[1]!.length;
        out.writeln(line);
      } else if (inlineDelimiter == null &&
          (line.startsWith('    ') || line.startsWith('\t'))) {
        out.writeln(line);
      } else {
        var position = 0;
        for (final run in runs.allMatches(line)) {
          final text = line.substring(position, run.start);
          out.write(inlineDelimiter == null ? _normalText(text, links) : text);
          final delimiter = run[0]!;
          if (inlineDelimiter == delimiter) {
            inlineDelimiter = null;
          } else if (inlineDelimiter == null) {
            var slashes = 0;
            for (var i = run.start - 1; i >= 0 && line[i] == '\\'; i--) {
              slashes++;
            }
            final exactRun = RegExp('(?<!`)${RegExp.escape(delimiter)}(?!`)');
            if (slashes.isEven &&
                exactRun.hasMatch(input.substring(lineOffset + run.end))) {
              inlineDelimiter = delimiter;
            }
          }
          out.write(delimiter);
          position = run.end;
        }
        final rest = line.substring(position);
        out.write(inlineDelimiter == null ? _normalText(rest, links) : rest);
        out.writeln();
      }
      lineOffset += line.length + 1;
    }
    return out.toString();
  }

  static String _normalText(String source, List<md.Element> links) {
    final anchored = source.replaceAllMapped(
        RegExp(r'<a\b[^>]*>[\s\S]*?</a>', caseSensitive: false), (match) {
      final anchor = html_parser.parseFragment(match[0]!).querySelector('a');
      if (anchor == null ||
          !anchor.classes.any((c) => c.startsWith('feed-link-'))) {
        return match[0]!;
      }
      final href = anchor.attributes['href'] ?? '';
      if (!allowsUrl(href)) return anchor.text;
      final node = md.Element.text('a', _escape.convert(anchor.text))
        ..attributes['href'] = href
        ..attributes['data-native'] = '1';
      links.add(node);
      return '\uE000C001${links.length - 1}\uE001';
    });
    return anchored
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?p\s*>', caseSensitive: false), '\n\n')
        .replaceAllMapped(RegExp(r'&(?:#[0-9]+|#x[0-9a-fA-F]+|[a-zA-Z]+);'),
            (m) => html_parser.parseFragment(m[0]!).text ?? m[0]!);
  }

  static void _clean(dom.Node parent, List<String> images,
      {required bool coolapk,
      required bool showEmoji,
      bool inCode = false,
      bool forExport = false}) {
    for (final node in parent.nodes.toList()) {
      if (node is dom.Element) {
        final tag = node.localName;
        if (tag == 'input' && !forExport) {
          node.replaceWith(
              dom.Text(node.attributes.containsKey('checked') ? '☑ ' : '☐ '));
          continue;
        }
        if (tag == 'a' && !allowsUrl(node.attributes['href'] ?? '')) {
          node.replaceWith(dom.Text(node.text));
          continue;
        }
        if (tag == 'img') {
          final src = node.attributes['src'] ?? '';
          if (!allowsUrl(src, image: true)) {
            node.replaceWith(dom.Text(node.attributes['alt'] ?? ''));
            continue;
          }
          if (!images.contains(src)) images.add(src);
        }
        node.attributes.removeWhere((key, value) =>
            !{
              'href',
              'src',
              'alt',
              'title',
              'start',
              'align',
              'id',
            }.contains(key) &&
            !(forExport &&
                ((tag == 'code' && key == 'class') ||
                    (tag == 'input' &&
                        {'type', 'checked', 'disabled'}.contains(key)))));
        _clean(node, images,
            coolapk: coolapk,
            showEmoji: showEmoji,
            forExport: forExport,
            inCode: inCode || tag == 'pre' || tag == 'code');
      } else if (node is dom.Text && !inCode) {
        final emoji = showEmoji ? RegExp(r'\[[^\]\n]+\]') : RegExp(r'(?!)');
        var decorated = _escape.convert(node.data).replaceAllMapped(emoji, (m) {
          final value = EmojiUtil.emojiMap[m[0]!];
          if (value == null) return m[0]!;
          return '<img data-emoji="${const HtmlEscape().convert(value)}" alt="${m[0]}">';
        });
        if (coolapk &&
            parent is dom.Element &&
            ({'p', 'strong', 'em', 'del', 'a'}.contains(parent.localName) ||
                (parent.localName == 'li' && node.data.trim().isNotEmpty))) {
          decorated = decorated.replaceAll('\n', '<br>');
        }
        if (decorated != _escape.convert(node.data)) {
          final parts = html_parser.parseFragment(decorated).nodes.toList();
          final index = parent.nodes.indexOf(node);
          parent.nodes.insertAll(index, parts);
          node.remove();
        }
      }
    }
  }

  static String _readable(dom.Node node) {
    if (node is dom.Text) return node.data;
    if (node is dom.Element && node.localName == 'img') {
      return node.attributes['alt'] ?? '';
    }
    final text = node.nodes.map(_readable).join();
    if (node is dom.Element &&
        {
          'p',
          'li',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
          'tr',
          'pre',
          'blockquote',
          'br'
        }.contains(node.localName)) {
      return '$text\n';
    }
    if (node is dom.Element && {'th', 'td'}.contains(node.localName)) {
      return '$text ';
    }
    return text;
  }
}

class _NativeLinkSyntax extends md.InlineSyntax {
  _NativeLinkSyntax(this.links) : super('\uE000C001([0-9]+)\uE001');
  final List<md.Element> links;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final index = int.parse(match[1]!);
    if (index >= links.length) return false;
    parser.addNode(links[index]);
    return true;
  }
}
