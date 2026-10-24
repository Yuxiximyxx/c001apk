import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/announcements/announcement.dart';
import '../logic/announcements/announcement_service.dart';
import '../utils/markdown_content.dart';
import 'announcement_avatar.dart';
import 'markdown_body.dart';

String announcementDate(DateTime date) {
  final local = date.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

Future<void> showAnnouncement(
        BuildContext context, AnnouncementService service, Announcement item,
        {bool automatic = false, String? loadedBody}) =>
    showDialog<void>(
        context: context,
        builder: (_) => AnnouncementDialog(
            service: service,
            item: item,
            automatic: automatic,
            loadedBody: loadedBody));

Widget _keyboard(
        BuildContext context, ScrollController controller, Widget child) =>
    CallbackShortcuts(bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).maybePop(),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        if (controller.hasClients) {
          controller.animateTo(
              (controller.offset + 100)
                  .clamp(0, controller.position.maxScrollExtent),
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut);
        }
      },
      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        if (controller.hasClients) {
          controller.animateTo(
              (controller.offset - 100)
                  .clamp(0, controller.position.maxScrollExtent),
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut);
        }
      },
    }, child: Focus(autofocus: true, child: child));

class AnnouncementDialog extends StatefulWidget {
  const AnnouncementDialog(
      {super.key,
      required this.service,
      required this.item,
      this.automatic = false,
      this.loadedBody});
  final AnnouncementService service;
  final Announcement item;
  final bool automatic;
  final String? loadedBody;
  @override
  State<AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<AnnouncementDialog>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  late Future<String> _load;
  String? _body;
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load = widget.loadedBody == null
        ? widget.service.loadBody(widget.item)
        : Future.value(widget.loadedBody);
  }

  void _recordVisible() {
    if (_recorded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!mounted ||
          _recorded ||
          ModalRoute.of(context)?.isCurrent != true ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          !widget.service.isCurrent(widget.item)) {
        return;
      }
      _recorded = true;
      final write = widget.automatic
          ? widget.service.markPrompted(widget.item)
          : widget.service.markRead(widget.item);
      unawaited(write.catchError((Object _) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(const SnackBar(content: Text('公告阅读状态未能保存，请稍后重试')));
        }
      }));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted && state == AppLifecycleState.resumed) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _keyboard(
      context,
      _scroll,
      AnimatedBuilder(
          animation: widget.service,
          builder: (context, _) => FutureBuilder<String>(
              future: _load,
              builder: (context, snapshot) {
                // Depend on route visibility so a covered popup records its receipt
                // only when it becomes visible again.
                final visible = ModalRoute.of(context)?.isCurrent == true;
                final current = widget.service.isCurrent(widget.item);
                final ready = current && snapshot.hasData;
                if (ready) {
                  _body = snapshot.data;
                  if (visible) _recordVisible();
                }
                final theme = Theme.of(context);
                final colors = theme.colorScheme;
                return Dialog(
                    insetPadding: const EdgeInsets.all(24),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: 520,
                            maxHeight: MediaQuery.sizeOf(context).height * .82),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                              child: Scrollbar(
                                  controller: _scroll,
                                  child: SingleChildScrollView(
                                      controller: _scroll,
                                      padding: const EdgeInsets.fromLTRB(
                                          24, 20, 24, 8),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Row(children: [
                                              const AnnouncementAvatar(
                                                  size: 36),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                  child: Text('c001apk 小助手',
                                                      style: theme
                                                          .textTheme.labelLarge
                                                          ?.copyWith(
                                                              color: colors
                                                                  .onSurfaceVariant))),
                                              IconButton(
                                                  tooltip: '展开阅读',
                                                  visualDensity: VisualDensity
                                                      .compact,
                                                  onPressed: !ready
                                                      ? null
                                                      : () => Navigator
                                                              .of(context)
                                                          .push(MaterialPageRoute<
                                                                  void>(
                                                              fullscreenDialog:
                                                                  true,
                                                              builder: (_) => AnnouncementReadingPage(
                                                                  service: widget
                                                                      .service,
                                                                  item: widget
                                                                      .item,
                                                                  body:
                                                                      _body!))),
                                                  icon: const Icon(
                                                      Icons.open_in_full,
                                                      size: 20)),
                                            ]),
                                            const SizedBox(height: 16),
                                            Text(widget.item.title,
                                                style: theme
                                                    .textTheme.titleLarge
                                                    ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.3)),
                                            const SizedBox(height: 10),
                                            Wrap(
                                                spacing: 10,
                                                runSpacing: 6,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  if (widget.item.important)
                                                    Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 8,
                                                                vertical: 3),
                                                        decoration: BoxDecoration(
                                                            color: colors
                                                                .secondaryContainer,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        6)),
                                                        child: Text('重要公告',
                                                            style: theme
                                                                .textTheme
                                                                .labelSmall
                                                                ?.copyWith(
                                                                    color: colors
                                                                        .onSecondaryContainer))),
                                                  Text(
                                                      '发布于 ${announcementDate(widget.item.publishedAt)}',
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                              color: colors
                                                                  .onSurfaceVariant)),
                                                ]),
                                            const SizedBox(height: 16),
                                            Divider(
                                                height: 1,
                                                color: colors.outlineVariant),
                                            const SizedBox(height: 16),
                                            if (!current)
                                              const Text('公告已更新或撤回，请刷新列表')
                                            else if (snapshot.hasError)
                                              Column(children: [
                                                Text(snapshot.error
                                                        is AnnouncementFailure
                                                    ? (snapshot.error
                                                            as AnnouncementFailure)
                                                        .message
                                                    : '公告正文加载失败，请稍后重试'),
                                                TextButton(
                                                    onPressed: () =>
                                                        setState(() {
                                                          _load = widget.service
                                                              .loadBody(
                                                                  widget.item);
                                                        }),
                                                    child: const Text('重试'))
                                              ])
                                            else if (!ready)
                                              const SizedBox(
                                                  height: 120,
                                                  child: Center(
                                                      child:
                                                          CircularProgressIndicator()))
                                            else
                                              MarkdownBody(
                                                  content:
                                                      MarkdownContent.parse(
                                                          _body!,
                                                          explicit: true,
                                                          coolapk: false,
                                                          showEmoji: false),
                                                  fontSize: 14,
                                                  baseUrl: widget
                                                      .service.baseUri
                                                      .resolve(
                                                          widget.item.path)),
                                          ])))),
                          Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 12, 24, 20),
                              child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('知道了')))),
                        ])));
              })));
}

