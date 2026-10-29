import 'package:fluid_glass/fluid_glass.dart' show LayerBackdrop;
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/widgets.dart';

/// 主页面共享录制注册表（miuix25 滚动性能）：miuix24 之后一个主
/// 页面上同时有两三套全屏 LayerBackdrop 录制在跑——MainPage 为悬浮
/// Dock 录一遍整页 PageView、各页 LiquidTopBarScaffold 为顶栏再录
/// 一遍正文、关注页筛选胶囊又录一遍信息流。LayerBackdrop 的采样
/// 走 OffsetLayer.toImageSync 全屏捕获，滚动时每套录制都要逐帧
/// 重捕，是全局掉帧的头号结构性嫌疑。
///
/// 去重口径：每个主页面只保留一套录制（页面正文那套，由
/// LiquidTopBarScaffold 持有），经本注册表按页序号发布；Dock 与
/// 顶栏都是该录制子树**之外**的消费者，共享同一 [LayerBackdrop]
/// ——与三家统一的 Dock 标准结构一致（消费者绝不在被录子树内
/// 自采样）。MainPage 不再自录整页。
class PageBackdropRegistry extends ChangeNotifier {
  final Map<int, LayerBackdrop> _backdrops = {};
  int _activeIndex = 0;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// 注册/注销发生在页面挂载/卸载时（build 阶段内），直接
  /// notifyListeners 会把 Dock 的 AnimatedBuilder 在 build 中标脏
  /// （框架断言 setState during build）。非 idle 阶段的通知统一
  /// 推迟到本帧结束再发——Dock 晚一帧拿到录制，首帧走无录制回落，
  /// 与「页面未登记时为 null」的既定语义一致。
  void _notify() {
    if (_disposed) return;
    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 当前页的录制（Dock 的采样源）；当前页尚未注册时为 null，
  /// Dock 自动回落无录制引擎（首帧/宽屏 rail 的既有行为）。
  LayerBackdrop? get activeBackdrop => _backdrops[_activeIndex];

  int get activeIndex => _activeIndex;

  /// 已注册录制的页数（测试钉去重结构用）。
  int get registeredCount => _backdrops.length;

  void register(int index, LayerBackdrop backdrop) {
    if (_backdrops[index] == backdrop) return;
    _backdrops[index] = backdrop;
    _notify();
  }

  void unregister(int index, LayerBackdrop backdrop) {
    if (_backdrops[index] == backdrop) {
      _backdrops.remove(index);
      _notify();
    }
  }

  void setActive(int index) {
    if (_activeIndex == index) return;
    _activeIndex = index;
    _notify();
  }
}

/// 把 [PageBackdropRegistry] 提供给主页面子树（各页的
/// LiquidTopBarScaffold 据此注册自有录制）。
class PageBackdropScope extends InheritedWidget {
  const PageBackdropScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final PageBackdropRegistry registry;

  static PageBackdropRegistry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PageBackdropScope>()
      ?.registry;

  @override
  bool updateShouldNotify(PageBackdropScope oldWidget) =>
      !identical(registry, oldWidget.registry);
}
