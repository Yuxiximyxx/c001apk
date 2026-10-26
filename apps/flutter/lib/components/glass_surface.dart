import 'dart:ui' as ui
    show
        Canvas,
        ColorFilter,
        FragmentProgram,
        ImageFilter,
        Paint,
        PictureRecorder;

import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/storage_util.dart';
import 'app_anim.dart';

/// 玻璃材质（设置项「玻璃材质」，以 int 索引存设置盒
/// [SettingsBoxKey.dockGlassMaterial]），悬浮 Dock 与全应用悬浮按钮共用。
/// miuix16 按「身份」重新拉开三档（miuix14 的参数在真实信息流背景上
/// 差异太小、切换后几乎看不出区别，小乐真机反馈）：毛玻璃=最清透、
/// 磨砂=最哑光、液态=折射最强，逐项对照见 [DockGlassMaterialSpec]。
enum DockGlassMaterial {
  /// 毛玻璃：模糊最轻、饱和最高、纱最薄、rim 高光最亮、透镜中低。
  clear,

  /// 磨砂玻璃（默认）：模糊最重、纱最厚、饱和最低（哑光）、透镜最弱。
  frosted,

  /// 液态玻璃：模糊次轻、纱薄、透镜最强 + 光谱色散。
  liquid;

  static DockGlassMaterial fromStorage(Object? value) =>
      value is int && value >= 0 && value < values.length
          ? values[value]
          : DockGlassMaterial.frosted;
}

/// 一种玻璃材质的完整参数。配方出处：liquid-glass-recipes 三档 +
/// Kyant0/AndroidLiquidGlass 的透镜模型（miuix16 起底栏本体三档都带
/// circleMap 剖面透镜，参数按身份拉开，见各档数值）。
class DockGlassSpec {
  const DockGlassSpec({
    required this.sigma,
    required this.saturate,
    required this.tintAlphaDark,
    required this.tintAlphaLight,
    required this.highlightAlphaDark,
    required this.highlightAlphaLight,
    required this.borderAlphaDark,
    required this.borderAlphaLight,
    required this.refractionBandDp,
    required this.refractionAmountDp,
    required this.dispersion,
  });

  final double sigma;
  final double saturate;
  final double tintAlphaDark;
  final double tintAlphaLight;
  final double highlightAlphaDark;
  final double highlightAlphaLight;
  final double borderAlphaDark;
  final double borderAlphaLight;

  /// 底栏本体透镜的折射带宽（dp，Kyant refractionHeight）。
  final double refractionBandDp;

  /// 底栏本体透镜的折射量（dp，Kyant refractionAmount，正值；
  /// shader 内取负实现向内采样）。
  final double refractionAmountDp;

  /// 光谱色散强度（0=关，单采样快路径；Kyant 典型 0.1  subtle /
  /// 0.2 类 Apple 药丸 / 0.3+ 明显彩虹边）。
  final double dispersion;

  /// 是否带透镜折射（三档恒 true，量不同；保留此派生量供旧断言语义）。
  bool get refraction => refractionAmountDp > 0;

  DockGlassSpec copyWith({
    double? sigma,
    double? saturate,
    double? tintAlphaDark,
    double? tintAlphaLight,
    double? highlightAlphaDark,
    double? highlightAlphaLight,
    double? borderAlphaDark,
    double? borderAlphaLight,
    double? refractionBandDp,
    double? refractionAmountDp,
    double? dispersion,
  }) =>
      DockGlassSpec(
        sigma: sigma ?? this.sigma,
        saturate: saturate ?? this.saturate,
        tintAlphaDark: tintAlphaDark ?? this.tintAlphaDark,
        tintAlphaLight: tintAlphaLight ?? this.tintAlphaLight,
        highlightAlphaDark: highlightAlphaDark ?? this.highlightAlphaDark,
        highlightAlphaLight: highlightAlphaLight ?? this.highlightAlphaLight,
        borderAlphaDark: borderAlphaDark ?? this.borderAlphaDark,
        borderAlphaLight: borderAlphaLight ?? this.borderAlphaLight,
        refractionBandDp: refractionBandDp ?? this.refractionBandDp,
        refractionAmountDp: refractionAmountDp ?? this.refractionAmountDp,
        dispersion: dispersion ?? this.dispersion,
      );

  @override
  bool operator ==(Object other) =>
      other is DockGlassSpec &&
      other.sigma == sigma &&
      other.saturate == saturate &&
      other.tintAlphaDark == tintAlphaDark &&
      other.tintAlphaLight == tintAlphaLight &&
      other.highlightAlphaDark == highlightAlphaDark &&
      other.highlightAlphaLight == highlightAlphaLight &&
      other.borderAlphaDark == borderAlphaDark &&
      other.borderAlphaLight == borderAlphaLight &&
      other.refractionBandDp == refractionBandDp &&
      other.refractionAmountDp == refractionAmountDp &&
      other.dispersion == dispersion;

