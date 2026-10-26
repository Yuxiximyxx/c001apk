import 'package:flutter/material.dart';

import 'app_anim.dart';
import 'glass_surface.dart';

/// 玻璃对话框的展示入口（miuix18）：语义与默认值与框架 showDialog
/// 完全一致（barrier 黑 54%、点击外部可关、根导航器、主题捕获、
/// SafeArea 与焦点语义都由 [DialogRoute] 本体保证，调用点从
/// showDialog 换成本函数即可），仅把进出动画收编到全局规范
/// [AppAnim]：fade（DialogRoute 自带）+ scale 0.96→1，进入 220ms、
/// 退出 150ms。框架默认 DialogRoute 只有 150ms 纯 fade、无缩放。
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push<T>(_GlassDialogRoute<T>(
    context: context,
    builder: builder,
    themes: themes,
    barrierDismissible: barrierDismissible,
  ));
}

class _GlassDialogRoute<T> extends DialogRoute<T> {
  _GlassDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierDismissible,
  }) : super(
          animationStyle: AnimationStyle(
            duration: AppAnim.dialogEnter,
            reverseDuration: AppAnim.dialogExit,
            curve: AppAnim.enterCurve,
            reverseCurve: AppAnim.exitCurve,
          ),
        );

  CurvedAnimation? _scaleAnimation;

  @override
  Duration get reverseTransitionDuration => AppAnim.dialogExit;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (_scaleAnimation?.parent != animation) {
      _scaleAnimation?.dispose();
      _scaleAnimation = CurvedAnimation(
        parent: animation,
        curve: AppAnim.enterCurve,
        reverseCurve: AppAnim.exitCurve,
      );
    }
    return ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1).animate(_scaleAnimation!),
      child:
          super.buildTransitions(context, animation, secondaryAnimation, child),
    );
  }

  @override
  void dispose() {
    _scaleAnimation?.dispose();
    super.dispose();
  }
}

/// 玻璃对话框（miuix17）：按苹果 Liquid Glass 规范，对话框属于悬浮
/// 控制层，用 Regular 变体 + large 面积档（透镜收敛 0.35、band 封顶
/// 14dp）的 [GlassSurface] 做面，替代 AlertDialog 的实色面。布局度量
/// 照 Material 3 AlertDialog（标题/正文/actions 的内边距与字阶），
/// 调用点只需把 AlertDialog 换成本组件；参数子集覆盖全应用现有
/// 用法（title/content/actions/各 padding/scrollable/clipBehavior）。
/// clipBehavior 仅为兼容保留——玻璃面本身已按圆角裁剪。
class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({
    super.key,
    this.title,
    this.titlePadding,
    this.titleTextStyle,
    this.content,
    this.contentPadding,
    this.actions,
    this.actionsPadding,
    this.scrollable = false,
    this.clipBehavior,
  });

  final Widget? title;
  final EdgeInsetsGeometry? titlePadding;
  final TextStyle? titleTextStyle;
  final Widget? content;
  final EdgeInsetsGeometry? contentPadding;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? actionsPadding;
  final bool scrollable;
  final Clip? clipBehavior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActions = actions != null && actions!.isNotEmpty;
    Widget? titleWidget;
    if (title != null) {
      final padding = titlePadding ??
          EdgeInsets.fromLTRB(
              24, 24, 24, content == null && !hasActions ? 24 : 0);
      titleWidget = Padding(
        padding: padding,
        child: DefaultTextStyle(
          style: titleTextStyle ??
              theme.textTheme.titleLarge ??
              const TextStyle(fontSize: 22),
          child: Semantics(container: true, child: title),
        ),
      );
    }
    Widget? contentWidget;
    if (content != null) {
      final padding = contentPadding ??
          EdgeInsets.fromLTRB(24, title == null ? 24 : 20, 24, 24);
      Widget inner = DefaultTextStyle(
        style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ) ??
            const TextStyle(fontSize: 14),
        child: content!,
      );
      if (scrollable) inner = SingleChildScrollView(child: inner);
      contentWidget = Padding(padding: padding, child: inner);
    }
    Widget? actionsWidget;
    if (hasActions) {
      actionsWidget = Padding(
        padding: actionsPadding ?? const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: actions!,
        ),
      );
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(28),
        sizeClass: GlassSizeClass.large,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (titleWidget != null) titleWidget,
              if (contentWidget != null)
                Flexible(fit: FlexFit.loose, child: contentWidget),
              if (actionsWidget != null) actionsWidget,
            ],
          ),
        ),
      ),
    );
  }
}
