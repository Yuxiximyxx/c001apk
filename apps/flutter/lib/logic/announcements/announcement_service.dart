import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'announcement.dart';

enum SyncReason { coldStart, resume, inbox, manual }

/// A public, account-independent feed. Never use the Coolapk Request client.
class AnnouncementService extends ChangeNotifier {
  AnnouncementService(this._box,
      {Dio? dio, DateTime Function()? clock, Uri? baseUri})
      : _dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8))),
        _clock = clock ?? DateTime.now,
        baseUri = baseUri ??
            Uri.parse(
                'https://raw.githubusercontent.com/TG-Twilight/c001apk/announcements/announcements/') {
    final state = _box.get('state');
    if (state is Map) {
      try {
        if (state['index'] != null) {
          _index = AnnouncementIndex.fromJson(state['index']);
        }
        void receipts(String key, Map<String, int> target) {
          if (state[key] is Map) {
            for (final entry in (state[key] as Map).entries) {
              if (entry.key is String && entry.value is int) {
                target[entry.key] = entry.value;
              }
            }
          }
        }

        receipts('read', _read);
        receipts('prompted', _prompted);
        if (state['bodies'] is Map) {
          for (final entry in (state['bodies'] as Map).entries) {
            if (entry.key is String && entry.value is String) {
              _bodies[entry.key] = entry.value;
            }
          }
        }
        _automaticEnabled = state['automaticEnabled'] != false;
        _lastSuccess = DateTime.tryParse('${state['lastSuccess']}');
        _trimBodies();
      } catch (_) {
        // A corrupt cache must not break launch or expose raw stored content.
        _index = null;
        _bodies.clear();
      }
    }
    _scheduleExpiry();
  }

  final Box<dynamic> _box;
  final Dio _dio;
  final DateTime Function() _clock;
  final Uri baseUri;
  AnnouncementIndex? _index;
  final Map<String, int> _read = {}, _prompted = {};
  final Map<String, String> _bodies = {};
  final Map<String, Future<String>> _bodyLoads = {};
  Future<String?>? _syncing;
  Future<void> _saving = Future.value();
  DateTime? _lastSuccess, _lastAttempt;
  bool _coldChecked = false, _automaticEnabled = true, _disposed = false;
  Timer? _expiryTimer;

  List<Announcement> get items => List.unmodifiable(
      _index?.entries.where((e) => e.activeAt(_clock())) ?? <Announcement>[]);
  bool get automaticEnabled => _automaticEnabled;
  bool get isSyncing => _syncing != null;
  bool isRead(Announcement item) =>
      (_read[item.id] ?? 0) >= item.reminderRevision;
  int get unreadCount => items.where((e) => !isRead(e)).length;

  Announcement? get pendingImportant {
    final important = items.where((e) => e.important);
    if (important.isEmpty) return null;
    final latest = important.first;
    return !isRead(latest) &&
            (_prompted[latest.id] ?? 0) < latest.reminderRevision
        ? latest
        : null;
  }

  /// Re-check after every async boundary: a table may have withdrawn this item.
  bool isCurrent(Announcement item) => items.any((e) =>
      e.id == item.id &&
      e.cacheKey == item.cacheKey &&
      e.reminderRevision == item.reminderRevision);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _save() {
    final snapshot = {
      'index': _index?.toJson(),
      'read': Map.of(_read),
      'prompted': Map.of(_prompted),
      'bodies': Map.of(_bodies),
      'lastSuccess': _lastSuccess?.toIso8601String(),
      'automaticEnabled': _automaticEnabled,
    };
    final write = _saving.then((_) => _box.put('state', snapshot));
    _saving = write.catchError((Object _) {});
    return write;
  }

  Future<void> setAutomaticEnabled(bool enabled) async {
    _automaticEnabled = enabled;
    await _save();
    _changed();
  }

  Future<void> markRead(Announcement item) async {
    if (!isCurrent(item)) return;
    _read[item.id] = item.reminderRevision;
    await _save();
    _changed();
  }

  Future<void> markPrompted(Announcement item) async {
    if (!isCurrent(item)) return;
    _prompted[item.id] = item.reminderRevision;
    await _save();
    _changed();
  }

  Future<void> clearBodyCache() async {
    _bodies.clear();
    await _save();
    _changed();
  }

  Future<String?> sync(SyncReason reason) {
    if (_syncing != null) return _syncing!;
    final automatic =
        reason == SyncReason.coldStart || reason == SyncReason.resume;
    if (automatic && !_automaticEnabled) return Future.value();
    final now = _clock();
    if (reason == SyncReason.coldStart && _coldChecked) return Future.value();
    if (reason == SyncReason.coldStart) _coldChecked = true;
    if (reason != SyncReason.manual &&
        reason != SyncReason.coldStart &&
        _lastSuccess != null &&
        now.difference(_lastSuccess!) <
            (reason == SyncReason.resume
                ? const Duration(hours: 6)
                : const Duration(minutes: 15))) {
      return Future.value();
    }
    if (reason != SyncReason.manual &&
        _lastAttempt != null &&
        now.difference(_lastAttempt!) < const Duration(minutes: 1)) {
      return Future.value();
    }
    _lastAttempt = now;
    final done = Completer<String?>();
    _syncing = done.future;
    _changed();
    () async {
      String? error;
      try {
        final response = await _dio.get<String>(
            baseUri.resolve('index.json').toString(),
            options: Options(
                responseType: ResponseType.plain,
                followRedirects: false,
                headers: {
                  'Accept': 'application/json',
                  'User-Agent': 'c001apk-announcements'
                }));
        final text = response.data;
        if (text == null || utf8.encode(text).length > 1024 * 1024) {
          throw const FormatException('公告表过大');
        }
        final next = AnnouncementIndex.fromJson(jsonDecode(text));
        final previous = _index;
        if (previous != null) {
          if (next.revision < previous.revision ||
              (next.revision == previous.revision &&
                  next.fingerprint != previous.fingerprint)) {
            throw const FormatException('公告表版本冲突');
          }
          final old = {for (final e in previous.entries) e.id: e};
          for (final e in next.entries) {
            final before = old[e.id];
            if (before != null &&
                (e.contentRevision < before.contentRevision ||
                    e.reminderRevision < before.reminderRevision ||
                    (e.contentRevision == before.contentRevision &&
                        (e.digest != before.digest ||
                            e.path != before.path)))) {
              throw const FormatException('公告修订冲突');
            }
          }
        }
        _index = next;
        final activeIds = items.map((e) => e.id).toSet();
        _bodies
            .removeWhere((key, _) => !activeIds.contains(key.split(':').first));
        // Older important items remain unread, but never become surprise popups
        // after the latest item is read, removed or expires.
        for (final older in items.where((e) => e.important).skip(1)) {
          _prompted[older.id] = older.reminderRevision;
        }
        _lastSuccess = now;
        _scheduleExpiry();
        await _save();
      } catch (_) {
        error = '公告同步失败，请稍后重试；已缓存的公告仍可查看';
      } finally {
        _syncing = null;
        done.complete(error);
        _changed();
      }
    }();
    return done.future;
  }

  Future<String> loadBody(Announcement item) {
    if (!isCurrent(item)) {
      return Future.error(const AnnouncementFailure('公告已更新或撤回，请刷新列表'));
    }
    final cached = _bodies.remove(item.cacheKey);
    if (cached != null) {
      _bodies[item.cacheKey] = cached;
      return Future.value(cached);
    }
    final pending = _bodyLoads[item.cacheKey];
    if (pending != null) return pending;
    final done = Completer<String>();
    _bodyLoads[item.cacheKey] = done.future;
    () async {
      try {
        final response = await _dio.get<List<int>>(
            baseUri.resolve(item.path).toString(),
            options: Options(
                responseType: ResponseType.bytes,
                followRedirects: false,
                headers: {
                  'Accept': 'text/plain',
                  'User-Agent': 'c001apk-announcements'
                }));
        final bytes = response.data;
        if (bytes == null ||
            bytes.isEmpty ||
            bytes.length > 256 * 1024 ||
            sha256.convert(bytes).toString() != item.digest) {
          throw const AnnouncementFailure('公告正文尚未同步或校验失败，请稍后重试');
        }
        final body = utf8.decode(bytes);
        if (!isCurrent(item)) {
          throw const AnnouncementFailure('公告已更新或撤回，请刷新列表');
        }
        _bodies[item.cacheKey] = body;
        _trimBodies();
        await _save();
        if (!isCurrent(item)) {
          throw const AnnouncementFailure('公告已更新或撤回，请刷新列表');
        }
        done.complete(body);
      } catch (error) {
        done.completeError(error is AnnouncementFailure
            ? error
            : const AnnouncementFailure('公告正文加载失败，请检查网络后重试'));
      } finally {
        _bodyLoads.remove(item.cacheKey);
      }
    }();
    return done.future;
  }

  void _trimBodies() {
    var size = _bodies.values.fold<int>(0, (n, e) => n + utf8.encode(e).length);
    while (_bodies.length > 20 || size > 2 * 1024 * 1024) {
      size -= utf8.encode(_bodies.remove(_bodies.keys.first)!).length;
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final now = _clock();
    final future = _index?.entries
            .where((e) =>
                !e.withdrawn &&
                e.expiresAt != null &&
                e.expiresAt!.isAfter(now))
            .map((e) => e.expiresAt!)
            .toList() ??
        <DateTime>[];
    if (future.isEmpty) return;
    future.sort();
    _expiryTimer = Timer(future.first.difference(now), () {
      if (_disposed) return;
      final active = items.map((e) => e.id).toSet();
      _bodies.removeWhere((key, _) => !active.contains(key.split(':').first));
      _changed();
      unawaited(_save().catchError((Object _) {}));
      _scheduleExpiry();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    _dio.close();
    super.dispose();
  }
}
