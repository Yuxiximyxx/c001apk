import 'package:flutter/material.dart';

import 'glass_surface.dart';

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
