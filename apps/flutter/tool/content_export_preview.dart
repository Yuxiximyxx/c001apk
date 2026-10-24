// Offline desktop acceptance harness, using the product exporter and save UI.
import 'dart:io';

import 'package:c001apk_flutter/components/content_export_button.dart';
import 'package:c001apk_flutter/components/markdown_body.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/logic/state/loading_state.dart';
import 'package:c001apk_flutter/utils/content_export_service.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hive/hive.dart';
import 'package:window_manager/window_manager.dart';

import 'markdown_preview.dart' show sample;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final temp = await Directory.systemTemp.createTemp('c001apk-export-preview-');
  Hive.init(temp.path);
  GStorage.settings = await Hive.openBox('settings');
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
      const WindowOptions(size: Size(1280, 720), title: 'c001apk M3E 保存验收'),
      () => windowManager.show());
  runApp(const ExportPreview());
}

class ExportPreview extends StatelessWidget {
  const ExportPreview({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      builder: FlutterSmartDialog.init(),
      home: Scaffold(
        appBar: AppBar(title: const Text('保存内容本地验收'), actions: [
          ContentExportButton(
            feed: Datum(
                id: 123,
                messageTitle: '离线保存验收',
                username: '示例作者',
                dateline: 1700000000,
                message: sample,
                picArr: [
                  'https://example.com/export-local-test.png'
                ],
                topReplyRows: [
                  Datum(
                      id: 1, username: '置顶作者', message: '低赞置顶必须第一', likenum: 1)
                ]),
            serviceFactory: () => ContentExportService(
                blockedUids: () => {},
                loadPopular: (_) async => Success([
                      Datum(
                          id: 9,
                          username: '热门作者',
                          message: '热门第一应为第二条',
                          likenum: 900),
                      Datum(id: 1, message: '重复置顶不应占位'),
                      Datum(
                          id: 4,
                          username: '热门作者二',
                          message: '热门第二应为第三条',
                          likenum: 800),
                      Datum(id: 99, message: '第四条不应保存', likenum: 9999),
                    ]),
                loadImage: (_) async =>
                    (await rootBundle.load('assets/icon/icon.png'))
                        .buffer
                        .asUint8List()),
          ),
          PopupMenuButton<String>(
              itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'placeholder', child: Text('菜单位置参考')),
                  ]),
        ]),
        body: const SingleChildScrollView(
            padding: EdgeInsets.all(24), child: FeedText(sample)),
      ));
}
