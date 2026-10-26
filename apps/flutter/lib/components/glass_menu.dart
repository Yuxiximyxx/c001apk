import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;

import 'glass_surface.dart';

/// 玻璃弹出菜单（miuix17）：按苹果 Liquid Glass 规范，弹出菜单属于
/// 悬浮控制层，用 Regular 变体 + medium 面积档的 [GlassSurface] 做面，
/// 替代 Material 的实色菜单面。菜单项直接复用 Flutter 的
/// [PopupMenuItem]/[CheckedPopupMenuItem]/[PopupMenuDivider]——它们的
/// handleTap 自带 onTap + Navigator.pop(value) 语义，放进本路由即可
/// 原样工作，所以调用点只需把 PopupMenuButton 换成
/// [GlassPopupMenuButton]、showMenu 换成 [showGlassMenu]。
///
/// 定位：菜单优先开在锚点下方（Material 的 PopupMenuPosition.under
/// 语义，全应用统一），下方空间不足则翻到锚点上方；水平先对齐锚点
/// 左缘，溢出时改为对齐右缘，四周留 8dp 安全边距。菜单高度超出可用
/// 空间时内部滚动。
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  double? menuMaxHeight,
}) {
  final navigator = Navigator.of(context);
  final overlayBox =
      navigator.context.findRenderObject() as RenderBox?;
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
  Duration get transitionDuration => const Duration(milliseconds: 160);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);

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
    ));
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

class _GlassMenuPanel<T> extends StatefulWidget {
  const _GlassMenuPanel({
    required this.anchorRect,
    required this.items,
    this.menuMaxHeight,
  });

  final Rect anchorRect;
  final List<PopupMenuEntry<T>> items;
  final double? menuMaxHeight;

  @override
  State<_GlassMenuPanel<T>> createState() => _GlassMenuPanelState<T>();
}

class _GlassMenuPanelState<T> extends State<_GlassMenuPanel<T>> {
  final _menuKey = GlobalKey();
  Size? _menuSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _menuKey.currentContext?.findRenderObject() as RenderBox?;
      if (mounted && box != null && box.hasSize) {
        setState(() => _menuSize = box.size);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    const margin = 8.0;
    const gap = 4.0;
    final maxHeight = widget.menuMaxHeight ??
        screen.height - margin * 2 - MediaQuery.paddingOf(context).top;
    final size = _menuSize;
    double left = -10000, top = -10000;
    if (size != null) {
      left = widget.anchorRect.left;
      if (left + size.width > screen.width - margin) {
        left = widget.anchorRect.right - size.width;
      }
      left = left.clamp(margin, math.max(margin, screen.width - margin - size.width));
      top = widget.anchorRect.bottom + gap;
      if (top + size.height > screen.height - margin) {
        top = widget.anchorRect.top - size.height - gap;
      }
      top = top.clamp(margin, math.max(margin, screen.height - margin - size.height));
    }
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Opacity(
            // 首帧先量尺寸再定位，避免菜单跳位。
            opacity: size == null ? 0 : 1,
            child: GlassSurface(
              key: _menuKey,
              borderRadius: BorderRadius.circular(20),
              sizeClass: GlassSizeClass.medium,
              child: Material(
                type: MaterialType.transparency,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 112,
                    maxWidth: 320,
                    maxHeight: maxHeight,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      // PopupMenuItem 带 menuItem 语义角色，语义树校验
                      // 要求祖先有 menu 角色节点（Material 菜单路由同理）。
                      child: Semantics(
                        container: true,
                        role: SemanticsRole.menu,
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
