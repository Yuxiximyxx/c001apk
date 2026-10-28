import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../constants/liquid_glass_level.dart';
import 'glass_surface.dart' hide GlassSurface;

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
    final colors = dockGlassColorsForSpec(spec,
            dark: dark, accent: theme.colorScheme.primary)
        .copyWith(container: tint.withValues(alpha: .9));
    final shape =
        glassShapeForBorderRadius(radius, Directionality.of(context));
    final low = level == LiquidGlassLevel.low;
    return LiquidGlassTheme(
      colors: colors,
      child: DrawBackdrop(
        backdrop: fluidGlassBackdropOf(context),
        shape: () => shape,
        effects: (scope) => low
            ? (scope
              ..vibrancy()
              ..blur(fluidGlassBlurRadius))
            : (scope
              ..vibrancy()
              ..blur(fluidGlassBlurRadius)
              ..lens(
                spec.refractionBandDp,
                spec.refractionAmountDp,
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
                final selected = (_dragIndex ?? widget.selectedIndex)
                    .clamp(0, widget.labels.length - 1);
                void drag(Offset point) => setState(() => _dragIndex =
                    (point.dx / bounds.maxWidth * widget.labels.length)
                        .floor()
                        .clamp(0, widget.labels.length - 1));
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
                          onHorizontalDragCancel: () =>
                              setState(() => _dragIndex = null),
                          onHorizontalDragEnd: (_) {
                            final index = _dragIndex;
                            setState(() => _dragIndex = null);
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
                                                      backgroundColor: selected == i
                                                          ? theme.colorScheme
                                                              .primaryContainer
                                                          : Colors.transparent,
                                                      foregroundColor: selected == i
                                                          ? theme.colorScheme
                                                              .onPrimaryContainer
                                                          : theme.colorScheme
                                                              .onSurface),
                                                  child: widget.tabs
                                                      ? Text(widget.labels[i],
                                                          maxLines: 1)
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
