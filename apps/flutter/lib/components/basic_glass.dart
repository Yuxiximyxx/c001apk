import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../constants/liquid_glass_level.dart';
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

/// 玻璃面的采样解析（miuix24 起，miuix25 抽为共享）：顶栏作用域在场
/// 且 shader 可用时走正文录制（真折射，与 Dock 同构）；其余走既有
/// 统一解析（合成器 plain 路径）。
Backdrop resolveGlassBackdrop(BuildContext context) {
  final scoped = TopBarGlassScope.maybeOf(context);
  return scoped != null && isRuntimeShaderSupported()
      ? scoped
      : fluidGlassBackdropOf(context);
}

/// 顶栏选中药丸（miuix25）：与底栏药丸对齐的实现。此前药丸是
/// [GlassSurface.navigationLens]——primaryContainer 蓝纱 α.55 盖死、
/// 透镜恒开 spec 全量（液态 24/24）、高光/阴影/内阴影恒开，与底栏
/// 透镜「静止近全透、按下才长出」是两种质感。现逐项改走底栏本体
/// （fluid LiquidBottomTabs 药丸）的原值，唯一事实源 [DockPillGlass]：
/// - 纱：container 走 [dockGlassColorsForSpec]（与底栏同一映射点），
///   其上只叠中性纱（深 White/浅 Black α.10×(1−p)）与按压压暗
///   （Black α.03×p）——不再有蓝色块；
/// - 透镜：lens(10p, 14p, 色散开)，静止为 0、随 [pressProgress] 长出
///   （low 档与同栏其它面一致，只模糊不折射）；
/// - 高光 alpha = p、阴影 GlassShadow.standard alpha = p、内阴影
///   radius 8p / alpha = p，静止全关。
/// 采样模糊与底栏副本同值（blur 8），采样链与栏体同源
/// （[resolveGlassBackdrop]）。
class DockStylePill extends StatelessWidget {
  const DockStylePill({
    super.key,
    required this.extent,
    required this.pressProgress,
    required this.enabled,
    required this.level,
  });

  final Size extent;

  /// 按压进度 0..1（由 LiquidNavigationBar 的弹簧组驱动，参数同
  /// [DockPillGlass]；静止 0、按住 1）。
  final double pressProgress;
  final bool enabled;
  final LiquidGlassLevel level;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(extent.height / 2);
    final theme = Theme.of(context);
    if (!enabled || MediaQuery.highContrastOf(context)) {
      return ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: theme.colorScheme.primaryContainer,
          child: const SizedBox.expand(),
        ),
      );
    }
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
        dark: dark, accent: theme.colorScheme.primary);
    final shape =
        glassShapeForBorderRadius(radius, Directionality.of(context));
    final low = level == LiquidGlassLevel.low;
    final p = pressProgress.clamp(0.0, 1.0).toDouble();
    return LiquidGlassTheme(
      colors: colors,
      child: DrawBackdrop(
        backdrop: resolveGlassBackdrop(context),
        shape: () => shape,
        effects: (scope) => low
            ? (scope
              ..vibrancy()
              ..blur(DockPillGlass.blurRadius))
            : (scope
              ..vibrancy()
              ..blur(DockPillGlass.blurRadius)
              ..lens(
                DockPillGlass.lensBand * p,
                DockPillGlass.lensAmount * p,
                chromaticAberration: DockPillGlass.lensChromaticAberration,
              )),
        highlight: () => Highlight.standard.copyWith(alpha: p),
        shadow: () => GlassShadow.standard.copyWith(alpha: p),
        innerShadow: () => GlassInnerShadow(
          radius: DockPillGlass.innerShadowRadius * p,
          alpha: p,
        ),
        isolateSurface: false,
        onDrawSurface: (canvas, size) {
          final rect = Offset.zero & size;
          canvas.drawRect(rect, Paint()..color = colors.container);
          canvas.drawRect(
              rect,
              Paint()
                ..color = (dark ? Colors.white : Colors.black)
                    .withValues(alpha: DockPillGlass.restTintAlpha * (1 - p)));
          canvas.drawRect(
              rect,
              Paint()
                ..color = Colors.black
                    .withValues(alpha: DockPillGlass.pressShadeAlpha * p));
        },
        child: const SizedBox.expand(),
      ),
    );
  }
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
    final backdrop = resolveGlassBackdrop(context);
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

