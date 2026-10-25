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
/// 三档参数按 Kyant0/AndroidLiquidGlass 的 LiquidBottomTabs 配方校准
/// （miuix14）：玻璃感主要来自饱和提升 + 透镜折射，模糊只是打底；
/// 纱走深色薄纱（深 #121212 / 浅 #FAFAFA），不再用乳白厚涂。
enum DockGlassMaterial {
  /// 毛玻璃：blur 12 + 薄纱 + 强高光 + 饱和 1.6。
  clear,

  /// 磨砂玻璃（默认）：blur 16 + 纱略厚于液态 + 弱高光 + 饱和 1.5。
  frosted,

  /// 液态玻璃：blur 8 + Kyant 原方薄纱 + SDF 透镜折射 + 饱和 1.45。
  liquid;

  static DockGlassMaterial fromStorage(Object? value) => value is int &&
          value >= 0 &&
          value < values.length
      ? values[value]
      : DockGlassMaterial.frosted;
}

/// 一种玻璃材质的完整参数。配方出处：liquid-glass-recipes（毛玻璃/磨砂
/// 玻璃/液态玻璃三档），已换算到 Flutter 的 BackdropFilter 参数。
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
    required this.refraction,
  });

  final double sigma;
  final double saturate;
  final double tintAlphaDark;
  final double tintAlphaLight;
  final double highlightAlphaDark;
  final double highlightAlphaLight;
  final double borderAlphaDark;
  final double borderAlphaLight;
  final bool refraction;
}

extension DockGlassMaterialSpec on DockGlassMaterial {
  DockGlassSpec get spec => switch (this) {
        DockGlassMaterial.clear => const DockGlassSpec(
            sigma: 12,
            saturate: 1.6,
            tintAlphaDark: 0.30,
            tintAlphaLight: 0.32,
            highlightAlphaDark: 0.45,
            highlightAlphaLight: 0.80,
            borderAlphaDark: 0.30,
            borderAlphaLight: 0.55,
            refraction: false,
          ),
        DockGlassMaterial.frosted => const DockGlassSpec(
            sigma: 16,
            saturate: 1.5,
            tintAlphaDark: 0.45,
            tintAlphaLight: 0.52,
            highlightAlphaDark: 0.18,
            highlightAlphaLight: 0.45,
            borderAlphaDark: 0.30,
            borderAlphaLight: 0.55,
            refraction: false,
          ),
        DockGlassMaterial.liquid => const DockGlassSpec(
            sigma: 8,
            saturate: 1.45,
            tintAlphaDark: 0.40,
            tintAlphaLight: 0.40,
            highlightAlphaDark: 0.50,
            highlightAlphaLight: 0.85,
            borderAlphaDark: 0.50,
            borderAlphaLight: 0.70,
            refraction: true,
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
/// 不可用就返回 null，液态档走近似参数（低模糊+高饱和+强高光）。
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
        ..setFloat(4, 1);
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

/// 液态透镜的折射带宽（dp，Kyant lens 的 refractionHeight）。
const double glassRefractionBandDp = 24;

/// 液态透镜的折射量（dp，Kyant lens 的 refractionAmount；shader 内
/// 位移剖面峰值取其 0.5 倍，见 dock_refraction.frag）。
const double glassRefractionAmountDp = 24;

/// 玻璃滤镜链（Kyant 顺序）：饱和提升（vibrancy）→ 模糊打底 →
/// （液态且 shader 可用时）SDF 透镜折射。折射带宽/量与色差开关可覆写
/// （miuix15 的 Dock 药丸透镜按 pressProgress 驱动带宽/量，见
/// floating_dock_bar.dart）；不传时用整栏的 Kyant 24/24dp 与色差开。
ui.ImageFilter glassImageFilter({
  required DockGlassSpec spec,
  required Size size,
  required double dpr,
  required ui.FragmentProgram? refractionProgram,
  double? blurSigma,
  double? refractionBandDp,
  double? refractionAmountDp,
  bool chromaticAberration = true,
}) {
  final sigma = blurSigma ?? spec.sigma;
  ui.ImageFilter filter =
      ui.ColorFilter.matrix(dockSaturationMatrix(spec.saturate));
  filter = ui.ImageFilter.compose(
    outer: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    inner: filter,
  );
  final program = refractionProgram;
  if (spec.refraction && program != null) {
    final shader = program.fragmentShader()
      ..setFloat(0, size.width * dpr)
      ..setFloat(1, size.height * dpr)
      ..setFloat(2, (refractionBandDp ?? glassRefractionBandDp) * dpr)
      ..setFloat(3, (refractionAmountDp ?? glassRefractionAmountDp) * dpr)
      ..setFloat(4, chromaticAberration ? 1 : 0);
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
