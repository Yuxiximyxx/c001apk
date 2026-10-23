import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 全 App 统一的 MIUIX 页面底色：深色用 background(#242424)，
/// 浅色用 surface(#F7F7F7)，与白色卡片(surfaceContainer)形成层次。
/// 底栏、AppBar、页面背景都取这个颜色，避免深浅不一致的色带。
Color miuixPageBackground(BuildContext context) {
  final colors = MiuixTheme.of(context).colors;
  return Theme.of(context).brightness == Brightness.dark
      ? colors.background
      : colors.surface;
}

/// 卡片/面板底色（与 MiuixCard 默认色一致）。
Color miuixPanelColor(BuildContext context) =>
    MiuixTheme.of(context).colors.surfaceContainer;
