// ============================================================================
// 预测式返回真机诊断（临时代码，问题定位后整体删除）
//
// 删除方法：删掉 lib/diagnostics/ 整个目录，并去掉两处接线——
//   1. lib/main.dart 中 PredictiveBackDiagnostics.install() 调用、
//      GetMaterialApp 的 navigatorObservers 参数与本包 import；
//   2. lib/pages/settings/settings_page.dart 中「预测式返回诊断」条目与 import。
//
// 观测原理（全部使用框架公开的观察点，不拦截、不转发、不认领）：
//   * 通道层：注册一个 WidgetsBindingObserver，其 handleStartBackGesture
//     恒返回 false。框架 WidgetsBinding 对每个 start 事件都会遍历全部
//     observer 并把解码后的 PredictiveBackEvent（touchOffset / progress /
//     swipeEdge / isButtonEvent）逐个递给它们；返回 false 只是不加入
//     本次手势的认领名单，不改变 SDK detector 的认领与动画驱动。
//     progress/cancel/commit 按框架设计只投递给认领者，观察者看不到，
//     因此用下面的路由层代理指标补齐。
//   * 路由层：NavigatorObserver 记录路由进出、didStartUserGesture /
//     didStopUserGesture（这两者由顶层路由的 handleStartBackGesture 触发，
//     出现即证明 detector 已认领手势）、顶层路由 animation 的状态与
//     手势期间的取值变化（出现即证明进度事件在驱动动画）。
//   * 门控层：框架的 canHandlePop 由 _NavigatorState 内部计算后经
//     NavigationNotification 交给 WidgetsApp，后者在通知上 return true
//     截断冒泡，应用层无法直接旁听。此处按框架源码同一公式复算
//     （canPop() || 顶层路由 popDisposition == doNotPop），属于派生记录；
//     WidgetsApp 收到该值后同步调用 SystemNavigator.setFrameworkHandlesBack
//     是框架的确定行为，故日志中记为「将调用」。
// 所有 observer 回调都包了 try/catch：诊断代码绝不能把应用带崩。
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/device_profile.dart';

/// 诊断日志存储：内存环形缓冲（供面板实时显示）+ 文档目录文本文件（备用）。
class BackDiagLog {
  BackDiagLog._();

  static final BackDiagLog instance = BackDiagLog._();

  static const int maxLines = 600;

  final List<String> _lines = <String>[];

  /// 面板监听此值刷新日志区。
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Stopwatch _clock = Stopwatch();
  File? _file;
  Future<void> _writeChain = Future<void>.value();

  /// 日志文件的完整路径（文件初始化完成后才有值）。
  String? get filePath => _file?.path;

  List<String> get lines => List<String>.unmodifiable(_lines);

  String get fullText => _lines.join('\n');

  void start() {
    if (!_clock.isRunning) _clock.start();
    unawaited(_initFile());
  }

  Future<void> _initFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/predictive_back_diag.log');
      await _file!.writeAsString(
        '\n===== 预测式返回诊断会话 ${DateTime.now().toIso8601String()} =====\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // 文件落盘失败不影响内存日志与面板显示。
      _file = null;
    }
  }

  void log(String tag, String message) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    final stamp =
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${three(now.millisecond)}'
        '(+${_clock.elapsedMilliseconds}ms)';
    final line = '[$stamp][$tag] $message';
    _lines.add(line);
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    revision.value++;
    final file = _file;
    if (file != null) {
      _writeChain = _writeChain.then((_) async {
        try {
          await file.writeAsString('$line\n', mode: FileMode.append);
        } catch (_) {
          // 忽略落盘错误，内存日志为准。
        }
      });
    }
  }

  void clear() {
    _lines.clear();
    revision.value++;
    log('系统', '日志已清空');
  }
}

String _routeLabel(Route<dynamic> route) {
  final name = route.settings.name;
  final short = identityHashCode(route).toRadixString(16);
  return '${route.runtimeType}${name != null ? ' name=$name' : ''}'
      '#${short.substring(0, short.length < 5 ? short.length : 5)}';
}

/// 通道层观察者：只记录 start 事件与解码后的载荷，恒不认领手势。
class BackDiagBindingObserver with WidgetsBindingObserver {
  BackDiagBindingObserver(this._navObserver);

  final BackDiagNavigatorObserver _navObserver;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    try {
      BackDiagLog.instance.log(
        '通道',
        'startBackGesture 到达 Dart: touchOffset=${backEvent.touchOffset} '
        'progress=${backEvent.progress} swipeEdge=${backEvent.swipeEdge} '
        'isButtonEvent=${backEvent.isButtonEvent}'
        '${backEvent.isButtonEvent ? ' ← detector 会据此拒绝认领！' : ''}',
      );
      BackDiagLog.instance.log('快照', _navObserver.gestureStartSnapshot());
    } catch (_) {
      // 诊断自身出错时保持沉默，绝不干扰手势分发。
    }
    return false;
  }

  // 以下三个回调按框架分发规则只投递给「认领了手势」的 observer；本观察者
  // 恒返回 false，正常情况下永远不会被调用。若日志里出现它们，说明框架
  // 分发语义与预期不符，本身就是一条诊断结论。
  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    BackDiagLog.instance.log(
        '通道', '异常：未认领却收到 progress=${backEvent.progress}');
  }

  @override
  void handleCommitBackGesture() {
    BackDiagLog.instance.log('通道', '异常：未认领却收到 commit');
  }

  @override
  void handleCancelBackGesture() {
    BackDiagLog.instance.log('通道', '异常：未认领却收到 cancel');
  }

  @override
  Future<bool> didPopRoute() {
    try {
      BackDiagLog.instance.log(
          '框架', 'didPopRoute 被调用（离散返回路径：无认领者时 commit 的兜底）');
    } catch (_) {}
    return Future<bool>.value(false);
  }
}

