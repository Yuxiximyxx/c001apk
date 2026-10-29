import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../constants/liquid_glass_level.dart';
import 'app_anim.dart';
import 'glass_surface.dart' hide GlassSurface;

/// 顶栏玻璃的采样作用域（miuix24）：顶栏与 Dock 同构的关键——页面
/// 正文由 [LiquidTopBarScaffold] 包进 fluid 的 BackdropLayer 录制，
/// 顶栏（Scaffold 的 appBar 槽，位于录制子树之外）经本作用域拿到
/// 同一条 LayerBackdrop 采样链，于是顶栏与底栏一样是真折射，而不是
/// nativeBackdrop 的 plain 路径（合成器高斯模糊、无折射、rim 钉平）。
/// 只有 appBar 槽被包进本作用域；正文内部的玻璃面（资料卡等）仍走
/// 原解析，避免消费者在被录子树内自采样的反馈。
class TopBarGlassScope extends InheritedWidget {
  const TopBarGlassScope({
    super.key,
    required this.backdrop,
    required super.child,
  });

  final Backdrop backdrop;

  static Backdrop? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TopBarGlassScope>()
      ?.backdrop;

  @override
  bool updateShouldNotify(TopBarGlassScope oldWidget) =>
      !identical(backdrop, oldWidget.backdrop);
}