  @override
  int get hashCode => Object.hash(
      sigma,
      saturate,
      tintAlphaDark,
      tintAlphaLight,
      highlightAlphaDark,
      highlightAlphaLight,
      borderAlphaDark,
      borderAlphaLight,
      refractionBandDp,
      refractionAmountDp,
      dispersion);

  /// 按苹果 Liquid Glass 规范的变体/面积规则派生某个具体玻璃面实际
  /// 使用的参数（miuix17）：玻璃只长在悬浮控制层上，面积越大、离
  /// 「小控件」越远，透镜越要收敛——大面全量折射会把整页内容弯得
  /// 没法读。系数（相对有效 spec 的全量值）：
  /// - small（FAB/底栏/药丸等小控件）：amount ×1.0、band ×1.0；
  /// - medium（弹出菜单/回复输入卡）：amount ×0.6、band ×0.6（band
  ///   封顶 20dp）；
  /// - large（底部 sheet/对话框）：amount ×0.35、band ×0.35（band
  ///   封顶 14dp）；
  /// - clear 变体（只用于媒体内容之上的控制层，其下另有压暗层）：
  ///   透镜同 large，纱 alpha ×0.5、模糊 sigma ×0.85（更透）。
  DockGlassSpec adjustedForSurface({
    required GlassVariant variant,
    required GlassSizeClass sizeClass,
  }) {
    if (variant == GlassVariant.clear) {
      return copyWith(
        sigma: sigma * 0.85,
        tintAlphaDark: tintAlphaDark * 0.5,
        tintAlphaLight: tintAlphaLight * 0.5,
        refractionBandDp: _cappedBand(0.35, 14),
        refractionAmountDp: refractionAmountDp * 0.35,
      );
    }
    switch (sizeClass) {
      case GlassSizeClass.small:
        return this;
      case GlassSizeClass.medium:
        return copyWith(
          refractionBandDp: _cappedBand(0.6, 20),
          refractionAmountDp: refractionAmountDp * 0.6,
        );
      case GlassSizeClass.large:
        return copyWith(
          refractionBandDp: _cappedBand(0.35, 14),
          refractionAmountDp: refractionAmountDp * 0.35,
        );
    }
  }

  double _cappedBand(double scale, double cap) {
    final scaled = refractionBandDp * scale;
    return scaled < cap ? scaled : cap;
  }
}

/// 玻璃变体（苹果 Liquid Glass 的 Regular / Clear）：
/// regular 自适应保可读性，绝大多数悬浮面用它；clear 更透明，只用在
/// 媒体内容之上的元素（图片查看器控制层），且其下须有压暗层。
enum GlassVariant { regular, clear }

/// 玻璃面的面积档，决定透镜折射的收敛系数（见
/// [DockGlassSpec.adjustedForSurface]）。
enum GlassSizeClass { small, medium, large }

extension DockGlassMaterialSpec on DockGlassMaterial {
  DockGlassSpec get spec => switch (this) {
        // 毛玻璃（最清透）：模糊最轻、饱和最高、纱最薄、高光最亮。
        DockGlassMaterial.clear => const DockGlassSpec(
            sigma: 6,
            saturate: 1.8,
            tintAlphaDark: 0.16,
            tintAlphaLight: 0.18,
            highlightAlphaDark: 0.60,
            highlightAlphaLight: 0.95,
            borderAlphaDark: 0.30,
            borderAlphaLight: 0.55,
            refractionBandDp: 16,
            refractionAmountDp: 10,
            dispersion: 0,
          ),
        // 磨砂玻璃（最哑光）：模糊最重、纱最厚（相对本组；深色基仍
        // #121212 深纱，不回 1.7.0 的乳白厚涂）、饱和最低、透镜最弱。
        DockGlassMaterial.frosted => const DockGlassSpec(
            sigma: 20,
            saturate: 1.3,
            tintAlphaDark: 0.55,
            tintAlphaLight: 0.58,
            highlightAlphaDark: 0.12,
            highlightAlphaLight: 0.30,
            borderAlphaDark: 0.30,
            borderAlphaLight: 0.55,
            refractionBandDp: 20,
            refractionAmountDp: 6,
            dispersion: 0,
          ),
        // 液态玻璃：模糊次轻、纱薄、透镜 = Kyant 原方 24/24 + 色散。
        DockGlassMaterial.liquid => const DockGlassSpec(
            sigma: 8,
            saturate: 1.5,
            tintAlphaDark: 0.32,
            tintAlphaLight: 0.32,
            highlightAlphaDark: 0.50,
            highlightAlphaLight: 0.85,
            borderAlphaDark: 0.50,
            borderAlphaLight: 0.70,
            refractionBandDp: glassRefractionBandDp,
            refractionAmountDp: glassRefractionAmountDp,
            dispersion: 0.2,
          ),
      };
}

