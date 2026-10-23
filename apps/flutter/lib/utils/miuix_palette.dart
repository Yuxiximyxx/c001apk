import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// MIUIX 规范底色映射（flutter_miuix 色板语义）：
/// - 页面/窗口底色 = surface（浅 #F7F7F7 / 深 #000000 纯黑）
/// - 卡片/面板底色 = background（浅 #FFFFFF / 深 #242424）
/// 全 App 的页面、AppBar、底栏都取 surface，卡片取 background，
/// 保证深浅两色层次与 MIUIX 官方一致、不出现色带。
Color miuixPageBackground(BuildContext context) =>
    MiuixTheme.of(context).colors.surface;

/// 卡片/面板底色。
Color miuixPanelColor(BuildContext context) =>
    MiuixTheme.of(context).colors.background;
