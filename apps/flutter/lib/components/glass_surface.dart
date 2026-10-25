import 'dart:ui' as ui
    show
        Canvas,
        ColorFilter,
        FragmentProgram,
        ImageFilter,
        Paint,
        PictureRecorder;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/storage_util.dart';

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

  static DockGlassMaterial fromStorage(Object? value) => value is int &&
          value >= 0 &&
          value < values.length
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
}

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
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
      0, 0, 0, 1, 0,
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

/// 折射 shader 的一次性加载+能力探测：ImageFilter.shader 仅 Impeller
/// 可用，Skia 后端（测试环境、无 Vulkan 的老设备回退）在绘制时会抛
/// UnsupportedError 且无法在使用点 catch，所以先用 2x2 离屏绘制探一遍，
/// 不可用就返回 null，三档一律退回无透镜的滤镜链（饱和+模糊不变）。
/// 全应用共享同一次加载。
class RefractionSupport {
  static Future<ui.FragmentProgram?>? _future;

  static Future<ui.FragmentProgram?> load() => _future ??= _load();

  static Future<ui.FragmentProgram?> _load() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
          'assets/shaders/dock_refraction.frag');
      final shader = program.fragmentShader()
        ..setFloat(0, 2)
        ..setFloat(1, 2)
        ..setFloat(2, 2)
        ..setFloat(3, 2)
        ..setFloat(4, 0.2)
        ..setFloat(5, 0.5)
        ..setFloat(6, 0.3);
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
      return program;
    } catch (_) {
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

/// 玻璃滤镜链（Kyant 顺序）：饱和提升（vibrancy）→ 模糊打底 →
/// （shader 可用时）circleMap 剖面透镜折射。miuix16 起三档底栏本体
/// 都走透镜（量按档拉开）；折射带宽/量、色散强度可覆写（Dock 药丸
/// 透镜按 pressProgress 驱动，见 floating_dock_bar.dart），不传时用
/// spec 的档位值。[rimStrength] 为 shader 边缘镜面高光强度、
/// [innerShadow] 为底部内阴影强度（0=关）。
ui.ImageFilter glassImageFilter({
  required DockGlassSpec spec,
  required Size size,
  required double dpr,
  required ui.FragmentProgram? refractionProgram,
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
    final shader = program.fragmentShader()
      ..setFloat(0, size.width * dpr)
      ..setFloat(1, size.height * dpr)
      ..setFloat(2, band * dpr)
      ..setFloat(3, amount * dpr)
      ..setFloat(4, dispersion ?? spec.dispersion)
      ..setFloat(5, rimStrength)
      ..setFloat(6, innerShadow);
    filter = ui.ImageFilter.compose(
        outer: ui.ImageFilter.shader(shader), inner: filter);
  }
  return filter;
}

/// 共享玻璃面：柔和投影 + 真毛玻璃（BackdropFilter 模糊/折射/饱和）+
/// 乳纱 + 描边 + 顶缘 inset 高光，[child] 叠在玻璃之上。悬浮 Dock 与
/// [GlassFab] 共用同一套参数与滤镜链，材质只此一份来源：未传
/// [materialOverride] 时读设置盒并监听，切换即时全局生效。
class GlassSurface extends StatefulWidget {
  const GlassSurface({
    super.key,
    required this.borderRadius,
    required this.child,
    this.materialOverride,
    this.highlightHeight = 16,
  });

  final BorderRadius borderRadius;
  final Widget child;

  /// 测试/预览覆写材质；为空时读设置盒并监听变化。
  final DockGlassMaterial? materialOverride;

  /// 顶部高光带的高度（自顶缘向下渐隐）。
  final double highlightHeight;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  ui.FragmentProgram? _refractionProgram;

  @override
  void initState() {
    super.initState();
    RefractionSupport.load().then((program) {
      if (mounted && program != null) {
        setState(() => _refractionProgram = program);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final override = widget.materialOverride;
    if (override != null) return _buildSurface(context, override);
    final listenable = dockGlassMaterialListenable();
    if (listenable == null) {
      return _buildSurface(context, currentDockGlassMaterial());
    }
    return ValueListenableBuilder(
      valueListenable: listenable,
      builder: (context, _, __) =>
          _buildSurface(context, currentDockGlassMaterial()),
    );
  }

  Widget _buildSurface(BuildContext context, DockGlassMaterial material) {
    final spec = material.spec;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: LayoutBuilder(
          builder: (context, constraints) => BackdropFilter(
            filter: glassImageFilter(
              spec: spec,
              size: Size(constraints.maxWidth, constraints.maxHeight),
              dpr: dpr,
              refractionProgram: _refractionProgram,
              // shader 端边缘镜面光（rim）跟随本档高光身份强度、
              // 底部内阴影固定克制值——给玻璃补轮廓光与厚度感。
              rimStrength: glassHighlightAlpha(spec, dark),
              innerShadow: 0.3,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: glassTintColor(spec, dark),
                borderRadius: widget.borderRadius,
                border: Border.all(color: glassBorderColor(spec, dark)),
              ),
              child: Stack(
                children: [
                  // 顶缘 inset 高光：顶部 1px 起的渐变亮线。
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: widget.highlightHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(
                                alpha: glassHighlightAlpha(spec, dark)),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  widget.child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃悬浮按钮：与悬浮 Dock 同一套玻璃材质（跟随设置切换），替代各页
/// 的 FloatingActionButton。形状保持原有形态——默认与 FAB 相同的
/// 16dp 圆角方形，[circular] 时为正圆；尺寸默认与 FAB 相同的 56dp。
/// [onPressed] 为空时呈禁用态（图标变淡、无点击）。
class GlassFab extends StatelessWidget {
  const GlassFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.size = 56,
    this.circular = false,
    this.iconSize = 24,
    this.materialOverride,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String? tooltip;
  final double size;
  final bool circular;
  final double iconSize;

  /// 测试/预览覆写材质；为空时跟随设置。
  final DockGlassMaterial? materialOverride;

  @override
  Widget build(BuildContext context) {
    final borderRadius =
        circular ? BorderRadius.circular(size / 2) : BorderRadius.circular(16);
    final enabled = onPressed != null;
    final baseColor = glassIconColor(context);
    final button = SizedBox(
      width: size,
      height: size,
      child: GlassSurface(
        borderRadius: borderRadius,
        materialOverride: materialOverride,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            customBorder: circular
                ? const CircleBorder()
                : RoundedRectangleBorder(borderRadius: borderRadius),
            // 图标盒撑满按钮面：否则 InkWell 只缩在图标大小、点不中。
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: iconSize,
                color: enabled
                    ? baseColor
                    : baseColor.withValues(alpha: 0.38),
              ),
            ),
          ),
        ),
      ),
    );
    final message = tooltip;
    return message == null
        ? button
        : Tooltip(message: message, child: button);
  }
}