/// 饱和度 ColorFilter 矩阵（luma 0.213/0.715/0.072）。
List<double> dockSaturationMatrix(double s) => <double>[
      0.213 + 0.787 * s,
      0.715 - 0.715 * s,
      0.072 - 0.072 * s,
      0,
      0,
      0.213 - 0.213 * s,
      0.715 + 0.285 * s,
      0.072 - 0.072 * s,
      0,
      0,
      0.213 - 0.213 * s,
      0.715 - 0.715 * s,
      0.072 + 0.928 * s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];

/// 读取设置里的玻璃材质（设置盒不可用时回退默认磨砂）。
DockGlassMaterial currentDockGlassMaterial() {
  try {
    return DockGlassMaterial.fromStorage(
        GStorage.settings.get(SettingsBoxKey.dockGlassMaterial));
  } catch (_) {
    return DockGlassMaterial.frosted;
  }
}

/// 玻璃材质设置的可监听对象；设置盒未初始化时（如未初始化 Hive 的
/// 测试环境）返回 null，调用方退回 [currentDockGlassMaterial] 静态读取，
/// 不要直接碰 late 的 GStorage.settings 而抛 LateInitializationError。
ValueListenable<Box<dynamic>>? dockGlassMaterialListenable() {
  try {
    return GStorage.settings
        .listenable(keys: [SettingsBoxKey.dockGlassMaterial]);
  } catch (_) {
    return null;
  }
}

/// 玻璃全部设置（预设 + 自定义参数）的可监听对象：任一处改动都经它
/// 触发所有玻璃面重建，滑杆拖动即时全局生效（miuix17）。
ValueListenable<Box<dynamic>>? dockGlassSettingsListenable() {
  try {
    return GStorage.settings.listenable(keys: [
      SettingsBoxKey.dockGlassMaterial,
      SettingsBoxKey.dockGlassCustom,
    ]);
  } catch (_) {
    return null;
  }
}

/// 自定义玻璃参数（设置页滑杆组）在设置盒 [SettingsBoxKey.dockGlassCustom]
/// 里存的字段名。滑杆一律存**绝对值**（即该字段就是 spec 的对应分量），
/// 全应用只有这一份事实源；字段缺失时逐项回退到当前预设的分量。
class DockGlassCustomField {
  static const sigma = 'sigma';
  static const saturate = 'saturate';
  static const tintDark = 'tintDark';
  static const tintLight = 'tintLight';
  static const highlightDark = 'highlightDark';
  static const highlightLight = 'highlightLight';
  static const borderDark = 'borderDark';
  static const borderLight = 'borderLight';
  static const band = 'band';
  static const amount = 'amount';
  static const dispersion = 'dispersion';
}

/// 把一份 spec 全字段写成自定义参数（选中预设、拖动滑杆、恢复预设
/// 都走这里，保证存储里的自定义值永远是完整的一份 spec）。
Map<String, double> dockGlassCustomFromSpec(DockGlassSpec spec) => {
      DockGlassCustomField.sigma: spec.sigma,
      DockGlassCustomField.saturate: spec.saturate,
      DockGlassCustomField.tintDark: spec.tintAlphaDark,
      DockGlassCustomField.tintLight: spec.tintAlphaLight,
      DockGlassCustomField.highlightDark: spec.highlightAlphaDark,
      DockGlassCustomField.highlightLight: spec.highlightAlphaLight,
      DockGlassCustomField.borderDark: spec.borderAlphaDark,
      DockGlassCustomField.borderLight: spec.borderAlphaLight,
      DockGlassCustomField.band: spec.refractionBandDp,
      DockGlassCustomField.amount: spec.refractionAmountDp,
      DockGlassCustomField.dispersion: spec.dispersion,
    };

/// 读取存储里的自定义玻璃参数；未存过（老用户/未动过滑杆）返回 null。
Map<String, double>? readDockGlassCustom() {
  try {
    final raw = GStorage.settings.get(SettingsBoxKey.dockGlassCustom);
    if (raw is! Map || raw.isEmpty) return null;
    final result = <String, double>{};
    raw.forEach((key, value) {
      if (key is String && value is num) result[key] = value.toDouble();
    });
    return result.isEmpty ? null : result;
  } catch (_) {
    return null;
  }
}