/// Public backend: ordinary translucent/frosted surfaces and navigation.
/// The official source assembly supplies the same API with its own renderer.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.shader,
    required this.enabled,
    required this.extent,
    required this.depth,
    required this.dispersion,
    required this.tint,
    this.refractionHeight = 0,
    this.depthEffect = false,
    this.blur = 4,
    this.fallbackTint,
    this.level = LiquidGlassLevel.medium,
    this.press = 0,
    this.borderRadius,
    this.shadow = true,
  });

  factory GlassSurface.navigationBase({
    required ui.FragmentShader? shader,
    required bool enabled,
    required Size extent,
    required ThemeData theme,
    required LiquidGlassLevel level,
    bool shadow = true,
    double press = 0,
  }) =>
      GlassSurface(
          shader: shader,
          enabled: enabled,
          extent: extent,
          depth: 0,
          dispersion: 0,
          tint: theme.colorScheme.surfaceContainer,
          level: level,
          shadow: shadow,
          press: press);

  factory GlassSurface.navigationLens({
    required ui.FragmentShader? shader,
    required bool enabled,
    required Size extent,
    required ThemeData theme,
    required LiquidGlassLevel level,
    required double progress,
    bool shadow = true,
    Color? tint,
  }) =>
      GlassSurface(
          shader: shader,
          enabled: enabled,
          extent: extent,
          depth: 0,
          dispersion: 0,
          tint: tint ?? theme.colorScheme.primaryContainer,
          level: level,
          depthEffect: true,
          shadow: shadow,
          press: progress);

  final ui.FragmentShader? shader;
  final bool enabled, depthEffect, shadow;
  final Size extent;
  final double depth, dispersion, refractionHeight, blur, press;
  final Color tint;
  final Color? fallbackTint;
  final LiquidGlassLevel level;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(extent.height / 2);
    final solid = !enabled || MediaQuery.highContrastOf(context);
    if (solid) {
      return ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: (fallbackTint ?? tint).withValues(alpha: 1),
          child: const SizedBox.expand(),
        ),
      );
    }
    // miuix23：出图换 fork 定版 fluid_glass 引擎（换引擎不换壳）——
    // 本类的公开 API、调用点的布局与交互全部保留，只把 basic 的
    // 「半透明色 + 4px 高斯模糊」换成与悬浮 Dock 同一套 fluid
    // DrawBackdrop 链：采样经 fluidGlassBackdropOf 统一解析，纱色用
    // 调用方 tint（alpha 按旧 basic 口径 .9），光学走当前玻璃材质
    // spec（blur 8 / vibrancy 1.5 / lens 按 spec)，level == low 时
    // 只模糊不折射（对应旧 basic 在 low 下不启用的行为）。
    // spec 变化经 dockGlassSettingsListenable 监听即时生效，与
    // fork GlassSurface 同口径。
    final listenable = dockGlassSettingsListenable();
    if (listenable == null) return _buildFluid(context, radius);
    return ValueListenableBuilder(
      valueListenable: listenable,
      builder: (context, _, __) => _buildFluid(context, radius),
    );
  }

  Widget _buildFluid(BuildContext context, BorderRadius radius) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final spec = currentDockGlassSpec();
    // miuix24 根因修复：miuix23 在这里把纱色覆写成调用方 tint
    // （surfaceContainer 不透灰）× α.9——玻璃面被一层近不透的灰盖死，
    // 只剩平灰、毫无底栏的通透感。改与底栏同源：底面一律走 spec 纱
    // （glassTintColor，与 Dock 的 LiquidBottomTabs 同一映射点同一
    // 数值）；透镜面（选中药丸）保留其身份色但降到 α.55 半透，让
    // 采样内容透出来。tint 参数自此只对透镜面有意义。
    final container = depthEffect
        ? tint.withValues(alpha: .55)
        : glassTintColor(spec, dark);
    final colors = dockGlassColorsForSpec(spec,
            dark: dark, accent: theme.colorScheme.primary)
        .copyWith(container: container);
    final shape =
        glassShapeForBorderRadius(radius, Directionality.of(context));
    final low = level == LiquidGlassLevel.low;
    // 大面（资料卡 panel 等）透镜按面积收敛，与 fork GlassSurface 的
    // large 档同口径（band ×0.35 封顶 14、amount ×0.35），避免整面
    // 内容被强折射弯得没法读；小面（顶栏胶囊/药丸/圆球）全量。
    final largeSurface = extent.height > 72;
    final band = largeSurface
        ? math.min(spec.refractionBandDp * 0.35, 14.0)
        : spec.refractionBandDp;
    final amount = largeSurface
        ? spec.refractionAmountDp * 0.35
        : spec.refractionAmountDp;
    // 采样解析：顶栏作用域在场且 shader 可用时走正文录制（真折射，
    // 与 Dock 同构）；其余走既有统一解析（合成器 plain 路径）。
    final scopedBackdrop = TopBarGlassScope.maybeOf(context);
    final backdrop = scopedBackdrop != null && isRuntimeShaderSupported()
        ? scopedBackdrop
        : fluidGlassBackdropOf(context);
    return LiquidGlassTheme(
      colors: colors,
      child: DrawBackdrop(
        backdrop: backdrop,
        shape: () => shape,
        effects: (scope) => low
            ? (scope
              ..vibrancy()
              ..blur(fluidGlassBlurRadius))
            : (scope
              ..vibrancy()
              ..blur(fluidGlassBlurRadius)
              ..lens(
                band,
                amount,
                chromaticAberration: spec.dispersion > 0,
              )),
        highlight: () => Highlight.standard
            .copyWith(alpha: glassHighlightAlpha(spec, dark)),
        shadow: shadow
            ? () => GlassShadow(
                  radius: 18,
                  offset: const Offset(0, 6),
                  color: Colors.black.withValues(alpha: dark ? 0.35 : 0.18),
                )
            : null,
        innerShadow: () => GlassInnerShadow(
          radius: 24,
          offset: const Offset(0, 24),
          color: const Color(0x26000000),
          alpha: 0.3,
        ),
        isolateSurface: false,
        onDrawSurface: (canvas, size) {
          canvas.drawRect(
              Offset.zero & size, Paint()..color = colors.container);
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}

class LiquidGlassPanel extends StatelessWidget {
  const LiquidGlassPanel(
      {super.key,
      required this.child,
      required this.enabled,
      required this.level,
      this.borderRadius = const BorderRadius.all(Radius.circular(28))});
  final Widget child;
  final bool enabled;
  final LiquidGlassLevel level;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: borderRadius,
      child: Stack(children: [
        Positioned.fill(
            child: IgnorePointer(
                child: LayoutBuilder(
                    builder: (context, bounds) => GlassSurface(
                        shader: null,
                        enabled: enabled,
                        extent: bounds.biggest,
                        depth: 0,
                        dispersion: 0,
                        tint: Theme.of(context).colorScheme.surfaceContainer,
                        level: level,
                        borderRadius: borderRadius)))),
        child,
      ]));
}

class LiquidGlassButton extends StatelessWidget {
  const LiquidGlassButton(
      {super.key,
      required this.child,
      required this.height,
      required this.level,
      required this.onPressed,
      required this.tooltip,
      this.width,
      this.enabled = true});
  final Widget child;
  final double height;
  final double? width;
  final LiquidGlassLevel level;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: width,
      height: height,
      child: Stack(fit: StackFit.expand, children: [
        IgnorePointer(
            child: GlassSurface.navigationBase(
                shader: null,
                enabled: enabled,
                extent: Size(width ?? height, height),
                theme: Theme.of(context),
                level: level,
                shadow: false)),
        Tooltip(
            message: tooltip,
            child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                    onTap: onPressed,
                    borderRadius: BorderRadius.circular(height / 2),
                    child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Center(child: child))))),
      ]));
}

