import 'dart:math' as math;
import 'dart:ui' as ui show FragmentProgram;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import 'glass_surface.dart';

export 'glass_surface.dart';

/// 窄幅悬浮 Dock 底栏（miuix13 规格：宽约屏幕 58%、水平居中、高 68dp 的
/// 大圆角胶囊，悬于内容之上；miuix14 玻璃按 Kyant 配方校准，见
/// glass_surface.dart）。
///
/// miuix15：药丸升级为「可拖拽的液态透镜」，复刻 legado-with-MD3 的
/// FloatingBottomBar（Kyant LiquidBottomTabs 移植版）的交互与光学：
/// - 绘制顺序 = [底栏 GlassSurface, 标签内容, 药丸]——药丸的
///   BackdropFilter 天然采样到其下的标签内容，滑过时图标/文字被弯折
///   放大（液态档 SDF 透镜，带宽/量 = lens(10dp, 14dp)×pressProgress、
///   带色差，与 Legado 一致；毛/磨砂沿 miuix14 的纯色药丸降级）。
/// - 拖动走 DampedDragAnimation 同款弹簧组（Compose spring(ζ, k)，
///   质量 1）：value ζ1.0/k1000 临界阻尼跟手；pressProgress ζ1.0/k1000；
///   scaleX ζ0.6/k250、scaleY ζ0.7/k250（双轴不同步出果冻感）；
///   速度平滑 ζ0.5/k300。两边速度同为「槽/秒」，果冻公式直接套用。
/// - 拖动中只更新目标值，松手才吸附到最近索引并回调；点按立即选中，
///   并走一次 press→动画到位→release 的脉冲（release 等 value 与目标
///   差 < 全程 2.5% 才撤按压态）。
/// - 整栏橡皮筋：拖动时整栏水平位移 = 4dp × sign × EaseOut(|拖距/栏宽|)。
/// - 标签按邻近度 progress = 1 − |index − value| 连续驱动：图标着色与
///   填充态渐变、竖排文字渐入、按压时图标随邻近度放大。
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

/// 一条弹簧通道：直接积分 Compose spring 的 ODE（质量 1）
/// a = −k(x − target) − 2ζ√k·v，与 Flutter 的
/// SpringDescription(mass: 1, stiffness: k, damping: 2ζ√k) 等价。
class _Spring {
  _Spring(this.zeta, this.stiffness, double initial)
      : value = initial,
        target = initial;

  final double zeta;
  final double stiffness;
  double value;
  double velocity = 0;
  double target;

  void step(double dt) {
    final damping = 2 * zeta * math.sqrt(stiffness);
    final accel = -stiffness * (value - target) - damping * velocity;
    velocity += accel * dt;
    value += velocity * dt;
  }

  bool settled(double posEps, double velEps) =>
      (value - target).abs() < posEps && velocity.abs() < velEps;

  void snap() {
    value = target;
    velocity = 0;
  }
}