/// 有效 spec 的唯一解析点：有自定义参数就以它为准（逐字段缺失回退
/// 预设分量），没有就原样返回预设 spec——所以老用户升级后、以及从未
/// 动过滑杆时，玻璃观感与 miuix16 逐值一致。
DockGlassSpec resolveDockGlassSpec({
  DockGlassMaterial? material,
  Map<String, double>? custom,
}) {
  final preset = (material ?? currentDockGlassMaterial()).spec;
  final values = custom ?? readDockGlassCustom();
  if (values == null) return preset;
  double pick(String key, double fallback) => values[key] ?? fallback;
  return DockGlassSpec(
    sigma: pick(DockGlassCustomField.sigma, preset.sigma),
    saturate: pick(DockGlassCustomField.saturate, preset.saturate),
    tintAlphaDark: pick(DockGlassCustomField.tintDark, preset.tintAlphaDark),
    tintAlphaLight: pick(DockGlassCustomField.tintLight, preset.tintAlphaLight),
    highlightAlphaDark:
        pick(DockGlassCustomField.highlightDark, preset.highlightAlphaDark),
    highlightAlphaLight:
        pick(DockGlassCustomField.highlightLight, preset.highlightAlphaLight),
    borderAlphaDark:
        pick(DockGlassCustomField.borderDark, preset.borderAlphaDark),
    borderAlphaLight:
        pick(DockGlassCustomField.borderLight, preset.borderAlphaLight),
    refractionBandDp: pick(DockGlassCustomField.band, preset.refractionBandDp),
    refractionAmountDp:
        pick(DockGlassCustomField.amount, preset.refractionAmountDp),
    dispersion: pick(DockGlassCustomField.dispersion, preset.dispersion),
  );
}

/// 当前有效 spec（预设 + 自定义覆盖，存储不可用时回退默认预设）。
DockGlassSpec currentDockGlassSpec() {
  try {
    return resolveDockGlassSpec();
  } catch (_) {
    return DockGlassMaterial.frosted.spec;
  }
}

/// 是否处于「自定义」态：存有自定义参数且与上次选中的预设数值不一致
/// （用户拖过滑杆）。设置页据此决定预设 chips 显示选中还是「自定义」。
bool dockGlassIsCustomized() {
  final custom = readDockGlassCustom();
  if (custom == null) return false;
  return resolveDockGlassSpec(custom: custom) !=
      currentDockGlassMaterial().spec;
}

/// 把一份 spec 作为自定义参数写入设置盒（滑杆拖动的落盘点）。
Future<void> writeDockGlassCustom(DockGlassSpec spec) => GStorage.settings
    .put(SettingsBoxKey.dockGlassCustom, dockGlassCustomFromSpec(spec));

/// 选中预设：预设索引与「把该预设数值写入滑杆组」同时落盘，此后有效
/// spec 由滑杆值（=预设值）决定，chips 回到该预设的选中态。
Future<void> selectDockGlassPreset(DockGlassMaterial material) async {
  await GStorage.settings.put(SettingsBoxKey.dockGlassMaterial, material.index);
  await writeDockGlassCustom(material.spec);
}

/// 材质对应的纱颜色：Kyant 配方——深色走近透明黑 #121212、浅色走
/// #FAFAFA，透明度取自配方参数（深色模式不再用乳白纱，避免泛白）。
Color glassTintColor(DockGlassSpec spec, bool dark) => dark
    ? const Color(0xFF121212).withValues(alpha: spec.tintAlphaDark)
    : const Color(0xFFFAFAFA).withValues(alpha: spec.tintAlphaLight);

/// 材质对应的描边颜色。
Color glassBorderColor(DockGlassSpec spec, bool dark) => Colors.white
    .withValues(alpha: dark ? spec.borderAlphaDark : spec.borderAlphaLight);

/// 材质对应的顶部高光强度。
double glassHighlightAlpha(DockGlassSpec spec, bool dark) =>
    dark ? spec.highlightAlphaDark : spec.highlightAlphaLight;

/// 玻璃面上的图标颜色（与 Dock 未选中项一致，深色近白、浅色深灰，
/// 保证在乳纱上的对比度）。
Color glassIconColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.95)
        : const Color(0xFF3F4145);

/// 全应用玻璃面与 fluid_glass 组件之间的**唯一颜色映射点**（miuix22
/// 自 floating_dock_bar.dart 迁来此处，成为所有玻璃面共用的映射）：
/// fluid 的组件/原语只开放颜色入口，光学（blur 8 / vibrancy 1.5 /
/// lens 24·24 一系）在库内写死为 Kyant 原方——能经 [LiquidGlassColors]
/// 进引擎的只有颜色：
/// - accent ← 应用强调色（选中标记、药丸内标签副本的染色）；
/// - container ← [glassTintColor]（spec 的纱基色 #121212/#FAFAFA
///   + tintAlpha，即三预设身份与「透明度」滑杆经此生效）。
/// 其余 spec 字段在 fluid 侧的去向：refractionBandDp /
/// refractionAmountDp / dispersion 经 [GlassSurface] 的效果链以
/// lens 参数进入（见 _buildSurface）；highlightAlpha /
/// borderAlpha 分别经 Highlight 与描边进入；sigma / saturate 无入口
/// （fluid 写死 blur 半径 8 与 vibrancy 1.5），不要在此静默吞掉别的
/// 字段——新增映射先过这里。
LiquidGlassColors dockGlassColorsForSpec(
  DockGlassSpec spec, {
  required bool dark,
  required Color accent,
}) {
  final base = LiquidGlassColors.forBrightness(
      dark ? Brightness.dark : Brightness.light);
  return base.copyWith(
    accent: accent,
    container: glassTintColor(spec, dark),
  );
}

