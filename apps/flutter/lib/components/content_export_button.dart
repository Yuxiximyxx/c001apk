import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../logic/model/feed/datum.dart';
import '../logic/model/feed_article/feed_article.dart';
import '../utils/content_export_service.dart';
import '../utils/content_export.dart';
import '../utils/global_data.dart';

class ContentExportButton extends StatefulWidget {
  const ContentExportButton(
      {super.key,
      required this.feed,
      this.articles = const [],
      this.serviceFactory});
  final Datum feed;
  final List<FeedArticle> articles;
  final ContentExportService Function()? serviceFactory;

  @override
  State<ContentExportButton> createState() => _ContentExportButtonState();
}

class _ContentExportButtonState extends State<ContentExportButton> {
  bool _busy = false;
  bool _preparing = false;
  ContentExportService? _service;

  @override
  void dispose() {
    _service?.cancel();
    super.dispose();
  }

  bool _active(int generation) =>
      mounted && GlobalData().sessionGeneration == generation;

  Future<void> _start() async {
    final generation = GlobalData().sessionGeneration;
    setState(() => _busy = true);
    try {
      final format = await showDialog<ExportFormat>(
          context: context,
          builder: (context) =>
              SimpleDialog(title: const Text('保存内容'), children: [
                ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Markdown (.md)'),
                    subtitle: const Text('可编辑，图片保留在线链接'),
                    onTap: () => Navigator.pop(context, ExportFormat.markdown)),
                ListTile(
                    leading: const Icon(Icons.html_outlined),
                    title: const Text('离线 HTML (.html)'),
                    subtitle: const Text('图文排版，图片内嵌至单个文件'),
                    onTap: () => Navigator.pop(context, ExportFormat.html)),
                const Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 12),
                    child: Text('正文与最多三条评论；置顶优先，其余按热门排序。')),
              ]));
      if (format == null || !_active(generation)) return;
      final service = widget.serviceFactory?.call() ?? ContentExportService();
      _service = service;
      setState(() => _preparing = true);
      // Snapshot the displayed content before awaiting network work.
      final feed = snapshotExportFeed(widget.feed);
      final prepared = await service.prepare(feed,
          articles: List.of(widget.articles), format: format);
      if (!mounted || !_active(generation)) return;
      setState(() => _preparing = false);
      if (prepared.warnings.isNotEmpty) {
        final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('部分内容未能保存'),
                    content: Text(
                        '${prepared.warnings.join('\n\n')}\n\n继续保存已取得的内容？'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('继续保存'))
                    ]));
        if (proceed != true || !_active(generation)) return;
      }
      final saved = await service.save(prepared);
      if (saved && _active(generation)) SmartDialog.showToast('内容已保存');
    } on ExportCancelled {
      // Leaving the detail page cancels the operation normally.
    } catch (_) {
      if (_active(generation)) {
        SmartDialog.showToast('保存失败，请检查目录权限和剩余空间后重试');
      }
    } finally {
      _service?.cancel();
      _service = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _preparing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: _busy ? '正在准备保存内容' : '保存内容',
      onPressed: _busy ? null : _start,
      icon: _preparing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.save_alt_outlined));
}
