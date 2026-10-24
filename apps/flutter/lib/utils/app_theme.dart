import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' as miuix;

import 'storage_util.dart';

/// 当前应用级字体族：开启「使用系统字体」（默认开启）时为 'sans-serif'，
/// Android 上由系统解析为设备默认字体（HyperOS 上即 MiSans）；
/// 关闭时为 null，恢复 Flutter 默认字体。
String? get appFontFamily =>
    GStorage.settings.get(SettingsBoxKey.useSystemFont, defaultValue: true)
        ? 'sans-serif'
        : null;

/// 构建带应用字体设置的 [miuix.MiuixThemeData]：开启系统字体时把
/// MIUIX 文本样式集的每个样式都换上系统字体族，保证 MIUIX 组件文字跟随。
miuix.MiuixThemeData appMiuixThemeData(Brightness brightness) {
  final data = miuix.MiuixThemeData.of(brightness);
  final fontFamily = appFontFamily;
  if (fontFamily == null) return data;
  TextStyle withFont(TextStyle style) =>
      style.copyWith(fontFamily: fontFamily);
  final styles = data.textStyles;
  return data.copyWith(
    textStyles: styles.copy(
      main: withFont(styles.main),
      paragraph: withFont(styles.paragraph),
      body1: withFont(styles.body1),
      body2: withFont(styles.body2),
      button: withFont(styles.button),
      footnote1: withFont(styles.footnote1),
      footnote2: withFont(styles.footnote2),
      headline1: withFont(styles.headline1),
      headline2: withFont(styles.headline2),
      subtitle: withFont(styles.subtitle),
      title1: withFont(styles.title1),
      title2: withFont(styles.title2),
      title3: withFont(styles.title3),
      title4: withFont(styles.title4),
    ),
  );
}

/// Typography follows the reference app's compact page titles and setting
/// descriptions while retaining Material's normal body sizes and touch targets.
ThemeData applyAppTypography(ThemeData theme) => theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
            fontSize: 16,
            color: theme.colorScheme.onSurface,
            fontFamily: appFontFamily),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        titleTextStyle: TextStyle(
            fontSize: 16,
            color: theme.colorScheme.onSurface,
            fontFamily: appFontFamily),
        subtitleTextStyle: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.outline,
            fontWeight: FontWeight.normal,
            fontFamily: appFontFamily),
      ),
      dialogTheme: theme.dialogTheme.copyWith(
        titleTextStyle: TextStyle(
            fontSize: 18,
            color: theme.colorScheme.onSurface,
            fontFamily: appFontFamily),
      ),
    );

class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}
