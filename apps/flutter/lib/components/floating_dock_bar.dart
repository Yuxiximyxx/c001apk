import 'dart:ui' as ui
    show
        Canvas,
        ColorFilter,
        FragmentProgram,
        ImageFilter,
        Paint,
        PictureRecorder;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/storage_util.dart';

/// 底栏玻璃材质（设置项「底栏玻璃材质」，以 int 索引存设置盒）。
enum DockGlassMaterial {
  /// 毛玻璃：中模糊 + 薄纱 + 明显高光 + 饱和 1.6。
  clear,

  /// 磨砂玻璃（默认，已确认效果图的质感）：大模糊 + 厚乳纱 + 弱高光。
  frosted,

  /// 液态玻璃：小模糊 + 极薄纱 + 边缘折射 shader + 强边缘高光。
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
            sigma: 14,
            saturate: 1.6,
            tintAlphaDark: 0.16,
            tintAlphaLight: 0.38,
            highlightAlphaDark: 0.45,
            highlightAlphaLight: 0.80,
            borderAlphaDark: 0.30,
            borderAlphaLight: 0.55,
            refraction: false,
          ),
        DockGlassMaterial.frosted => const DockGlassSpec(
            sigma: 22,
            saturate: 1.5,
            tintAlphaDark: 0.30,
            tintAlphaLight: 0.62,
            highlightAlphaDark: 0.18,
            highlightAlphaLight: 0.45,
            borderAlphaDark: 0.30,
            borderAlphaLight: 0.55,
            refraction: false,
          ),
        DockGlassMaterial.liquid => const DockGlassSpec(
            sigma: 3,
            saturate: 1.4,
            tintAlphaDark: 0.08,
            tintAlphaLight: 0.18,
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

/// 窄幅悬浮 Dock 底栏（miuix13，用户看图拍板的规格，见
/// preview/dockfx/cool_dock2.png）：宽约屏幕 58%、水平居中、高 68dp 的
/// 大圆角胶囊，悬于内容之上，内容从栏下滚过。选中项为椭圆高亮内竖排
/// 「图标在上、文字在下」（强调蓝），未选中项只有图标。高亮在两项之间
/// 滑动过渡（250ms）。玻璃材质三档可切换（设置项，默认磨砂），只换玻璃
/// 层参数，几何与选中样式不变；液态档的折射由 fragment shader
/// （assets/shaders/dock_refraction.frag）对 backdrop 做边缘位移，shader
/// 加载完成前先用「低模糊+高饱和+强高光」近似渲染。
class FloatingDockBar extends StatefulWidget {
  const FloatingDockBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.materialOverride,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// 测试/预览覆写材质；为空时读设置盒并监听变化（即时生效）。
  final DockGlassMaterial? materialOverride;

  static const double widthFactor = 0.58;
  static const double height = 68;
  static const double _pillInset = 6;

  static const labels = ['首页', '我的'];
  static const _icons = [Icons.home_outlined, Icons.person_outline];
  static const _selectedIcons = [Icons.home, Icons.person];

  @override
  State<FloatingDockBar> createState() => _FloatingDockBarState();
}

/// 折射 shader 的一次性加载+能力探测：ImageFilter.shader 仅 Impeller
/// 可用，Skia 后端（测试环境、无 Vulkan 的老设备回退）在绘制时会抛
/// UnsupportedError 且无法在使用点 catch，所以先用 2x2 离屏绘制探一遍，
/// 不可用就返回 null，液态档走近似参数（低模糊+高饱和+强高光）。
class _RefractionSupport {
  static Future<ui.FragmentProgram?>? _future;

  static Future<ui.FragmentProgram?> load() => _future ??= _load();

  static Future<ui.FragmentProgram?> _load() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
          'assets/shaders/dock_refraction.frag');
      final shader = program.fragmentShader()
        ..setFloat(0, 2)
        ..setFloat(1, 2)
        ..setFloat(2, 0.012);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()
        ..imageFilter = ui.ImageFilter.shader(shader);
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

class _FloatingDockBarState extends State<FloatingDockBar> {
  ui.FragmentProgram? _refractionProgram;

  @override
  void initState() {
    super.initState();
    _RefractionSupport.load().then((program) {
      if (mounted && program != null) {
        setState(() => _refractionProgram = program);
      }
    });
  }

  DockGlassMaterial get _storedMaterial {
    try {
      return DockGlassMaterial.fromStorage(
          GStorage.settings.get(SettingsBoxKey.dockGlassMaterial));
    } catch (_) {
      return DockGlassMaterial.frosted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final override = widget.materialOverride;
    if (override != null) return _buildDock(context, override);
    return ValueListenableBuilder(
      valueListenable: GStorage.settings
          .listenable(keys: [SettingsBoxKey.dockGlassMaterial]),
      builder: (context, _, __) => _buildDock(context, _storedMaterial),
    );
  }

  ui.ImageFilter _glassFilter(DockGlassSpec spec, Size size, double dpr) {
    ui.ImageFilter filter =
        ui.ImageFilter.blur(sigmaX: spec.sigma, sigmaY: spec.sigma);
    final program = _refractionProgram;
    if (spec.refraction && program != null) {
      final shader = program.fragmentShader()
        ..setFloat(0, size.width * dpr)
        ..setFloat(1, size.height * dpr)
        ..setFloat(2, 0.012);
      filter = ui.ImageFilter.compose(
          outer: ui.ImageFilter.shader(shader), inner: filter);
    }
    return ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix(dockSaturationMatrix(spec.saturate)),
      inner: filter,
    );
  }

  Widget _buildDock(BuildContext context, DockGlassMaterial material) {
    final spec = material.spec;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final viewBottom = MediaQuery.viewPaddingOf(context).bottom;
    // 悬在系统手势区上方：下边距约为手势区高度的 3/4（无手势区时 10dp）。
    final bottomMargin = viewBottom >= 16 ? viewBottom * 0.75 : 10.0;

    final tint = dark
        ? const Color(0xFFEDEEF2).withValues(alpha: spec.tintAlphaDark)
        : Colors.white.withValues(alpha: spec.tintAlphaLight);
    final pillColor = dark
        ? Colors.black.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.10);
    final unselectedColor =
        dark ? Colors.white.withValues(alpha: 0.95) : const Color(0xFF3F4145);
    final borderColor = dark
        ? Colors.white.withValues(alpha: spec.borderAlphaDark)
        : Colors.white.withValues(alpha: spec.borderAlphaLight);
    final highlightAlpha =
        dark ? spec.highlightAlphaDark : spec.highlightAlphaLight;

    return SizedBox(
      height: FloatingDockBar.height + bottomMargin,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          key: const Key('floatingDockCapsule'),
          width: screenWidth * FloatingDockBar.widthFactor,
          height: FloatingDockBar.height,
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(FloatingDockBar.height / 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.35 : 0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(FloatingDockBar.height / 2),
            child: LayoutBuilder(
              builder: (context, constraints) => BackdropFilter(
                filter: _glassFilter(
                    spec,
                    Size(constraints.maxWidth, constraints.maxHeight),
                    dpr),
                child: Container(
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius:
                        BorderRadius.circular(FloatingDockBar.height / 2),
                    border: Border.all(color: borderColor),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Stack(
                      children: [
                        // 顶缘 inset 高光：顶部 1px 起的渐变亮线。
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 16,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: highlightAlpha),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          left: FloatingDockBar._pillInset +
                              widget.selectedIndex *
                                  (constraints.maxWidth /
                                      FloatingDockBar.labels.length),
                          top: FloatingDockBar._pillInset,
                          width: constraints.maxWidth /
                                  FloatingDockBar.labels.length -
                              FloatingDockBar._pillInset * 2,
                          height: FloatingDockBar.height -
                              FloatingDockBar._pillInset * 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: pillColor,
                              borderRadius: BorderRadius.circular(
                                  (FloatingDockBar.height -
                                          FloatingDockBar._pillInset * 2) /
                                      2),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0;
                                i < FloatingDockBar.labels.length;
                                i++)
                              Expanded(
                                child: InkWell(
                                  onTap: () =>
                                      widget.onDestinationSelected(i),
                                  child: Center(
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      child: i == widget.selectedIndex
                                          ? Column(
                                              key: ValueKey('dock$i'),
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                    FloatingDockBar
                                                        ._selectedIcons[i],
                                                    size: 22,
                                                    color: accent),
                                                const SizedBox(height: 1),
                                                Text(
                                                  FloatingDockBar.labels[i],
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    height: 1,
                                                    color: accent,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Icon(FloatingDockBar._icons[i],
                                              key: ValueKey('dock$i'),
                                              size: 24,
                                              color: unselectedColor),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
