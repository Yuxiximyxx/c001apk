import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// 玻璃 SnackBar（miuix20 补漏）：SnackBar 是悬浮在内容之上的提示层，
/// 按全局玻璃标准换成液态玻璃面——保留框架 SnackBar 的队列、滑动
/// 关闭、时长与关闭原因语义，只把面换掉：SnackBar 本体透明无投影，
/// 内容是一块 small 档 [GlassSurface]（与 CustomToast 同源参数），
/// 文字、动作按钮、关闭图标都收进玻璃面内（禁止玻璃叠玻璃，不用
/// SnackBarAction 的面外按钮）。滤镜由 GlassSurface 在构建期同步挂
/// 上，入场第一帧即终态（miuix19 口径）。
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showGlassSnackBar(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  bool showCloseIcon = false,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.of(context);
  return messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      duration: duration,
      content: GlassSurface(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (actionLabel != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    onAction?.call();
                    messenger.hideCurrentSnackBar();
                  },
                  child: Text(actionLabel),
                ),
              ],
              if (showCloseIcon)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onPressed: () => messenger.hideCurrentSnackBar(),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