/// 把 Flutter 的 [BorderRadius] 换算成 fluid 的形状：四角半径原样
/// 传入（fluid 的 lens 按形状的真实角算 SDF——miuix19 的同心圆弧
/// bug 类在新引擎里由构造消除）；统一半径走 [RoundedRectangle]，
/// 非统一走 [UnevenRoundedRectangle] 并按文字方向把物理左右角映射
/// 到 start/end。角样式用 fluid 原生的 continuous（与 Dock 的
/// LiquidBottomTabs 同款轮廓）。
RoundedRectangularShape glassShapeForBorderRadius(
  BorderRadius radius,
  TextDirection direction,
) {
  final tl = radius.topLeft.x;
  final tr = radius.topRight.x;
  final br = radius.bottomRight.x;
  final bl = radius.bottomLeft.x;
  if (tl == tr && tr == br && br == bl) return RoundedRectangle(tl);
  final ltr = direction == TextDirection.ltr;
  return UnevenRoundedRectangle(RectangleCornerRadii(
    topStart: ltr ? tl : tr,
    topEnd: ltr ? tr : tl,
    bottomEnd: ltr ? br : bl,
    bottomStart: ltr ? bl : br,
  ));
}

/// 向子树提供一块可采样录制的注入点：只有「消费者在录制子树之外」
/// 的面才许提供（Kyant 采样硬规则，消费者在被录子树内自采样会
/// 形成反馈）。当前只有图片查看器提供（录制 pager、箭头在录制
/// 之外采样）；其余面不提供、走 [nativeBackdrop] 的合成器路径。
class GlassBackdropScope extends InheritedWidget {
  const GlassBackdropScope({
    super.key,
    required this.backdrop,
    required super.child,
  });

  final LayerBackdrop backdrop;

  static LayerBackdrop? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GlassBackdropScope>()
      ?.backdrop;

  @override
  bool updateShouldNotify(GlassBackdropScope oldWidget) =>
      !identical(backdrop, oldWidget.backdrop);
}

/// 玻璃面实际采样的 backdrop 解析（miuix22）：
/// - 运行时 shader 不可用（Skia 回退/测试环境）→ 一律 [nativeBackdrop]
///   （合成器 BackdropFilter 路径：模糊+纱色+ rim，无折射的等价呈现，
///   功能不受影响）；
/// - 子树有 [GlassBackdropScope] 注入的录制 → 用录制（真折射）；
/// - 否则 [nativeBackdrop]——菜单/对话框/sheet/toast 等模态面浮在
///   内容之上，合成器路径自带 barrier 变暗、无冻结帧、零录制成本，
///   也是 fluid 官方对这类面的推荐（LiquidSheet/LiquidDialog 文档）。
Backdrop fluidGlassBackdropOf(BuildContext context) {
  if (!isRuntimeShaderSupported()) return nativeBackdrop;
  return GlassBackdropScope.maybeOf(context) ?? nativeBackdrop;
}

/// fluid 面板的模糊半径（Kyant 原方，与 LiquidPanel 默认值、
/// LiquidBottomTabs 面板同值；fluid 的 blur() 吃 Android 式半径，
/// 内部换算 sigma）。
const double fluidGlassBlurRadius = 8;

