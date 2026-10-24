import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

const sampleBody = '# 公告正文\n\n**支持 Markdown**\n\n- 第一项\n- 第二项\n';

Map<String, dynamic> noticeJson(String id,
        {int content = 1, int reminder = 1, bool important = false}) =>
    {
      'id': id,
      'title': '公告 $id',
      'summary': '摘要 $id',
      'publishedAt': '2026-10-23T08:00:00Z',
      'contentRevision': content,
      'reminderRevision': reminder,
      'important': important,
      'path': '$id-$content.md',
      'sha256': sha256.convert(utf8.encode(sampleBody)).toString(),
    };

Map<String, dynamic> indexJson(int revision, List<dynamic> entries) => {
      'schemaVersion': 1,
      'revision': revision,
      'announcements': entries,
    };

class AnnouncementAdapter implements HttpClientAdapter {
  Map<String, dynamic> index = indexJson(1, [noticeJson('a')]);
  final List<RequestOptions> requests = [];
  int status = 200;
  int bodyStatus = 200;
  String body = sampleBody;
  Completer<void>? pendingIndex;
  Completer<void>? pendingBody;
  final indexStarted = Completer<void>();
  final bodyStarted = Completer<void>();

  int get bodyRequests =>
      requests.where((r) => !r.uri.path.endsWith('/index.json')).length;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<dynamic>? cancelFuture) async {
    requests.add(options);
    final isIndex = options.uri.path.endsWith('/index.json');
    if (isIndex && !indexStarted.isCompleted) indexStarted.complete();
    if (!isIndex && !bodyStarted.isCompleted) bodyStarted.complete();
    await (isIndex ? pendingIndex?.future : pendingBody?.future);
    return ResponseBody.fromString(
        isIndex ? jsonEncode(index) : body, isIndex ? status : bodyStatus,
        headers: {
          Headers.contentTypeHeader: [
            isIndex ? 'application/json' : 'text/plain'
          ]
        });
  }

  @override
  void close({bool force = false}) {}
}
