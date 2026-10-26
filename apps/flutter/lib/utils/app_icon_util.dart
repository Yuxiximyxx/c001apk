import 'package:flutter/services.dart';

/// 可切换的桌面图标变体（仅 Android）：清单里两个 activity-alias 各
/// 带一个启动图标，原生侧保证同一时刻恰好启用一个（见 MainActivity
/// 的 app_icon 通道）。
enum AppIconVariant {
  standard('default', '默认图标'),
  coolGreen('green', '酷安绿');

  const AppIconVariant(this.id, this.label);

  /// 与原生通道约定的变体 id（MainActivity 的 alias 映射键）。
  final String id;
  final String label;

  /// 设置页里展示的图标预览资源。
  String get previewAsset => switch (this) {
        AppIconVariant.standard => 'assets/icon/icon.png',
        AppIconVariant.coolGreen => 'assets/icon/icon_green.png',
      };

  static AppIconVariant fromId(String? id) => AppIconVariant.values.firstWhere(
        (variant) => variant.id == id,
        orElse: () => AppIconVariant.standard,
      );
}

/// 图标切换的通道封装。通道名与方法名必须与 MainActivity 注册的
/// `app.awavenue.c001apk/app_icon` 保持一致。
class AppIconUtil {
  AppIconUtil._();

  static const MethodChannel channel =
      MethodChannel('app.awavenue.c001apk/app_icon');

  /// 应用 [variant]，返回原生侧实际生效的变体；通道不可用或切换失败
  /// 时返回 null，调用方应保持原有选择不变。
  static Future<AppIconVariant?> applyIcon(AppIconVariant variant) async {
    try {
      final applied = await channel.invokeMethod<String>(
        'setAppIcon',
        {'variant': variant.id},
      );
      return applied == null ? null : AppIconVariant.fromId(applied);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 查询原生侧当前实际启用的变体（设置页以存储值为准，此方法仅作
  /// 对账用）；通道不可用时返回 null。
  static Future<AppIconVariant?> currentIcon() async {
    try {
      final current = await channel.invokeMethod<String>('getAppIcon');
      return current == null ? null : AppIconVariant.fromId(current);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