/// 折射 shader 的一次性加载+能力探测：ImageFilter.shader 仅 Impeller
/// 可用，Skia 后端（测试环境、无 Vulkan 的老设备回退）在绘制时会抛
/// UnsupportedError 且无法在使用点 catch，所以先用 2x2 离屏绘制探一遍，
/// 不可用就返回 null，三档一律退回无透镜的滤镜链（饱和+模糊不变）。
/// 全应用共享同一次加载。
///
/// miuix22 注记：本管线（[RefractionSupport] / [glassImageFilter] /
/// [glassShaderUniformValues] 与 assets/shaders/dock_refraction.frag）
/// 已冻结——全应用玻璃面迁 fluid_glass 后，只剩冻结不改的 Dock
/// 回落路（floating_dock_bar.dart 的选中药丸）在用它，故不删除、
/// 也不再往新面扩散。
///
/// miuix19：加载结果同步缓存（[cachedProgram]/[settled]）。此前每个
/// GlassSurface 都在 initState 里各自 .then 异步取 program——首次
/// build 时 program 恒为 null（先用无透镜滤镜链），回调落地后
/// setState 把整条滤镜链换掉，菜单这种在入场动画里被盯着看的面就
/// 会出现「第一帧玻璃没到位、闪一下才完整」的跳变。改为 initState
/// 同步读缓存：加载早已完成时（常态，应用启动时 Dock 已触发加载），
/// 每个新玻璃面第一帧就是完整滤镜链，不再有中途换链。
class RefractionSupport {
  static Future<ui.FragmentProgram?>? _future;
  static ui.FragmentProgram? _cachedProgram;
  static bool _settled = false;

  /// 最近一次加载完成后的 program（未完成/不可用时为 null，配合
  /// [settled] 区分「还没加载完」与「加载完但不可用」）。
  static ui.FragmentProgram? get cachedProgram => _cachedProgram;

  /// 加载是否已完成（成功或失败都算完成）。
  static bool get settled => _settled;

  static Future<ui.FragmentProgram?> load() => _future ??= _load();

  static Future<ui.FragmentProgram?> _load() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
          'assets/shaders/dock_refraction.frag');
      final shader = program.fragmentShader();
      // uniform 布局与 glassShaderUniformValues 对齐（11 个 float）。
      const probe = <double>[
        2, 2, // uSize
        2, // uBand
        2, // uAmount
        0.2, // uDispersion
        0.5, // uRim
        0.3, // uInnerShadow
        1, 1, 1, 1, // uRadii (TL/TR/BR/BL)
      ];
      for (var i = 0; i < probe.length; i++) {
        shader.setFloat(i, probe[i]);
      }
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()..imageFilter = ui.ImageFilter.shader(shader);
      canvas.saveLayer(null, paint);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
      canvas.restore();
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      image.dispose();
      picture.dispose();
      _cachedProgram = program;
      _settled = true;
      return program;
    } catch (_) {
      _cachedProgram = null;
      _settled = true;
      return null;
    }
  }
}

/// 液态档底栏本体透镜的折射带宽（dp，Kyant lens 的 refractionHeight；
/// 液态 spec 直接引用此常量，三档数值见 [DockGlassSpec]）。
const double glassRefractionBandDp = 24;

/// 液态档底栏本体透镜的折射量（dp，Kyant lens 的 refractionAmount；
/// miuix16 起剖面换 Kyant circleMap——边缘处即达全量，不再减半）。
const double glassRefractionAmountDp = 24;

/// 折射 shader 的 uniform 值（顺序与 dock_refraction.frag 的声明
/// 严格对应）：[宽, 高, band, amount, dispersion, rim, innerShadow,
/// 半径 TL, TR, BR, BL]，长度/半径类一律物理像素。单独成纯函数便于
/// 测试钉住管线（miuix19：半径必须传玻璃面的**真实**四角半径——
/// shader 里的 SDF 按它算，传错就会在面内画出假轮廓弧线）。
List<double> glassShaderUniformValues({
  required DockGlassSpec spec,
  required Size size,
  required double dpr,
  required BorderRadius cornerRadii,
  double? refractionBandDp,
  double? refractionAmountDp,
  double? dispersion,
  double rimStrength = 0,
  double innerShadow = 0,
}) {
  final band = refractionBandDp ?? spec.refractionBandDp;
  final amount = refractionAmountDp ?? spec.refractionAmountDp;
  return <double>[
    size.width * dpr,
    size.height * dpr,
    band * dpr,
    amount * dpr,
    dispersion ?? spec.dispersion,
    rimStrength,
    innerShadow,
    cornerRadii.topLeft.x * dpr,
    cornerRadii.topRight.x * dpr,
    cornerRadii.bottomRight.x * dpr,
    cornerRadii.bottomLeft.x * dpr,
  ];
}

