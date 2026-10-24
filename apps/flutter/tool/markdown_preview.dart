// Local, offline acceptance harness. This is not the application entry point.
import 'dart:io';

import 'package:c001apk_flutter/components/markdown_body.dart';
import 'package:c001apk_flutter/components/update_dialog.dart';
import 'package:c001apk_flutter/logic/app_update/app_release.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:window_manager/window_manager.dart';

const sample = '''# Markdown 本地验收

## 基础格式
**加粗**、*斜体*、~~删除线~~、`行内代码`，以及 [哈哈哈] 表情。

> 引用中的文字正常显示。

- 第一项
  - 嵌套项目
- 第二项
- [x] 只读已完成
- [ ] 只读待完成

## 表格
| 平台 | 文件 |
| --- | --- |
| Android | c001apk-android-arm64-v8a.apk |
| Windows | c001apk-windows-x86_64.zip |

## 代码
```text
[哈哈哈]  <tag>  **这里不格式化**
long_line_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz
```

---

## 原生链接
<a class="feed-link-tag" href="/t/Flutter">#Flutter#</a>
<a class="feed-link-uname" href="/u/1">@示例用户</a>

## 不支持的 HTML
<iframe src="https://example.com"></iframe>
''';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never opens the application's account/settings directory.
  final temp = await Directory.systemTemp.createTemp('c001apk-md-preview-');
  Hive.init(temp.path);
  GStorage.settings = await Hive.openBox('settings');
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
        const WindowOptions(
            size: Size(1280, 720), title: 'c001apk M3E Markdown 本地验收'),
        () async => windowManager.show());
  }
  runApp(const PreviewApp());
}

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key});
  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  bool dark = false;
  bool raw = false;
  bool preview = false;
  bool enlarged = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.blue),
        darkTheme: ThemeData(
            colorSchemeSeed: Colors.blue, brightness: Brightness.dark),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Builder(
            builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('Markdown 本地验收')),
                  body: Column(children: [
                    Wrap(children: [
                      TextButton(
                          onPressed: () => setState(() => raw = !raw),
                          child: Text(raw ? '格式化显示' : '查看原文')),
                      TextButton(
                          onPressed: () => setState(() => dark = !dark),
                          child: const Text('切换明暗')),
                      TextButton(
                          onPressed: () => setState(() => enlarged = !enlarged),
                          child: const Text('切换大字号')),
                      TextButton(
                          onPressed: () => setState(() => preview = !preview),
                          child: const Text('切换预览')),
                      TextButton(
                          onPressed: () => showDialog<UpdateAction>(
                              context: context,
                              builder: (_) => AppUpdateDialog(
                                  release: AppRelease.fromJson({
                                    'draft': false,
                                    'prerelease': false,
                                    'tag_name': '1.3.3-release',
                                    'html_url':
                                        'https://github.com/TG-Twilight/c001apk/releases/tag/1.3.3-release',
                                    'assets': <dynamic>[],
                                    'body': sample,
                                  }),
                                  currentVersion: '1.3.2',
                                  onOpenRelease: () {})),
                          child: const Text('更新日志示例')),
                    ]),
                    Expanded(
                        child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                              textScaler:
                                  TextScaler.linear(enlarged ? 1.4 : 1)),
                          child: FeedText(sample,
                              forcePlain: raw, preview: preview)),
                    )),
                  ]),
                )),
      );
}
