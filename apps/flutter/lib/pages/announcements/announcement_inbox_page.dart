import 'dart:async';

import 'package:flutter/material.dart';

import '../../components/announcement_dialog.dart';
import '../../components/expressive_refresh_indicator.dart';
import '../../logic/announcements/announcement_service.dart';

class AnnouncementInboxPage extends StatefulWidget {
  const AnnouncementInboxPage({super.key, required this.service});
  final AnnouncementService service;
  @override
  State<AnnouncementInboxPage> createState() => _AnnouncementInboxPageState();
}

class _AnnouncementInboxPageState extends State<AnnouncementInboxPage> {
  final _scroll = ScrollController();
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_refresh(SyncReason.inbox));
  }

  Future<void> _refresh(SyncReason reason) async {
    final error = await widget.service.sync(reason);
    if (mounted) setState(() => _error = error);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('c001apk 小助手'), actions: [
        IconButton(
            tooltip: '刷新公告',
            onPressed: () => _refresh(SyncReason.manual),
            icon: const Icon(Icons.refresh)),
        PopupMenuButton<String>(
            tooltip: '公告设置',
            onSelected: (_) async {
              await widget.service.clearBodyCache();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('公告正文缓存已清理，阅读记录已保留')));
              }
            },
            itemBuilder: (_) =>
                const [PopupMenuItem(value: 'clear', child: Text('清理公告正文缓存'))]),
      ]),
      body: SafeArea(
          top: false,
          child: AnimatedBuilder(
              animation: widget.service,
              builder: (context, _) {
                final items = widget.service.items;
                return Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 840),
                        child: Column(children: [
                          if (widget.service.isSyncing)
                            const LinearProgressIndicator(),
                          if (_error != null)
                            Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(_error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error))),
                          Expanded(
                              child: ExpressiveRefreshIndicator(
                                  onRefresh: () => _refresh(SyncReason.manual),
                                  child: ListView.builder(
                                      controller: _scroll,
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.all(12),
                                      itemCount:
                                          items.isEmpty ? 1 : items.length,
                                      itemBuilder: (context, index) {
                                        if (items.isEmpty) {
                                          return const Padding(
                                              padding: EdgeInsets.symmetric(
                                                  vertical: 80),
                                              child:
                                                  Center(child: Text('暂无公告')));
                                        }
                                        final item = items[index];
                                        return Card(
                                            clipBehavior: Clip.antiAlias,
                                            child: ListTile(
                                                contentPadding:
                                                    const EdgeInsets.all(16),
                                                title: Text(item.title),
                                                subtitle: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const SizedBox(height: 6),
                                                      Text(announcementDate(
                                                          item.publishedAt)),
                                                      if (item.summary
                                                          .isNotEmpty) ...[
                                                        const SizedBox(
                                                            height: 8),
                                                        Text(item.summary),
                                                      ],
                                                      if (item.important) ...[
                                                        const SizedBox(
                                                            height: 6),
                                                        const Text('重要公告'),
                                                      ],
                                                    ]),
                                                trailing:
                                                    widget.service.isRead(item)
                                                        ? const Icon(
                                                            Icons.chevron_right)
                                                        : const Badge(
                                                            label: Text('未读')),
                                                onTap: () => showAnnouncement(
                                                    context,
                                                    widget.service,
                                                    item)));
                                      }))),
                        ])));
              })));
}
