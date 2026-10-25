// 预测式返回诊断面板（临时代码，随 lib/diagnostics/ 一并删除）。
//
// 使用路径：我的 → 设置 → 预测式返回诊断。
//   ① 点「打开 A 页」→ 从左边缘慢滑返回 → 回到本页看日志并截图；
//   ② 点「打开 B 页」→ 同样慢滑返回 → 回到本页看日志并截图。
// A 是 GetX 路由（与应用内页面同机制），B 是绕开 GetX 的普通
// MaterialPageRoute，两页对照即可把断点定位到路由层或框架/系统层。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'predictive_back_diagnostics.dart';

class PredictiveBackDiagnosticsPage extends StatefulWidget {
  const PredictiveBackDiagnosticsPage({super.key});

  @override
  State<PredictiveBackDiagnosticsPage> createState() =>
      _PredictiveBackDiagnosticsPageState();
}

class _PredictiveBackDiagnosticsPageState
    extends State<PredictiveBackDiagnosticsPage> {
  late final Future<List<String>> _environment =
      PredictiveBackDiagnostics.collectEnvironment();
  int _markCount = 0;

  void _openGetXTestPage() {
    PredictiveBackDiagnostics.navigatorObserver
        .armNextRouteLabel('A-GetX测试页');
    Get.to<void>(() => const DiagTestPage(
          kind: 'A',
          routeKind: 'GetX 路由（与应用内页面同机制）',
          color: Colors.blue,
        ));
  }

  void _openPlainTestPage() {
    PredictiveBackDiagnostics.navigatorObserver
        .armNextRouteLabel('B-普通路由测试页');
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'diag/plain-test'),
      builder: (_) => const DiagTestPage(
        kind: 'B',
        routeKind: '普通 MaterialPageRoute（绕开 GetX）',
        color: Colors.green,
      ),
    ));
  }

  void _mark() {
    _markCount++;
    BackDiagLog.instance.log('标记', '—— 用户标记 #$_markCount ——');
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(
        ClipboardData(text: BackDiagLog.instance.fullText));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = BackDiagLog.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('预测式返回诊断')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '操作步骤（每步做完回到本页，截日志区的图）：\n'
                '1. 点下方「打开 A 页」，在 A 页从屏幕左边缘缓慢向右滑，'
                '观察页面是否跟随手指缩小；滑到一半再滑回去应能取消。\n'
                '2. 回到本页后，再点「打开 B 页」，做同样的慢滑。\n'
                '3. 也可以直接回应用里打开任意帖子页慢滑，再回本页看日志。\n'
                '4. 把日志区截图发回（或用「复制日志」整段粘贴）。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _openGetXTestPage,
                    child: const Text('打开 A 页（GetX 路由）'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _openPlainTestPage,
                    child: const Text('打开 B 页（普通 MaterialPageRoute）'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _mark,
                          child: const Text('在日志中打标记'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: log.clear,
                          child: const Text('清空日志'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _copyLog,
                          child: const Text('复制日志'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '日志文件（备用）: ${log.filePath ?? '初始化中或不可用，以内存日志为准'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('环境信息',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  FutureBuilder<List<String>>(
                    future: _environment,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Text('读取中…');
                      }
                      return SelectableText(
                        snapshot.data!.join('\n'),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('实时日志（最新在最上面）',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<int>(
                    valueListenable: log.revision,
                    builder: (context, _, __) {
                      final lines = log.lines.reversed.toList();
                      if (lines.isEmpty) return const Text('（暂无日志）');
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in lines)
                            SelectableText(
                              line,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 10),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A/B 对照测试页：除路由类型外，两页内容与结构完全一致。
class DiagTestPage extends StatelessWidget {
  const DiagTestPage({
    super.key,
    required this.kind,
    required this.routeKind,
    required this.color,
  });

  final String kind;
  final String routeKind;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('测试页 $kind')),
      body: Container(
        color: color.shade50,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swipe, size: 64, color: color),
            const SizedBox(height: 16),
            Text('测试页 $kind',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(routeKind, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const Text(
              '请从屏幕左边缘缓慢向右滑动：\n'
              '观察本页是否跟随手指缩小、露出下层页面；\n'
              '滑到一半滑回去，应当能取消返回。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('用按钮返回（不滑动）'),
            ),
          ],
        ),
      ),
    );
  }
}
