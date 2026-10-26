import 'dart:math' as math;

import 'package:fluid_glass/fluid_glass.dart' show FluidGlass;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;

import 'app_anim.dart';
import 'glass_surface.dart';

/// 玻璃弹出菜单（miuix17）：按苹果 Liquid Glass 规范，弹出菜单属于
/// 悬浮控制层，用 Regular 变体 + medium 面积档的 [GlassSurface] 做面，
/// 替代 Material 的实色菜单面。菜单项直接复用 Flutter 的
/// [PopupMenuItem]/[CheckedPopupMenuItem]/[PopupMenuDivider]——它们的
/// handleTap 自带 onTap + Navigator.pop(value) 语义，放进本路由即可
/// 原样工作，所以调用点只需把 PopupMenuButton 换成
/// [GlassPopupMenuButton]、showMenu 换成 [showGlassMenu]。
///
/// 尺寸（miuix18 修正）：miuix17 的菜单面被撑成近全屏宽——根因是
/// 内容 Column 用了 CrossAxisAlignment.stretch，它在滚动视图里会把
/// 横轴尺寸顶到约束上限，于是菜单恒为 ConstrainedBox 的 maxWidth
/// 320dp（约占屏 87%），与条目内容无关。现改为 IntrinsicWidth 按
/// 最宽条目的固有宽度定宽（Material 官方菜单同法），并收紧常量：
/// 下限 [kGlassMenuMinWidth]、上限 [kGlassMenuMaxWidth] 且不超过
/// 屏宽 −32dp；高度贴合内容（条目 48dp 标准高 + 组内距），超高才
/// 滚动，上限为屏高 55%。所有调用点共用这一处实现，尺寸自动受益。
///
/// 定位：菜单优先开在锚点下方（Material 的 PopupMenuPosition.under
/// 语义，全应用统一），下方空间不足则翻到锚点上方；水平先对齐锚点
/// 左缘，溢出时改为对齐右缘，四周留 8dp 安全边距。
///
/// 动画（[AppAnim]）：从锚点方向 fade + scale 0.95→1（transform
/// origin 对齐锚点侧）+ ≤4dp 微位移，进入 200ms、退出 130ms；
/// 只动 opacity/transform，不动滤镜参数。
const double kGlassMenuMinWidth = 168;
const double kGlassMenuMaxWidth = 280;
const double kGlassMenuScreenInset = 32;
const double kGlassMenuMargin = 8;
const double kGlassMenuGap = 4;
const double kGlassMenuMaxHeightFactor = 0.55;
const double kGlassMenuVerticalPadding = 4;

Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double? menuMaxHeight,
}) {
  final navigator = Navigator.of(context);
  final overlayBox = navigator.context.findRenderObject() as RenderBox?;
  final overlaySize = overlayBox?.size ?? MediaQuery.sizeOf(context);
  final anchorRect = Rect.fromLTRB(
    position.left,
    position.top,
    overlaySize.width - position.right,
    overlaySize.height - position.bottom,
  );
  return navigator.push<T>(_GlassMenuRoute<T>(
    anchorRect: anchorRect,
    items: items,
    menuMaxHeight: menuMaxHeight,
    capturedThemes:
        InheritedTheme.capture(from: context, to: navigator.context),
  ));
}

class _GlassMenuRoute<T> extends PopupRoute<T> {
  _GlassMenuRoute({
    required this.anchorRect,
    required this.items,
    required this.capturedThemes,
    this.menuMaxHeight,
  });

  final Rect anchorRect;
  final List<PopupMenuEntry<T>> items;
  final CapturedThemes capturedThemes;
  final double? menuMaxHeight;

  @override
  Duration get transitionDuration => AppAnim.menuEnter;

  @override
  Duration get reverseTransitionDuration => AppAnim.menuExit;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return capturedThemes.wrap(_GlassMenuPanel<T>(
      anchorRect: anchorRect,
      items: items,
      menuMaxHeight: menuMaxHeight,
      animation: animation,
    ));
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // 进出动画由面板自己驱动（需要知道菜单落在锚点上/下方来对齐
    // transform origin 与微位移方向），路由层不再叠加。
    return child;
  }
}

class _GlassMenuPanel<T> extends StatefulWidget {
  const _GlassMenuPanel({
    required this.anchorRect,
    required this.items,
    required this.animation,
    this.menuMaxHeight,
  });

  final Rect anchorRect;
  final List<PopupMenuEntry<T>> items;
  final double? menuMaxHeight;
  final Animation<double> animation;

  @override
  State<_GlassMenuPanel<T>> createState() => _GlassMenuPanelState<T>();
}

class _GlassMenuPanelState<T> extends State<_GlassMenuPanel<T>> {
  final _menuKey = GlobalKey();
  Size? _menuSize;

  /// 滤镜就绪门（miuix19 立、miuix22 改挂 fluid）：面板首次可见前，
  /// 要求 fluid 的 shader 程序已加载完成——DrawBackdrop 的效果链是
  /// 同步构建的、不存在旧自研引擎那种「回调后整链换掉」的跳变，
  /// 但程序未加载完时 lens 先缺席、加载完才补上，冷启动首开菜单
  /// 仍可能闪一下。常态下应用启动时 Dock 已触发并完成加载，这里
  /// 同步即 true、零等待；未完成时订阅一次完成回调，量尺寸的
  /// post-frame 回调兜底放行（最多多等一帧，不把 200ms 入场拖成
  /// 可感延迟；程序加载失败时 isReady 恒 false，也靠兜底放行）。
  bool _filterReady = false;
  late final CurvedAnimation _entrance = CurvedAnimation(
    parent: widget.animation,
    curve: AppAnim.enterCurve,
    reverseCurve: AppAnim.exitCurve,
  );

