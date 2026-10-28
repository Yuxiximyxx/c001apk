import 'package:flutter/animation.dart';

/// 全局动画规范（miuix18 起收编）：时长分三级、曲线按方向分工，
/// 玻璃面与主要转场一律从这里取常量，禁止再散落硬编码魔数。
///
/// 时长分级：
/// - [fast] 快速（120–150ms）：小控件的即时反馈（按下缩放、淡入淡出）；
/// - [standard] 标准（200–250ms）：常规面的进出（菜单/对话框/sheet）；
/// - [emphasized] 强调（≤340ms）：大位移与共享元素转场的上限。
///
/// 曲线分工：进入用 [enterCurve]（easeOutQuint 型：起步利落、收尾
/// 长尾缓降）、退出用 [exitCurve]（easeInCubic，干脆离场，退出恒短
/// 于进入）、共享元素/大位移用 [sharedCurve]（easeOutExpo 型：起步
/// 更果断、落点更柔）。miuix23 按小乐「转场太生硬」反馈整体软化：
/// 原 easeOutCubic/easeOutQuart 尾段衰减太快、300ms 内显得急停，
/// 换长尾曲线并把页面时长放宽到 340ms，接近弹簧的收尾手感。
///
/// 玻璃面动画只动 opacity/transform，绝不动 blur sigma/滤镜参数
/// （逐帧重建滤镜链是掉帧源）。
abstract final class AppAnim {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration emphasized = Duration(milliseconds: 340);

  /// 页面转场（GetX 路由 + 锚定容器转场共用）。
  static const Duration page = emphasized;

  /// 玻璃菜单：从锚点方向 fade + scale 0.95→1 + ≤4dp 微位移。
  static const Duration menuEnter = Duration(milliseconds: 200);
  static const Duration menuExit = Duration(milliseconds: 130);

  /// 玻璃对话框：fade + scale 0.96→1。
  static const Duration dialogEnter = Duration(milliseconds: 220);
  static const Duration dialogExit = fast;

  /// 玻璃底部 sheet：自下滑动 + fade（framework 路由驱动，只覆写
  /// 时长与曲线常量）。
  static const Duration sheetEnter = Duration(milliseconds: 260);
  static const Duration sheetExit = Duration(milliseconds: 200);

  /// toast 微上浮（fade 由 SmartDialog 驱动，200ms；上浮与之对齐）。
  static const Duration toastRise = Duration(milliseconds: 200);

  static const Curve enterCurve = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Curve exitCurve = Curves.easeInCubic;
  static const Curve sharedCurve = Cubic(0.16, 1.0, 0.3, 1.0);
}
