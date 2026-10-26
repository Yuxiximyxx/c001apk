import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'app_anim.dart';

/// 玻璃加载提示（miuix20 补漏）：SmartDialog 的默认 loading 是实色
/// 深卡，与 toast 同为悬浮提示层，统一换液态玻璃 small 档——经
/// FlutterSmartDialog 的 loadingBuilder 全局生效，所有
/// SmartDialog.showLoading 调用点零改动。滤镜构建期同步挂上，
/// 首帧即终态。
class CustomLoading extends StatelessWidget {
  const CustomLoading({super.key, required this.msg});

  final String msg;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            if (msg.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                msg,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 悬浮提示（miuix17：toast 是悬浮控制层，面换液态玻璃 Regular/small，
/// 与底栏、FAB 同一套参数；文字色改 onSurface 保证在纱上的对比度）。
class CustomToast extends StatelessWidget {
  const CustomToast({super.key, required this.msg});

  final String msg;

  @override
  Widget build(BuildContext context) {
    // miuix18：fade 由 SmartDialog 驱动（其默认 200ms），本组件只补
    // 4dp 微上浮（transform，不叠 opacity 避免双重淡入）。
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppAnim.toastRise,
      curve: AppAnim.enterCurve,
      builder: (context, t, child) =>
          Transform.translate(offset: Offset(0, (1 - t) * 4), child: child),
      child: Container(
        margin:
            EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 30),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
            child: Text(
              msg,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
