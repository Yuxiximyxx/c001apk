import 'dart:ui' as ui show FragmentProgram;

import 'package:flutter/material.dart';

import 'glass_surface.dart';

export 'glass_surface.dart';

/// 窄幅悬浮 Dock 底栏（miuix13，用户看图拍板的规格，见
/// preview/dockfx/cool_dock2.png）：宽约屏幕 58%、水平居中、高 68dp 的
/// 大圆角胶囊，悬于内容之上，内容从栏下滚过。选中项为椭圆高亮内竖排
/// 「图标在上、文字在下」（强调蓝），未选中项只有图标。高亮在两项之间
/// 滑动过渡（250ms）。玻璃层与全应用悬浮按钮共用 [GlassSurface]（材质
/// 三档可切换，设置项「玻璃材质」，默认磨砂，参数按 Kyant 配方校准，
/// 见 glass_surface.dart）；液态档下选中药丸本身也是一块透镜（独立
/// BackdropFilter 走同一条玻璃链），与 Kyant LiquidBottomTabs 一致。
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

class _FloatingDockBarState extends State<FloatingDockBar> {
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
    if (override != null) return _buildBar(context, override);
    final listenable = dockGlassMaterialListenable();
    if (listenable == null) {
      return _buildBar(context, currentDockGlassMaterial());
    }
    return ValueListenableBuilder(
      valueListenable: listenable,
      builder: (context, _, __) => _buildBar(context, currentDockGlassMaterial()),
    );
  }

  Widget _buildBar(BuildContext context, DockGlassMaterial material) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final viewBottom = MediaQuery.viewPaddingOf(context).bottom;
    // 悬在系统手势区上方：下边距约为手势区高度的 3/4（无手势区时 10dp）。
    final bottomMargin = viewBottom >= 16 ? viewBottom * 0.75 : 10.0;
    final pillColor = dark
        ? Colors.black.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.10);
    final unselectedColor = glassIconColor(context);

    return SizedBox(
      height: FloatingDockBar.height + bottomMargin,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: screenWidth * FloatingDockBar.widthFactor,
          height: FloatingDockBar.height,
          child: GlassSurface(
            key: const Key('floatingDockCapsule'),
            borderRadius:
                BorderRadius.circular(FloatingDockBar.height / 2),
            materialOverride: material,
            child: Material(
              type: MaterialType.transparency,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
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
                      child: _SelectionPill(
                        material: material,
                        color: pillColor,
                        refractionProgram: _refractionProgram,
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0;
                            i < FloatingDockBar.labels.length;
                            i++)
                          Expanded(
                            child: InkWell(
                              onTap: () => widget.onDestinationSelected(i),
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
    );
  }
}

/// Dock 的选中药丸：普通材质下是半透深色椭圆；液态材质下本身是一块
/// 透镜——独立 BackdropFilter 采样其下方的 Dock 玻璃与页面内容，走与
/// Dock 相同的玻璃链（饱和→模糊→SDF 折射），再覆原药丸色。
class _SelectionPill extends StatelessWidget {
  const _SelectionPill({
    required this.material,
    required this.color,
    required this.refractionProgram,
  });

  final DockGlassMaterial material;
  final Color color;
  final ui.FragmentProgram? refractionProgram;

  static const double _radius =
      (FloatingDockBar.height - FloatingDockBar._pillInset * 2) / 2;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(_radius);
    final program = refractionProgram;
    if (material != DockGlassMaterial.liquid || program == null) {
      return DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: borderRadius),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (context, constraints) => BackdropFilter(
          filter: glassImageFilter(
            spec: material.spec,
            size: Size(constraints.maxWidth, constraints.maxHeight),
            dpr: dpr,
            refractionProgram: program,
          ),
          child: DecoratedBox(decoration: BoxDecoration(color: color)),
        ),
      ),
    );
  }
}