/// 玻璃滤镜链（Kyant 顺序）：饱和提升（vibrancy）→ 模糊打底 →
/// （shader 可用时）circleMap 剖面透镜折射。miuix16 起三档底栏本体
/// 都走透镜（量按档拉开）；折射带宽/量、色散强度可覆写（Dock 药丸
/// 透镜按 pressProgress 驱动，见 floating_dock_bar.dart），不传时用
/// spec 的档位值。[rimStrength] 为 shader 边缘镜面高光强度、
/// [innerShadow] 为底部内阴影强度（0=关）。[cornerRadii] 是玻璃面
/// 的真实圆角（miuix19 起必传，见 [glassShaderUniformValues]）。
ui.ImageFilter glassImageFilter({
  required DockGlassSpec spec,
  required Size size,
  required double dpr,
  required ui.FragmentProgram? refractionProgram,
  required BorderRadius cornerRadii,
  double? blurSigma,
  double? refractionBandDp,
  double? refractionAmountDp,
  double? dispersion,
  double rimStrength = 0,
  double innerShadow = 0,
}) {
  final sigma = blurSigma ?? spec.sigma;
  ui.ImageFilter filter =
      ui.ColorFilter.matrix(dockSaturationMatrix(spec.saturate));
  filter = ui.ImageFilter.compose(
    outer: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    inner: filter,
  );
  final band = refractionBandDp ?? spec.refractionBandDp;
  final amount = refractionAmountDp ?? spec.refractionAmountDp;
  final program = refractionProgram;
  if (program != null && band > 0 && amount > 0) {
    final values = glassShaderUniformValues(
      spec: spec,
      size: size,
      dpr: dpr,
      cornerRadii: cornerRadii,
      refractionBandDp: refractionBandDp,
      refractionAmountDp: refractionAmountDp,
      dispersion: dispersion,
      rimStrength: rimStrength,
      innerShadow: innerShadow,
    );
    final shader = program.fragmentShader();
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    filter = ui.ImageFilter.compose(
        outer: ui.ImageFilter.shader(shader), inner: filter);
  }
  return filter;
}