class AnnouncementReadingPage extends StatefulWidget {
  const AnnouncementReadingPage(
      {super.key,
      required this.service,
      required this.item,
      required this.body});
  final AnnouncementService service;
  final Announcement item;
  final String body;
  @override
  State<AnnouncementReadingPage> createState() =>
      _AnnouncementReadingPageState();
}

class _AnnouncementReadingPageState extends State<AnnouncementReadingPage>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  bool _recorded = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _recordVisible() {
    if (_recorded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (mounted &&
          !_recorded &&
          ModalRoute.of(context)?.isCurrent == true &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
          widget.service.isCurrent(widget.item)) {
        _recorded = true;
        unawaited(
            widget.service.markRead(widget.item).catchError((Object _) {}));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted && state == AppLifecycleState.resumed) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ModalRoute.of(context)?.isCurrent == true) _recordVisible();
    final content = Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('发布于 ${announcementDate(widget.item.publishedAt)}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 16),
                      MarkdownBody(
                          content: MarkdownContent.parse(widget.body,
                              explicit: true, coolapk: false, showEmoji: false),
                          baseUrl:
                              widget.service.baseUri.resolve(widget.item.path)),
                    ]))));
    return _keyboard(
        context,
        _scroll,
        Scaffold(
            appBar: AppBar(title: Text(widget.item.title)),
            body: SafeArea(
                top: false,
                child: AnimatedBuilder(
                    animation: widget.service,
                    builder: (context, _) =>
                        !widget.service.isCurrent(widget.item)
                            ? const Center(child: Text('公告已更新或撤回，请刷新列表'))
                            : Scrollbar(
                                controller: _scroll,
                                child: SingleChildScrollView(
                                    controller: _scroll, child: content))))));
  }
}
