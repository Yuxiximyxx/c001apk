import 'dart:convert';

class AnnouncementFailure implements Exception {
  const AnnouncementFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Metadata only. No Markdown is downloaded while parsing an index.
class Announcement {
  const Announcement._(
      this.id,
      this.title,
      this.summary,
      this.publishedAt,
      this.contentRevision,
      this.reminderRevision,
      this.important,
      this.path,
      this.digest,
      this.withdrawn,
      this.expiresAt);

  final String id, title, summary, path, digest;
  final DateTime publishedAt;
  final DateTime? expiresAt;
  final int contentRevision, reminderRevision;
  final bool important, withdrawn;

  bool activeAt(DateTime now) =>
      !withdrawn && (expiresAt == null || now.isBefore(expiresAt!));
  String get cacheKey => '$id:$contentRevision:$digest';

  factory Announcement.fromJson(dynamic value) {
    if (value is! Map) throw const FormatException('公告项格式异常');
    String string(String key, int max, {bool empty = false}) {
      final text = value[key];
      if (text is! String ||
          text.length > max ||
          (!empty && text.trim().isEmpty)) {
        throw const FormatException('公告字段格式异常');
      }
      return text;
    }

    final id = string('id', 100);
    final path = string('path', 200);
    final digest = string('sha256', 64);
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*$').hasMatch(id) ||
        !RegExp(r'^[a-zA-Z0-9_-]+(?:/[a-zA-Z0-9_-]+)*\.md$').hasMatch(path) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('公告路径或标识格式异常');
    }
    final content = value['contentRevision'];
    final reminder = value['reminderRevision'];
    final important = value['important'];
    final withdrawn = value['withdrawn'] ?? false;
    if (content is! int ||
        content < 1 ||
        reminder is! int ||
        reminder < 1 ||
        important is! bool ||
        withdrawn is! bool) {
      throw const FormatException('公告修订格式异常');
    }
    DateTime date(dynamic source) {
      if (source is! String ||
          !RegExp(r'T.*(?:Z|[+-]\d{2}:\d{2})$').hasMatch(source)) {
        throw const FormatException('公告日期缺少时区');
      }
      return DateTime.parse(source).toUtc();
    }

    return Announcement._(
        id,
        string('title', 200),
        string('summary', 1000, empty: true),
        date(value['publishedAt']),
        content,
        reminder,
        important,
        path,
        digest,
        withdrawn,
        value['expiresAt'] == null ? null : date(value['expiresAt']));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'summary': summary,
        'publishedAt': publishedAt.toIso8601String(),
        'contentRevision': contentRevision,
        'reminderRevision': reminderRevision,
        'important': important,
        'path': path,
        'sha256': digest,
        'withdrawn': withdrawn,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      };
}

class AnnouncementIndex {
  const AnnouncementIndex(this.revision, this.entries);
  final int revision;
  final List<Announcement> entries;

  factory AnnouncementIndex.fromJson(dynamic value) {
    if (value is! Map ||
        value['schemaVersion'] != 1 ||
        value['revision'] is! int ||
        value['revision'] < 1 ||
        value['announcements'] is! List ||
        (value['announcements'] as List).length > 2000) {
      throw const FormatException('公告表格式异常');
    }
    final entries =
        (value['announcements'] as List).map(Announcement.fromJson).toList();
    if (entries.map((e) => e.id).toSet().length != entries.length) {
      throw const FormatException('公告 ID 重复');
    }
    entries.sort((a, b) {
      final date = b.publishedAt.compareTo(a.publishedAt);
      return date == 0 ? b.id.compareTo(a.id) : date;
    });
    return AnnouncementIndex(value['revision'], List.unmodifiable(entries));
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'revision': revision,
        'announcements': entries.map((e) => e.toJson()).toList(),
      };
  String get fingerprint => jsonEncode(toJson());
}