/// 路由层观察者：路由栈、手势认领信号、顶层路由动画、门控派生值。
class BackDiagNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];
  final Map<Route<dynamic>, String> _labels = <Route<dynamic>, String>{};
  final Map<Route<dynamic>, void Function()> _animationListeners =
      <Route<dynamic>, void Function()>{};
  String? _armedLabel;
  bool? _lastCanHandlePop;
  bool _gestureActive = false;

  /// 面板在 push 测试页之前调用，给下一个进栈路由打上 A/B 标签。
  void armNextRouteLabel(String label) => _armedLabel = label;

  String labelOf(Route<dynamic> route) =>
      _labels[route] ?? _routeLabel(route);

  Route<dynamic>? get topRoute => _stack.isEmpty ? null : _stack.last;

  String gestureStartSnapshot() {
    final nav = navigator;
    final top = topRoute;
    if (nav == null || top == null) return '手势开始：导航器未就绪';
    final buffer = StringBuffer()
      ..write('栈深=${_stack.length} 顶层=${labelOf(top)} '
          'navigator.canPop=${nav.canPop()} ');
    if (top is PageRoute) {
      buffer.write('popGestureEnabled=${top.popGestureEnabled} '
          'popDisposition=${top.popDisposition} '
          'animation=${top.animation?.value.toStringAsFixed(3)}');
    } else {
      buffer.write('popDisposition=${top.popDisposition}（非 PageRoute）');
    }
    buffer.write(' 派生canHandlePop=${_deriveCanHandlePop(nav, top)}');
    return buffer.toString();
  }

  /// 与框架 _NavigatorState._getNavigatorCanHandlePop 同一公式。
  bool _deriveCanHandlePop(NavigatorState nav, Route<dynamic> top) =>
      nav.canPop() || top.popDisposition == RoutePopDisposition.doNotPop;

  void _log(String tag, String message) =>
      BackDiagLog.instance.log(tag, message);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    try {
      _stack.add(route);
      final armed = _armedLabel;
      if (armed != null) {
        _labels[route] = '$armed ${_routeLabel(route)}';
        _armedLabel = null;
      }
      _log('路由',
          'didPush ${labelOf(route)}（前一层: ${previousRoute == null ? '无' : labelOf(previousRoute)}）');
      _watchAnimation(route);
      _scheduleCanHandlePopCheck('didPush ${labelOf(route)}');
    } catch (_) {}
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    try {
      _stack.remove(route);
      _unwatchAnimation(route);
      _log('路由',
          'didPop ${labelOf(route)}（回到: ${previousRoute == null ? '无' : labelOf(previousRoute)}）');
      _labels.remove(route);
      _scheduleCanHandlePopCheck('didPop ${labelOf(route)}');
    } catch (_) {}
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    try {
      _stack.remove(route);
      _unwatchAnimation(route);
      _log('路由', 'didRemove ${labelOf(route)}');
      _labels.remove(route);
      _scheduleCanHandlePopCheck('didRemove ${labelOf(route)}');
    } catch (_) {}
  }

  @override
  void didReplace(
      {Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    try {
      if (oldRoute != null) {
        final index = _stack.indexOf(oldRoute);
        _unwatchAnimation(oldRoute);
        _labels.remove(oldRoute);
        if (newRoute != null && index >= 0) {
          _stack[index] = newRoute;
        } else {
          _stack.remove(oldRoute);
          if (newRoute != null) _stack.add(newRoute);
        }
      } else if (newRoute != null) {
        _stack.add(newRoute);
      }
      if (newRoute != null) _watchAnimation(newRoute);
      _log('路由',
          'didReplace ${oldRoute == null ? '无' : labelOf(oldRoute)} -> ${newRoute == null ? '无' : labelOf(newRoute)}');
      _scheduleCanHandlePopCheck('didReplace');
    } catch (_) {}
  }

  @override
  void didStartUserGesture(
      Route<dynamic> route, Route<dynamic>? previousRoute) {
    try {
      _gestureActive = true;
      if (!_animationListeners.containsKey(route)) _watchAnimation(route);
      _log('手势',
          'didStartUserGesture ${labelOf(route)} ← detector 已认领手势并执行 route.handleStartBackGesture');
    } catch (_) {}
  }

  @override
  void didStopUserGesture() {
    try {
      _gestureActive = false;
      _log('手势', 'didStopUserGesture（手势结束：已 commit 或 cancel 并收尾）');
    } catch (_) {}
  }

  void _watchAnimation(Route<dynamic> route) {
    if (route is! TransitionRoute) return;
    final Animation<double>? animation = route.animation;
    if (animation == null) return;
    AnimationStatus? lastStatus = animation.status;
    double lastLoggedValue = animation.value;
    final PageRoute<dynamic>? pageRoute =
        route is PageRoute<dynamic> ? route : null;
    void listener() {
      try {
        // 数值采样只在手势活跃期记录，避免普通转场动画刷屏。
        if (_gestureActive &&
            (animation.value - lastLoggedValue).abs() >= 0.02) {
          lastLoggedValue = animation.value;
          _log('动画',
              '${labelOf(route)} value=${animation.value.toStringAsFixed(3)}（手势驱动中）');
        }
      } catch (_) {}
    }

    void statusListener(AnimationStatus status) {
      try {
        if (status != lastStatus) {
          _log('动画',
              '${labelOf(route)} status $lastStatus -> $status value=${animation.value.toStringAsFixed(3)} popGestureInProgress=${pageRoute?.popGestureInProgress}');
          lastStatus = status;
          lastLoggedValue = animation.value;
        }
      } catch (_) {}
    }

    animation.addListener(listener);
    animation.addStatusListener(statusListener);
    _animationListeners[route] = () {
      animation.removeListener(listener);
      animation.removeStatusListener(statusListener);
    };
  }

  void _unwatchAnimation(Route<dynamic> route) {
    _animationListeners.remove(route)?.call();
  }

  void _scheduleCanHandlePopCheck(String why) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final nav = navigator;
        final top = topRoute;
        if (nav == null || top == null) return;
        final value = _deriveCanHandlePop(nav, top);
        if (value != _lastCanHandlePop) {
          _log('门控',
              'canHandlePop $_lastCanHandlePop -> $value（$why，顶层=${labelOf(top)}）⇒ 框架 WidgetsApp 将调用 SystemNavigator.setFrameworkHandlesBack($value)${value ? '（启用 embedding 回调）' : '（禁用 embedding 回调，手势由系统接管）'}');
          _lastCanHandlePop = value;
        }
      } catch (_) {}
    });
  }
}