class _FloatingDockBarState extends State<FloatingDockBar>
    with TickerProviderStateMixin {
  /// 按压时药丸的放大倍率（Legado pressedScale = 78/56）。
  static const double _pressedScale = 78 / 56;

  /// 药丸透镜（Legado lens(10dp, 14dp, 色差=true)，随 pressProgress）。
  static const double _pillLensBandDp = 10;
  static const double _pillLensAmountDp = 14;

  ui.FragmentProgram? _refractionProgram;
  Ticker? _ticker;
  Duration? _lastTick;

  /// 药丸位置（槽索引单位），弹簧 ζ1.0/k1000。
  late final _Spring _value;
  late double _targetValue;

  /// 按压进度 0..1，弹簧 ζ1.0/k1000。
  final _Spring _press = _Spring(1.0, 1000, 0);

  /// 药丸双轴缩放，弹簧 ζ0.6/k250 与 ζ0.7/k250。
  final _Spring _scaleX = _Spring(0.6, 250, 1);
  final _Spring _scaleY = _Spring(0.7, 250, 1);

  /// value 速度的平滑跟随（槽/秒），弹簧 ζ0.5/k300；果冻公式用它。
  final _Spring _velocity = _Spring(0.5, 300, 0);

  /// 整栏橡皮筋的原始拖距（px）：拖动中直接 snap，松手弹簧 ζ1.0/k300 回 0。
  final _Spring _panelRaw = _Spring(1.0, 300, 0);

  bool _pointerDown = false;
  bool _pressEngaged = false;
  bool _dragging = false;
  double _slotWidth = 0;
  double _barWidth = 0;

  @override
  void initState() {
    super.initState();
    _value = _Spring(1.0, 1000, widget.selectedIndex.toDouble());
    _targetValue = widget.selectedIndex.toDouble();
    RefractionSupport.load().then((program) {
      if (mounted && program != null) {
        setState(() => _refractionProgram = program);
      }
    });
  }

  @override
  void didUpdateWidget(FloatingDockBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _animateToValue(widget.selectedIndex.toDouble());
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _animateToValue(double target) {
    _targetValue = target;
    _value.target = target;
    _ensureTicker();
  }

  void _ensureTicker() {
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
    // 定步长子步积分（≤1/240s），保证 k=1000 刚度下数值稳定。
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
    // press/缩放的目标由按压态决定（点按脉冲、拖动中都算按压中）。
    _press.target = _pressEngaged ? 1 : 0;
    _scaleX.target = _pressEngaged ? _pressedScale : 1;
    _scaleY.target = _pressEngaged ? _pressedScale : 1;
    _velocity.target = _value.velocity;
    _value.step(h);
    _press.step(h);
    _scaleX.step(h);
    _scaleY.step(h);
    _velocity.step(h);
    if (!_dragging) _panelRaw.step(h);
  }

  void _postStep() {
    // release 撤按压态的条件：指针已离手且 value 与目标差 < 全程 2.5%。
    final range = (FloatingDockBar.labels.length - 1).toDouble();
    if (!_pointerDown &&
        _pressEngaged &&
        (_value.value - _targetValue).abs() < 0.025 * range) {
      _pressEngaged = false;
    }
    if (_value.settled(0.0012, 0.01)) _value.snap();
    if (_press.settled(0.002, 0.02)) _press.snap();
    if (_scaleX.settled(0.002, 0.02)) _scaleX.snap();
    if (_scaleY.settled(0.002, 0.02)) _scaleY.snap();
    if (_panelRaw.settled(0.15, 8)) _panelRaw.snap();
    final idle = !_pressEngaged &&
        !_pointerDown &&
        _value.settled(0.0012, 0.01) &&
        _press.settled(0.002, 0.02) &&
        _scaleX.settled(0.002, 0.02) &&
        _scaleY.settled(0.002, 0.02) &&
        _panelRaw.settled(0.15, 8);
    if (idle) {
      _velocity.value = 0;
      _velocity.velocity = 0;
      _ticker?.stop();
    }
  }

  // ---- 手势 ----

  void _engagePress() {
    _pointerDown = true;
    _pressEngaged = true;
    _ensureTicker();
  }

  void _releasePointer() {
    _pointerDown = false;
    _dragging = false;
    _ensureTicker();
  }

  void _tapSlot(int index) {
    _animateToValue(index.toDouble());
    widget.onDestinationSelected(index);
  }

  void _handleTapUp(TapUpDetails details) {
    if (_slotWidth > 0) {
      final slot = (details.localPosition.dx / _slotWidth)
          .floor()
          .clamp(0, FloatingDockBar.labels.length - 1);
      _tapSlot(slot);
    }
    _releasePointer();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_slotWidth <= 0) return;
    final count = FloatingDockBar.labels.length;
    _targetValue =
        (_targetValue + details.delta.dx / _slotWidth).clamp(0, count - 1);
    _value.target = _targetValue;
    // 橡皮筋原始拖距直接跟随手指（Legado 的 offsetAnimation.snapTo）。
    _panelRaw.value += details.delta.dx;
    _panelRaw.velocity = 0;
  }

  void _handleDragEnd() {
    final targetIndex = _targetValue
        .round()
        .clamp(0, FloatingDockBar.labels.length - 1);
    _animateToValue(targetIndex.toDouble());
    _panelRaw.target = 0;
    // 拖动落回原标签不回调（点按的重选语义只属于点按，见 _tapSlot）。
    if (targetIndex != widget.selectedIndex) {
      widget.onDestinationSelected(targetIndex);
    }
    _releasePointer();
  }

  // ---- 构建 ----

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
      builder: (context, _, __) =>
          _buildBar(context, currentDockGlassMaterial()),
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
    final barWidth = screenWidth * FloatingDockBar.widthFactor;

    // 整栏橡皮筋位移：4dp × sign × EaseOut(|原始拖距/栏宽| 钳 1)。
    var panelOffset = 0.0;
    if (_barWidth > 0 && _panelRaw.value != 0) {
      final fraction =
          (_panelRaw.value / _barWidth).abs().clamp(0.0, 1.0).toDouble();
      panelOffset =
          4.0 * _panelRaw.value.sign * Curves.easeOut.transform(fraction);
    }

    final velocityNorm = (_velocity.value / 10).clamp(-1.0, 1.0).toDouble();
    final jellyX = (velocityNorm * 0.75).clamp(-0.2, 0.2).toDouble();
    final jellyY = (velocityNorm * 0.25).clamp(-0.2, 0.2).toDouble();
    final effScaleX = _scaleX.value / (1 - jellyX);
    final effScaleY = _scaleY.value * (1 - jellyY);

    return SizedBox(
      height: FloatingDockBar.height + bottomMargin,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: barWidth,
          height: FloatingDockBar.height,
          child: Transform.translate(
            offset: Offset(panelOffset, 0),
            child: GlassSurface(
              key: const Key('floatingDockCapsule'),
              borderRadius:
                  BorderRadius.circular(FloatingDockBar.height / 2),
              materialOverride: material,
              child: Material(
                type: MaterialType.transparency,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _barWidth = constraints.maxWidth;
                    _slotWidth = constraints.maxWidth /
                        FloatingDockBar.labels.length;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => _engagePress(),
                      onTapUp: _handleTapUp,
                      onTapCancel: _releasePointer,
                      onHorizontalDragStart: (_) {
                        _dragging = true;
                        _engagePress();
                      },
                      onHorizontalDragUpdate: _handleDragUpdate,
                      onHorizontalDragEnd: (_) => _handleDragEnd(),
                      onHorizontalDragCancel: () {
                        _panelRaw.target = 0;
                        _releasePointer();
                      },
                      child: Stack(
                        children: [
                          // 标签内容层（在药丸之下，药丸透镜采样得到它）。
                          Row(
                            children: [
                              for (var i = 0;
                                  i < FloatingDockBar.labels.length;
                                  i++)
                                Expanded(
                                  child: Semantics(
                                    button: true,
                                    selected: widget.selectedIndex == i,
                                    label: FloatingDockBar.labels[i],
                                    onTap: () => _tapSlot(i),
                                    child: _labelCell(
                                      i,
                                      (1 - (i - _value.value).abs())
                                          .clamp(0.0, 1.0)
                                          .toDouble(),
                                      accent,
                                      unselectedColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          // 药丸：连续位置 + 双轴弹簧缩放 + 速度果冻。
                          Positioned(
                            left: FloatingDockBar._pillInset +
                                _value.value * _slotWidth,
                            top: FloatingDockBar._pillInset,
                            width: _slotWidth - FloatingDockBar._pillInset * 2,
                            height: FloatingDockBar.height -
                                FloatingDockBar._pillInset * 2,
                            child: IgnorePointer(
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..scaleByDouble(
                                      effScaleX, effScaleY, 1, 1),
                                child: _SelectionPill(
                                  key: const Key('floatingDockPill'),
                                  material: material,
                                  color: pillColor,
                                  pressProgress: _press.value
                                      .clamp(0.0, 1.0)
                                      .toDouble(),
                                  refractionProgram: _refractionProgram,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 单个标签：progress 为邻近度（1=药丸正中）。选中形态 = 竖排图标+
  /// 文字（强调蓝），未选中只有图标；由连续的药丸位置驱动渐变。
  Widget _labelCell(
      int i, double progress, Color accent, Color unselectedColor) {
    final iconColor = Color.lerp(unselectedColor, accent, progress)!;
    final icon = progress >= 0.5
        ? FloatingDockBar._selectedIcons[i]
        : FloatingDockBar._icons[i];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            // 按压时图标随邻近度放大（Legado 标签内容 1→1.2 的邻近权重版）。
            scale: 1 + 0.2 * progress * _press.value,
            child: Icon(icon, size: 24 - 2 * progress, color: iconColor),
          ),
          if (progress > 0.001)
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: progress,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 1),
                    Text(
                      FloatingDockBar.labels[i],
                      style: TextStyle(
                        fontSize: 11,
                        height: 1,
                        color: accent.withValues(alpha: progress),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dock 的选中药丸（56dp 高）：静止为 miuix14 的半透深色椭圆；按压/
/// 拖动时按 Legado 配方过渡——深色按 (1−pressProgress) 淡出，表面 tint
/// （深色 White α0.1 / 浅色 Black α0.1，×(1−p)）与 Black α0.03p 叠入，
/// 高光/阴影/内阴影随 p 长出，液态档的 SDF 透镜（lens 10p/14p、色差）
/// 同步长出并弯折其下的标签内容。shader 不可用时回退纯色形态（全部
/// 拖动行为保留）。
class _SelectionPill extends StatelessWidget {
  const _SelectionPill({
    super.key,
    required this.material,
    required this.color,
    required this.pressProgress,
    required this.refractionProgram,
  });

  final DockGlassMaterial material;
  final Color color;
  final double pressProgress;
  final ui.FragmentProgram? refractionProgram;

  static const double _radius =
      (FloatingDockBar.height - FloatingDockBar._pillInset * 2) / 2;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(_radius);
    final p = pressProgress;
    final program = refractionProgram;
    final lens = material == DockGlassMaterial.liquid && program != null;

    final baseColor =
        color.withValues(alpha: color.a * (1 - p));
    final surfaceTint = (dark ? Colors.white : Colors.black)
        .withValues(alpha: 0.1 * (1 - p));
    final pressShade = Colors.black.withValues(alpha: 0.03 * p);
    final highlightAlpha = glassHighlightAlpha(material.spec, dark) * p;

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: p > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25 * p),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (lens)
              LayoutBuilder(
                builder: (context, constraints) => BackdropFilter(
                  filter: glassImageFilter(
                    spec: material.spec,
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    dpr: MediaQuery.devicePixelRatioOf(context),
                    refractionProgram: program,
                    // 药丸透镜按 Legado：无模糊打底、只透镜（采样已含
                    // 底栏玻璃处理过的背景），带宽/量随 pressProgress。
                    blurSigma: 0,
                    refractionBandDp: _FloatingDockBarState._pillLensBandDp * p,
                    refractionAmountDp:
                        _FloatingDockBarState._pillLensAmountDp * p,
                    chromaticAberration: true,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            DecoratedBox(decoration: BoxDecoration(color: baseColor)),
            DecoratedBox(decoration: BoxDecoration(color: surfaceTint)),
            DecoratedBox(decoration: BoxDecoration(color: pressShade)),
            if (p > 0)
              // 触点高光近似：Legado 的 InteractiveHighlight 是 AGSL
              // 镜面高光（跟随触点）；此处以药丸中心径向高光等效近似，
              // alpha 随 pressProgress。
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.9,
                    colors: [
                      Colors.white.withValues(alpha: 0.14 * p),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            if (p > 0)
              // 顶部镜面高光（Highlight，alpha = 高光强度 × pressProgress）。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: _radius,
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
            if (p > 0.01)
              // 内阴影近似：内侧暗边带（宽 8dp×p），无逐像素模糊。
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.10 * p),
                    width: 8 * p,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