/// 共享玻璃面（miuix22 起出图引擎换 fluid_glass）：柔和投影 +
/// fluid 的 [DrawBackdrop] 效果链（vibrancy → blur → lens，与 Dock
/// 的 LiquidBottomTabs 同引擎同口径）+ spec 纱色 + 描边 + fluid
/// rim 高光，[child] 叠在玻璃之上。悬浮 Dock 回落路、[GlassFab] 与
/// miuix17 起的菜单/sheet/对话框/回复输入卡共用同一套参数，参数
/// 只此一份来源：有效 spec（预设 + 用户自定义滑杆值，见
/// [resolveDockGlassSpec]），再按本面的 [variant]/[sizeClass] 派生
/// 透镜收敛系数（[DockGlassSpec.adjustedForSurface]）。
///
/// 与旧自研引擎（BackdropFilter + dock_refraction.frag）的口径差：
/// - 采样源经 [fluidGlassBackdropOf] 解析：有录制注入（查看器
///   箭头）走真折射，其余走合成器 native 路径（模糊+纱色+rim，
///   无折射）；shader 不可用时一律 native，等价呈现保功能；
/// - 光学以 fluid 写死值为准：blur 半径 [fluidGlassBlurRadius]、
///   vibrancy 饱和 1.5——spec 的 sigma/saturate 不再有入口（与
///   Dock 组件版同一代价，miuix21 已随底栏转正接受）；spec 的
///   band/amount/dispersion 经 lens 进入（按面积档收敛后的值），
///   tint/highlight/border 三个颜色分量经 [dockGlassColorsForSpec]
///   与描边/rim 进入；
/// - 旧版的顶部渐变高光带换成 fluid 的 rim 高光（强度仍由 spec 的
///   highlightAlpha 驱动）；[highlightHeight] 只保留作 rim 的开关
///   （>0 开），高度语义在新引擎无对应。
/// 未传覆写时读设置盒并监听，改动即时全局生效。按苹果规范，
/// 玻璃面上不要再套一层玻璃（子元素用填充/透明度表现）。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.borderRadius,
    required this.child,
    this.materialOverride,
    this.specOverride,
    this.variant = GlassVariant.regular,
    this.sizeClass = GlassSizeClass.small,
    this.highlightHeight = 16,
  });

  final BorderRadius borderRadius;
  final Widget child;

  /// 测试/预览覆写材质（直接用该预设的数值，忽略自定义参数）；
  /// 为空时读设置盒的有效 spec 并监听变化。
  final DockGlassMaterial? materialOverride;

  /// 测试/预览直接覆写有效 spec（优先于 [materialOverride]）。
  final DockGlassSpec? specOverride;

  /// 玻璃变体：regular 默认；clear 只给媒体之上的控制层用。
  final GlassVariant variant;

  /// 面积档，决定透镜收敛系数（small 为全量，底栏/FAB 用它）。
  final GlassSizeClass sizeClass;

  /// rim 高光开关（旧自研引擎里是顶部高光带高度，miuix22 起高度
  /// 语义无对应，仅 >0 时启用 fluid rim 高光）。
  final double highlightHeight;

  @override
  Widget build(BuildContext context) {
    final specOverride = this.specOverride;
    if (specOverride != null) return _buildSurface(context, specOverride);
    final override = materialOverride;
    if (override != null) return _buildSurface(context, override.spec);
    final listenable = dockGlassSettingsListenable();
    if (listenable == null) {
      return _buildSurface(context, currentDockGlassSpec());
    }
    return ValueListenableBuilder(
      valueListenable: listenable,
      builder: (context, _, __) =>
          _buildSurface(context, currentDockGlassSpec()),
    );
  }

  Widget _buildSurface(BuildContext context, DockGlassSpec rawSpec) {
    final spec =
        rawSpec.adjustedForSurface(variant: variant, sizeClass: sizeClass);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // 颜色统一走唯一映射点：container=纱色（onDrawSurface 铺）、
    // 其余字段供子树里的 fluid 组件（与 Dock 同一份调色）。
    final colors = dockGlassColorsForSpec(spec,
        dark: dark, accent: theme.colorScheme.primary);
    final shape =
        glassShapeForBorderRadius(borderRadius, Directionality.of(context));
    final borderColor = glassBorderColor(spec, dark);
    final highlightAlpha = glassHighlightAlpha(spec, dark);
    return LiquidGlassTheme(
      colors: colors,
      child: DrawBackdrop(
        backdrop: fluidGlassBackdropOf(context),
        shape: () => shape,
        effects: (scope) => scope
          ..vibrancy()
          ..blur(fluidGlassBlurRadius)
          ..lens(
            spec.refractionBandDp,
            spec.refractionAmountDp,
            chromaticAberration: spec.dispersion > 0,
          ),
        highlight: highlightHeight > 0
            ? () => Highlight.standard.copyWith(alpha: highlightAlpha)
            : null,
        shadow: () => GlassShadow(
          radius: 18,
          offset: const Offset(0, 6),
          color: Colors.black.withValues(alpha: dark ? 0.35 : 0.18),
        ),
        // 底部内阴影：给玻璃补厚度感（旧 shader innerShadow 0.3 的
        // 等效近似——fluid 的内阴影是整圈向内的柔影，强度克制）。
        innerShadow: () => GlassInnerShadow(
          radius: 24,
          offset: const Offset(0, 24),
          color: const Color(0x26000000),
          alpha: 0.3,
        ),
        // onDrawSurface 只铺一层纯色纱（srcOver），不需要隔离层。
        isolateSurface: false,
        onDrawSurface: (canvas, size) {
          canvas.drawRect(
              Offset.zero & size, Paint()..color = colors.container);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: borderColor),
          ),
          // 描边的内容内缩：旧自研面里描边由 Container 的
          // decoration.padding 承担（四边各 1dp），菜单定宽等布局
          // 契约按这个几何校准——新面用等量 Padding 补回，保证
          // 所有面的总尺寸与内容位置与旧引擎逐值一致。
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 玻璃悬浮按钮：与悬浮 Dock 同一套玻璃材质（跟随设置切换与自定义
/// 参数），替代各页的 FloatingActionButton。形状保持原有形态——默认
/// 与 FAB 相同的 16dp 圆角方形，[circular] 时为正圆；尺寸默认与 FAB
/// 相同的 56dp。[onPressed] 为空时呈禁用态（图标变淡、无点击）。
/// 按苹果 Liquid Glass 的交互规范，可交互玻璃被按下时有轻微缩放
/// 反馈（0.94，150ms），miuix17 起补上（仅视觉，不改回调语义）。
class GlassFab extends StatefulWidget {
  const GlassFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.size = 56,
    this.circular = false,
    this.iconSize = 24,
    this.materialOverride,
    this.variant = GlassVariant.regular,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String? tooltip;
  final double size;
  final bool circular;
  final double iconSize;

  /// 测试/预览覆写材质；为空时跟随设置。
  final DockGlassMaterial? materialOverride;

  /// 玻璃变体：浮在媒体内容上时（如图片查看器翻页箭头）用 clear。
  final GlassVariant variant;

  @override
  State<GlassFab> createState() => _GlassFabState();
}

class _GlassFabState extends State<GlassFab> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final borderRadius = widget.circular
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(16);
    final enabled = widget.onPressed != null;
    final baseColor = glassIconColor(context);
    final button = SizedBox(
      width: size,
      height: size,
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: AppAnim.fast,
          curve: AppAnim.enterCurve,
          child: GlassSurface(
            borderRadius: borderRadius,
            materialOverride: widget.materialOverride,
            variant: widget.variant,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onPressed,
                customBorder: widget.circular
                    ? const CircleBorder()
                    : RoundedRectangleBorder(borderRadius: borderRadius),
                // 图标盒撑满按钮面：否则 InkWell 只缩在图标大小、点不中。
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    widget.icon,
                    size: widget.iconSize,
                    color:
                        enabled ? baseColor : baseColor.withValues(alpha: 0.38),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final message = widget.tooltip;
    return message == null ? button : Tooltip(message: message, child: button);
  }
}