/// 诊断总装：安装观察者、收集环境信息。
class PredictiveBackDiagnostics {
  PredictiveBackDiagnostics._();

  static final BackDiagNavigatorObserver navigatorObserver =
      BackDiagNavigatorObserver();

  static bool _installed = false;

  /// 在 main() 的 ensureInitialized 之后、runApp 之前调用一次。
  static void install() {
    if (_installed) return;
    _installed = true;
    BackDiagLog.instance.start();
    WidgetsBinding.instance
        .addObserver(BackDiagBindingObserver(navigatorObserver));
    BackDiagLog.instance
        .log('系统', '诊断已安装：绑定观察者（恒不认领）+ 导航观察者已就位');
  }

  /// Q4 环境信息：设备、系统、应用与 Manifest 声明。
  static Future<List<String>> collectEnvironment() async {
    final lines = <String>[];
    try {
      final package = await PackageInfo.fromPlatform();
      lines.add(
          '应用: ${package.appName} ${package.version}+${package.buildNumber} 包名=${package.packageName}');
    } catch (e) {
      lines.add('应用: PackageInfo 读取失败 $e');
    }
    if (Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        lines.add('厂商/品牌: ${info.manufacturer} / ${info.brand}');
        lines.add(
            '机型: ${info.model}（device=${info.device}, product=${info.product}）');
        lines.add(
            'Android: ${info.version.release} API=${info.version.sdkInt} codename=${info.version.codename}');
        lines.add('Build.DISPLAY: ${info.display}');
        lines.add('Build.FINGERPRINT: ${info.fingerprint}');
        lines.add(
            'incremental: ${info.version.incremental} 安全补丁: ${info.version.securityPatch}');
        lines.add('物理设备: ${info.isPhysicalDevice}');
      } catch (e) {
        lines.add('设备信息读取失败: $e');
      }
      try {
        final profile = await DeviceProfile.current();
        lines.add(
            '原生通道交叉核对: manufacturer=${profile.manufacturer} model=${profile.model} buildNumber=${profile.buildNumber} sdkInt=${profile.sdkInt} android=${profile.androidVersion}');
      } catch (e) {
        lines.add('原生通道交叉核对失败: $e');
      }
    }
    lines.add('Dart: ${Platform.version}');
    lines.add(
        'targetSdk: android/app/build.gradle 中 targetSdk = flutter.targetSdkVersion'
        '（本工具链为 36；Dart 运行时无公开 API 读取，未做原生读取，此为构建配置值）');
    lines.add(
        'Manifest: android:enableOnBackInvokedCallback="true" 已声明'
        '（android/app/src/main/AndroidManifest.xml 源码核查；运行时是否生效，'
        '以滑动时 [通道] 是否出现 start 事件为准）');
    lines.add(
        '判读提示: 若 [通道] 完全无 start，先看同屏 [门控] 是否为 true；'
        '门控为 true 仍无 start 才是系统/embedding 层未投递。');
    return lines;
  }
}