  @override
  void initState() {
    super.initState();
    _filterReady = FluidGlass.isReady;
    if (!_filterReady) {
      FluidGlass.ensureInitialized().then((_) {
        if (mounted && !_filterReady) {
          setState(() => _filterReady = true);
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _menuKey.currentContext?.findRenderObject() as RenderBox?;
      if (mounted && box != null && box.hasSize) {
        setState(() {
          _menuSize = box.size;
          // 一帧兜底放行：加载极慢时也不吊住面板（此时 DrawBackdrop
          // 会在程序就绪后自动补上 lens，与 miuix19 前的最坏情况
          // 持平，常态路径不受影响）。
          _filterReady = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    const margin = kGlassMenuMargin;
    const gap = kGlassMenuGap;
    final maxHeight = widget.menuMaxHeight ??
        math.min(
          screen.height * kGlassMenuMaxHeightFactor,
          screen.height - margin * 2 - MediaQuery.paddingOf(context).top,
        );
    final maxWidth =
        math.min(kGlassMenuMaxWidth, screen.width - kGlassMenuScreenInset);
    final size = _menuSize;
    double left = -10000, top = -10000;
    var opensBelow = true;
    if (size != null) {
      left = widget.anchorRect.left;
      if (left + size.width > screen.width - margin) {
        left = widget.anchorRect.right - size.width;
      }
      left = left.clamp(
          margin, math.max(margin, screen.width - margin - size.width));
      top = widget.anchorRect.bottom + gap;
      if (top + size.height > screen.height - margin) {
        top = widget.anchorRect.top - size.height - gap;
        opensBelow = false;
      }
      top = top.clamp(
          margin, math.max(margin, screen.height - margin - size.height));
    }
    // 微位移：从锚点方向滑入 ≤4dp（按菜单高度换算成 Offset 分数）。
    final shiftFraction =
        size == null || size.height == 0 ? 0.0 : 4.0 / size.height;
    final surface = GlassSurface(
      key: _menuKey,
      borderRadius: BorderRadius.circular(20),
      sizeClass: GlassSizeClass.medium,
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // GlassSurface 的描边占内外各 1dp，内容约束预扣 2dp，
            // 让菜单总宽精确落在 [kGlassMenuMinWidth]–上限之间。
            minWidth: math.min(kGlassMenuMinWidth - 2, maxWidth - 2),
            maxWidth: maxWidth - 2,
            maxHeight: maxHeight,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: kGlassMenuVerticalPadding),
              // PopupMenuItem 带 menuItem 语义角色，语义树校验
              // 要求祖先有 menu 角色节点（Material 菜单路由同理）。
              child: Semantics(
                container: true,
                role: SemanticsRole.menu,
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.items,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          // 进出动画只动 opacity/transform：fade 用路由动画的曲线值，
          // 量尺寸完成且滤镜就绪前额外乘 0（首帧先量尺寸/等滤镜
          // 就绪再定位显示，避免跳位与滤镜中途换链的闪烁）。
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, child) => Opacity(
              opacity:
                  _entrance.value * (size == null || !_filterReady ? 0 : 1),
              child: child,
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, opensBelow ? -shiftFraction : shiftFraction),
                end: Offset.zero,
              ).animate(_entrance),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1).animate(_entrance),
                alignment:
                    opensBelow ? Alignment.topCenter : Alignment.bottomCenter,
                child: surface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 玻璃版 PopupMenuButton：API 子集与 Material 版对齐（itemBuilder /
/// onSelected / onOpened / onCanceled / tooltip / icon / child /
/// initialValue），触发按钮的观感与 IconButton 一致（默认 more_vert
/// 图标）。initialValue 在 Material 版里只影响菜单的初始滚动位置，
/// 本实现菜单从顶部排起，不使用它，仅为调用点兼容保留。
class GlassPopupMenuButton<T> extends StatefulWidget {
  const GlassPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.onOpened,
    this.onCanceled,
    this.tooltip,
    this.icon,
    this.child,
    this.enabled = true,
    this.initialValue,
    this.position,
    this.padding = const EdgeInsets.all(8),
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final VoidCallback? onOpened;
  final PopupMenuCanceled? onCanceled;
  final String? tooltip;
  final Widget? icon;
  final Widget? child;
  final bool enabled;
  final T? initialValue;

  /// 仅为兼容保留：本实现统一开在锚点下方（under 语义），空间不足
  /// 翻上方，与 position 取值无关。
  final PopupMenuPosition? position;
  final EdgeInsetsGeometry padding;

  @override
  State<GlassPopupMenuButton<T>> createState() =>
      _GlassPopupMenuButtonState<T>();
}

class _GlassPopupMenuButtonState<T> extends State<GlassPopupMenuButton<T>> {
  Future<void> _showButtonMenu() async {
    final button = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null || !button.hasSize) return;
    widget.onOpened?.call();
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final value = await showGlassMenu<T>(
      context: context,
      position: position,
      items: widget.itemBuilder(context),
      initialValue: widget.initialValue,
    );
    if (!mounted) return;
    if (value != null) {
      widget.onSelected?.call(value);
    } else {
      widget.onCanceled?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (child != null) {
      final trigger = InkWell(
        onTap: widget.enabled ? _showButtonMenu : null,
        child: child,
      );
      return widget.tooltip == null
          ? trigger
          : Tooltip(message: widget.tooltip!, child: trigger);
    }
    return IconButton(
      icon: widget.icon ?? const Icon(Icons.more_vert),
      tooltip: widget.tooltip,
      padding: widget.padding,
      onPressed: widget.enabled ? _showButtonMenu : null,
    );
  }
}
