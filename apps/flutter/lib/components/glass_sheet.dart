import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// 玻璃底部 sheet（miuix17）：按苹果 Liquid Glass 规范，底部 sheet 是
/// 悬浮在内容之上的控制层，用 Regular 变体 + large 面积档（透镜收敛
/// 到 0.35、band 封顶 14dp）的 [GlassSurface] 做面，替代
/// showModalBottomSheet 的实色面。用法与 showModalBottomSheet 一致，
/// builder 返回的内容原样放进玻璃面（内容里不要再套玻璃，规范禁止
/// 玻璃叠玻璃）。
Future<T?> showGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? barrierColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    barrierColor: barrierColor,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) => GlassSheetSurface(child: builder(context)),
  );
}

/// sheet 的玻璃面本体（顶圆角 28dp，与 Material 3 sheet 形状一致）。
/// 单独成组件便于测试断言与复用。
class GlassSheetSurface extends StatelessWidget {
  const GlassSheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      sizeClass: GlassSizeClass.large,
      highlightHeight: 10,
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}
