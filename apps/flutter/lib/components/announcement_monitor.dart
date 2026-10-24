import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../logic/announcements/announcement_service.dart';
import 'announcement_dialog.dart';
import 'update_check_tile.dart';

/// One automatic prompt per process, with version updates taking priority.
class AnnouncementMonitor extends StatefulWidget {
  const AnnouncementMonitor(
      {super.key,
      required this.service,
      required this.child,
      this.checkUpdates,
      this.clock,
      this.updatePromptShown});
  final AnnouncementService service;
  final Widget child;
  final Future<void> Function()? checkUpdates;
  final bool Function()? updatePromptShown;
  final DateTime Function()? clock;
  @override
  State<AnnouncementMonitor> createState() => _AnnouncementMonitorState();
}

class _AnnouncementMonitorState extends State<AnnouncementMonitor>
    with WidgetsBindingObserver {
  bool _foreground = true, _prompting = false, _shown = false;
  DateTime? _lastBodyAttempt;
  String? _lastBodyKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startup()));
  }

  Future<void> _startup() async {
    final index = widget.service.sync(SyncReason.coldStart);
    try {
      if (widget.checkUpdates != null) {
        await widget.checkUpdates!();
      } else {
        final context = Get.context;
        if (context != null) await AppUpdates.check(context, automatic: true);
      }
      await index;
      await _maybePrompt();
    } catch (_) {
      // Automatic checks never interrupt launch with diagnostic errors.
    }
  }

  BuildContext? _safeContext() {
    if (!mounted ||
        !_foreground ||
        _shown ||
        !widget.service.automaticEnabled ||
        (widget.updatePromptShown?.call() ?? AppUpdates.hasShownDialog) ||
        AppUpdates.isActive ||
        Get.currentRoute != '/' ||
        Get.isDialogOpen == true ||
        Get.isBottomSheetOpen == true) {
      return null;
    }
    final context = Get.context;
    if (context == null || !context.mounted || Navigator.of(context).canPop()) {
      return null;
    }
    return context;
  }

  Future<void> _maybePrompt() async {
    if (_prompting || _safeContext() == null) return;
    final item = widget.service.pendingImportant;
    if (item == null) return;
    final now = widget.clock?.call() ?? DateTime.now();
    final bodyKey = '${item.cacheKey}:${item.reminderRevision}';
    if (_lastBodyKey == bodyKey &&
        _lastBodyAttempt != null &&
        now.difference(_lastBodyAttempt!) < const Duration(minutes: 1)) {
      return;
    }
    _lastBodyKey = bodyKey;
    _lastBodyAttempt = now;
    _prompting = true;
    try {
      final body = await widget.service.loadBody(item);
      final context = _safeContext();
      final pending = widget.service.pendingImportant;
      if (context == null ||
          !context.mounted ||
          !widget.service.isCurrent(item) ||
          pending?.cacheKey != item.cacheKey ||
          pending?.reminderRevision != item.reminderRevision) {
        return;
      }
      _shown = true;
      await showAnnouncement(context, widget.service, item,
          automatic: true, loadedBody: body);
    } catch (_) {
      // Keep unread/prompt receipts unchanged on a failed or obsolete body.
    } finally {
      _prompting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_resume());
  }

  Future<void> _resume() async {
    await widget.service.sync(SyncReason.resume);
    if (mounted) await _maybePrompt();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AnnouncementAutoCheckTile extends StatelessWidget {
  const AnnouncementAutoCheckTile({super.key, required this.service});
  final AnnouncementService service;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: service,
      builder: (context, _) => SwitchListTile(
          secondary: const Icon(Icons.campaign_outlined),
          title: const Text('自动检查公告'),
          subtitle: const Text('普通公告进入小助手，重要公告首次弹窗提醒'),
          value: service.automaticEnabled,
          onChanged: (value) async {
            try {
              await service.setAutomaticEnabled(value);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('公告设置保存失败，请稍后重试')));
              }
            }
          }));
}