class _BasicNavigationState extends State<LiquidNavigationBar>
    with SingleTickerProviderStateMixin {
  // miuix25：药丸的运动物理与底栏对齐——位置/按压/速度/双轴缩放
  // 四条弹簧通道，ζ/k 全部取自共享定义 [DockPillGlass]（与底栏
  // LiquidBottomTabs 的 DampedDragAnimation 同组数值），不再用
  // AnimatedPositioned 的时长曲线吸附。拖动时位置弹簧跟随指针
  // 目标、按压弹簧长出透镜与放大；点按走一次 press 脉冲；松手
  // 吸附到最近槽并回调（回调时机与旧实现一致：拖动结束时）。
  Ticker? _ticker;
  Duration? _lastTick;
  late final DockSpring _value;
  final DockSpring _press = DockSpring(
      DockPillGlass.pressZeta, DockPillGlass.pressStiffness, 0);
  final DockSpring _velocity = DockSpring(
      DockPillGlass.velocityZeta, DockPillGlass.velocityStiffness, 0);
  final DockSpring _scaleX = DockSpring(
      DockPillGlass.scaleXZeta, DockPillGlass.scaleXStiffness, 1);
  final DockSpring _scaleY = DockSpring(
      DockPillGlass.scaleYZeta, DockPillGlass.scaleYStiffness, 1);
  bool _pointerDown = false;
  bool _pressEngaged = false;
  bool _dragging = false;
  double _targetValue = 0;

  @override
  void initState() {
    super.initState();
    _value = DockSpring(DockPillGlass.valueZeta,
        DockPillGlass.valueStiffness, widget.selectedIndex.toDouble());
    _targetValue = widget.selectedIndex.toDouble();
  }

  @override
  void didUpdateWidget(LiquidNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        !_dragging &&
        _targetValue != widget.selectedIndex.toDouble()) {
      _animateTo(widget.selectedIndex.toDouble());
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  bool get _reducedMotion =>
      mounted && MediaQuery.disableAnimationsOf(context);

  void _animateTo(double target) {
    _targetValue = target;
    _value.target = target;
    if (_reducedMotion) {
      _value.snap();
      _press.snap();
      if (mounted) setState(() {});
      return;
    }
    _ensureTicker();
  }

  void _engagePress() {
    _pointerDown = true;
    _pressEngaged = true;
    _ensureTicker();
  }

  void _releasePointer() {
    _pointerDown = false;
    _ensureTicker();
  }

  void _ensureTicker() {
    if (_reducedMotion) return;
    final ticker = _ticker ??= createTicker(_onTick);
    if (!ticker.isActive) {
      _lastTick = null;
      ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;
    if (last == null) return;
    var remaining = (elapsed - last).inMicroseconds / 1e6;
    if (remaining <= 0) return;
    var guard = 0;
    while (remaining > 0 && guard++ < 960) {
      final h = math.min(remaining, 1 / 240);
      _stepSprings(h);
      remaining -= h;
    }
    _postStep();
    if (mounted) setState(() {});
  }

  void _stepSprings(double h) {
    _press.target = _pressEngaged ? 1 : 0;
    _scaleX.target = _pressEngaged ? DockPillGlass.pressedScale : 1;
    _scaleY.target = _pressEngaged ? DockPillGlass.pressedScale : 1;
    _velocity.target = _value.velocity;
    _value.step(h);
    _press.step(h);
    _scaleX.step(h);
    _scaleY.step(h);
    _velocity.step(h);
  }

  void _postStep() {
    final range = math.max(1.0, (widget.labels.length - 1).toDouble());
    if (!_pointerDown &&
        !_dragging &&
        _pressEngaged &&
        (_value.value - _targetValue).abs() < 0.025 * range) {
      _pressEngaged = false;
    }
    if (_value.settled(0.0012, 0.01)) _value.snap();
    if (_press.settled(0.002, 0.02)) _press.snap();
    if (_scaleX.settled(0.002, 0.02)) _scaleX.snap();
    if (_scaleY.settled(0.002, 0.02)) _scaleY.snap();
    final idle = !_pressEngaged &&
        !_pointerDown &&
        !_dragging &&
        _value.settled(0.0012, 0.01) &&
        _press.settled(0.002, 0.02) &&
        _scaleX.settled(0.002, 0.02) &&
        _scaleY.settled(0.002, 0.02);
    if (idle) {
      _velocity.value = 0;
      _velocity.velocity = 0;
      _ticker?.stop();
    }
  }

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
                final selected =
                    _targetValue.round().clamp(0, count - 1).toInt();
                void dragTo(Offset point) {
                  final pos = (point.dx / slotWidth - 0.5)
                      .clamp(0.0, (count - 1).toDouble())
                      .toDouble();
                  _targetValue = pos;
                  _value.target = pos;
                  _ensureTicker();
                }

                const pillInset = 4.0;
                final velocityNorm =
                    (_velocity.value / 10).clamp(-1.0, 1.0).toDouble();
                final jellyX = (velocityNorm * 0.75).clamp(-0.2, 0.2).toDouble();
                final jellyY = (velocityNorm * 0.25).clamp(-0.2, 0.2).toDouble();
                final effScaleX = _scaleX.value / (1 - jellyX);
                final effScaleY = _scaleY.value * (1 - jellyY);
                return _BasicRoundHitRegion(
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(height / 2),
                        child: GestureDetector(
                          key: ValueKey(widget.tabs
                              ? 'liquid-tabs-surface'
                              : 'liquid-drag-surface'),
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => _engagePress(),
                          onTapUp: (_) => _releasePointer(),
                          onTapCancel: _releasePointer,
                          onHorizontalDragStart: (event) {
                            _dragging = true;
                            _engagePress();
                            dragTo(event.localPosition);
                          },
                          onHorizontalDragUpdate: (event) =>
                              dragTo(event.localPosition),
                          onHorizontalDragCancel: () {
                            _dragging = false;
                            _animateTo(widget.selectedIndex.toDouble());
                            _releasePointer();
                          },
                          onHorizontalDragEnd: (_) {
                            _dragging = false;
                            final index =
                                _targetValue.round().clamp(0, count - 1);
                            _animateTo(index.toDouble());
                            _releasePointer();
                            widget.onDestinationSelected(index);
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
                                // 选中药丸（miuix25）：与底栏药丸同参
                                // 的独立透镜层（DockStylePill），位置与
                                // 缩放由同组弹簧连续驱动，按压时透镜/
                                // 高光/阴影随 pressProgress 长出。
                                Positioned(
                                  left: _value.value * slotWidth + pillInset,
                                  top: pillInset,
                                  bottom: pillInset,
                                  width: slotWidth - pillInset * 2,
                                  child: IgnorePointer(
                                      child: Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..scaleByDouble(
                                          effScaleX, effScaleY, 1, 1),
                                    child: DockStylePill(
                                        key: const ValueKey(
                                            'liquid-tabs-pill'),
                                        extent: Size(
                                            slotWidth - pillInset * 2,
                                            height - pillInset * 2),
                                        pressProgress: _press.value
                                            .clamp(0.0, 1.0)
                                            .toDouble(),
                                        enabled: widget.refract,
                                        level: widget.level),
                                  )),
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
                                                  onPressed: () {
                                                    _pressEngaged = true;
                                                    _animateTo(i.toDouble());
                                                    widget
                                                        .onDestinationSelected(
                                                            i);
                                                  },
                                                  style: TextButton.styleFrom(
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              horizontal: 2),
                                                      // 药丸已由独立玻璃透镜层承担，
                                                      // 按钮本身不再画平色块。
                                                      backgroundColor:
                                                          Colors.transparent,
                                                      // 选中字形用强调色，
                                                      // 与底栏选中项的
                                                      // accent 身份一致。
                                                      foregroundColor: selected == i
                                                          ? theme.colorScheme
                                                              .primary
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