class LiquidNavigationBar extends StatefulWidget {
  const LiquidNavigationBar(
      {super.key,
      required this.selectedIndex,
      required this.onDestinationSelected,
      this.program,
      this.refract = true,
      this.level = LiquidGlassLevel.medium})
      : labels = const ['主页', '关注', '我的'],
        tabs = false;
  const LiquidNavigationBar.tabs(
      {super.key,
      required this.selectedIndex,
      required this.onDestinationSelected,
      required this.labels,
      this.program,
      this.refract = true,
      this.level = LiquidGlassLevel.medium})
      : tabs = true;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final ui.FragmentProgram? program;
  final bool refract, tabs;
  final LiquidGlassLevel level;
  final List<String> labels;

  @override
  State<LiquidNavigationBar> createState() => _BasicNavigationState();
}

class _BasicNavigationState extends State<LiquidNavigationBar> {
  int? _dragIndex;

  /// 药丸的连续位置（槽索引单位，miuix24）：拖动时药丸中心跟随
  /// 指针、按槽位换算成小数位置；松手后清掉，药丸由 AnimatedPositioned
  /// 以 [AppAnim] 曲线吸附到目标槽。点击仍走各标签自身的点按。
  double? _dragPosition;

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      bottom: !widget.tabs,
      minimum: widget.tabs
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: widget.tabs ? double.infinity : 248),
              child: LayoutBuilder(builder: (context, bounds) {
                if (widget.labels.isEmpty || bounds.maxWidth <= 0) {
                  return const SizedBox.shrink();
                }
                final theme = Theme.of(context);
                final textHeight = MediaQuery.textScalerOf(context).scale(14);
                final height = widget.tabs
                    ? math.max(48.0, textHeight + 24)
                    : math.max(64.0, textHeight + 40);
                final count = widget.labels.length;
                final slotWidth = bounds.maxWidth / count;
                final selected = (_dragIndex ?? widget.selectedIndex)
                    .clamp(0, count - 1);
                void drag(Offset point) => setState(() {
                      _dragIndex = (point.dx / slotWidth)
                          .floor()
                          .clamp(0, count - 1);
                      _dragPosition = (point.dx / slotWidth - 0.5)
                          .clamp(0.0, (count - 1).toDouble());
                    });
                const pillInset = 4.0;
                final pillPosition =
                    _dragPosition ?? selected.toDouble();
                return _BasicRoundHitRegion(
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(height / 2),
                        child: GestureDetector(
                          key: ValueKey(widget.tabs
                              ? 'liquid-tabs-surface'
                              : 'liquid-drag-surface'),
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (event) =>
                              drag(event.localPosition),
                          onHorizontalDragUpdate: (event) =>
                              drag(event.localPosition),
                          onHorizontalDragCancel: () => setState(() {
                            _dragIndex = null;
                            _dragPosition = null;
                          }),
                          onHorizontalDragEnd: (_) {
                            final index = _dragIndex;
                            setState(() {
                              _dragIndex = null;
                              _dragPosition = null;
                            });
                            if (index != null) {
                              widget.onDestinationSelected(index);
                            }
                          },
                          child: SizedBox(
                              height: height,
                              child: Stack(children: [
                                Positioned.fill(
                                    child: IgnorePointer(
                                        child: GlassSurface.navigationBase(
                                            shader: null,
                                            enabled: widget.refract,
                                            extent:
                                                Size(bounds.maxWidth, height),
                                            theme: theme,
                                            level: widget.level,
                                            shadow: false))),
                                // 选中药丸（miuix24）：独立玻璃透镜层，
                                // 不再是 TextButton 的平色块背景；拖动时
                                // 跟随指针（duration 0），其余时候以统一
                                // 曲线滑动吸附到选中槽。
                                AnimatedPositioned(
                                  duration: _dragPosition != null ||
                                          MediaQuery.disableAnimationsOf(
                                              context)
                                      ? Duration.zero
                                      : AppAnim.standard,
                                  curve: AppAnim.enterCurve,
                                  left: pillPosition * slotWidth + pillInset,
                                  top: pillInset,
                                  bottom: pillInset,
                                  width: slotWidth - pillInset * 2,
                                  child: IgnorePointer(
                                      child: GlassSurface.navigationLens(
                                          shader: null,
                                          enabled: widget.refract,
                                          extent: Size(
                                              slotWidth - pillInset * 2,
                                              height - pillInset * 2),
                                          theme: theme,
                                          level: widget.level,
                                          progress: 0,
                                          shadow: false)),
                                ),
                                Row(
                                  children: [
                                    for (var i = 0;
                                        i < widget.labels.length;
                                        i++)
                                      Expanded(
                                          child: Semantics(
                                              label: widget.labels[i],
                                              excludeSemantics: true,
                                              selected: selected == i,
                                              button: true,
                                              inMutuallyExclusiveGroup: true,
                                              child: TextButton(
                                                  onPressed: () => widget
                                                      .onDestinationSelected(i),
                                                  style: TextButton.styleFrom(
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              horizontal: 2),
                                                      // 药丸已由独立玻璃
                                                      // 透镜层承担，按钮
                                                      // 本身不再画平色块。
                                                      backgroundColor:
                                                          Colors.transparent,
                                                      foregroundColor: selected == i
                                                          ? theme.colorScheme
                                                              .onPrimaryContainer
                                                          : theme.colorScheme
                                                              .onSurface),
                                                  child: widget.tabs
                                                      ? FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                              widget.labels[i],
                                                              maxLines: 1))
                                                      : Column(mainAxisSize: MainAxisSize.min, children: [
                                                          Icon([
                                                            Icons.home_outlined,
                                                            Icons.feed_outlined,
                                                            Icons.person_outline
                                                          ][i % 3]),
                                                          Text(widget.labels[i],
                                                              maxLines: 1),
                                                        ]))))
                                  ],
                                ),
                              ])),
                        )));
              }))));
}

class _BasicRoundHitRegion extends SingleChildRenderObjectWidget {
  const _BasicRoundHitRegion({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _BasicRoundHitBox();
}

class _BasicRoundHitBox extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      RRect.fromRectAndRadius(
              Offset.zero & size, Radius.circular(size.height / 2))
          .contains(position) &&
      super.hitTest(result, position: position);
}
