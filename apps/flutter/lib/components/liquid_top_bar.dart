import 'dart:math' as math;

import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/storage_util.dart';
import '../utils/extensions.dart';
import 'basic_glass.dart';
import 'page_backdrop_scope.dart';
export 'basic_glass.dart' show LiquidGlassButton;

/// 四个主页面顶栏共用的间距常量（miuix24 收口）：此前主页/关注/
/// 消息/我的各自散落 6/10/12/56 等魔数，出现「有的过大、有的过小」。
/// 顶栏横向边距、行与行之间、顶栏到内容一律走这一套。
abstract final class TopBarMetrics {
  /// 顶栏左右边距（与顶栏标题间距一致）。
  static const double horizontalPadding = 12;

  /// 顶栏内相邻行之间（关注页第一行↔筛选段控行）。
  static const double rowGap = 8;

  /// 顶栏（或其最后一行）到下方内容的间距。
  static const double contentGap = 12;

  /// 顶栏胶囊与搜索球之间。
  static const double searchGap = 10;
}

/// Root toolbar surfaces share the navigation glass preference and optics.
/// Keep the body in the same element slot when preferences change.
class LiquidTopBarScaffold extends StatefulWidget {
  const LiquidTopBarScaffold({
    super.key,
    required this.title,
    required this.body,
    this.onSearch,
    this.actions = const [],
    this.overlayBody = true,
    this.titleSpacing,
    this.glassTitle,
    this.compactTitle = false,
    this.floatWithoutGlass = false,
    this.glassActions,
    this.backdropIndex,
    this.externalBackdrop,
  });

  final Widget title, body;

  /// 主页面序号（miuix25）：非空时把本页正文录制注册到
  /// [PageBackdropScope] 的共享注册表，悬浮 Dock 改采样这一套
  /// 录制（每页只录一遍，见 page_backdrop_scope.dart）。子页面/
  /// 独立使用时不传，行为与 miuix24 一致（自持录制、无人共享）。
  final int? backdropIndex;

  /// 外部录制覆写（miuix25）：页面正文内部已有录制层时（如关注页
  /// 信息流的筛选胶囊录制），顶栏直接采样那套录制，本脚手架不再
  /// 包第二层 BackdropLayer——同一份内容只录一次。非空时正文不再
  /// 被本脚手架录制，注册表注册的也是这套外部录制。
  final LayerBackdrop? externalBackdrop;

  /// Root pages opt in without changing the body element's position.
  final WidgetBuilder? glassTitle;
  final List<Widget> Function(BuildContext context)? glassActions;
  final bool compactTitle, floatWithoutGlass;
  final VoidCallback? onSearch;
  final List<Widget> actions;
  final bool overlayBody;
  final double? titleSpacing;

  @override
  State<LiquidTopBarScaffold> createState() => _LiquidTopBarScaffoldState();
}

class _LiquidTopBarScaffoldState extends State<LiquidTopBarScaffold> {
  /// 正文录制句柄（miuix24）：正文包进 BackdropLayer 录制，顶栏在
  /// appBar 槽（录制子树之外）经 [TopBarGlassScope] 采样——与悬浮
  /// Dock 在 MainPage 的结构同构，顶栏因此是真折射而非 plain 模糊。
  final LayerBackdrop _bodyBackdrop = LayerBackdrop();

  /// 实际生效的录制：外部覆写优先（页面正文已有录制时共用那套，
  /// 不再叠录），否则自持这套。
  LayerBackdrop get _effectiveBackdrop =>
      widget.externalBackdrop ?? _bodyBackdrop;

  PageBackdropRegistry? _registry;
  LayerBackdrop? _registeredBackdrop;

  void _syncRegistration() {
    final index = widget.backdropIndex;
    final backdrop = index == null ? null : _effectiveBackdrop;
    if (_registry != null &&
        _registeredBackdrop != null &&
        _registeredBackdrop != backdrop) {
      _registry!.unregister(_registeredIndex!, _registeredBackdrop!);
      _registeredBackdrop = null;
      _registeredIndex = null;
    }
    if (index != null && backdrop != null && _registry != null) {
      _registry!.register(index, backdrop);
      _registeredBackdrop = backdrop;
      _registeredIndex = index;
    }
  }

  int? _registeredIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registry = PageBackdropScope.maybeOf(context);
    _syncRegistration();
  }

  @override
  void didUpdateWidget(LiquidTopBarScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalBackdrop != widget.externalBackdrop ||
        oldWidget.backdropIndex != widget.backdropIndex) {
      _syncRegistration();
    }
  }

  @override
  void dispose() {
    if (_registry != null && _registeredBackdrop != null) {
      _registry!.unregister(_registeredIndex!, _registeredBackdrop!);
    }
    _bodyBackdrop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: GStorage.settings.listenable(keys: [
          SettingsBoxKey.floatingNavigation,
          SettingsBoxKey.liquidGlass,
          SettingsBoxKey.liquidGlassLevel,
        ]),
        builder: (context, _, __) {
          final media = MediaQuery.of(context);
          final glass = widget.glassTitle != null &&
              GStorage.floatingNavigation &&
              (GStorage.liquidGlass || widget.floatWithoutGlass);
          final height = glass
              ? math.max(64.0, media.textScaler.scale(20) + 16)
              : kToolbarHeight;
          final inset = media.padding.top + height;
          final overlay = glass && widget.overlayBody;
          final search = IconButton(
            onPressed: widget.onSearch,
            icon: const Icon(Icons.search),
            tooltip: '搜索',
          );
          final appBar = AppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: height,
            titleSpacing:
                glass ? TopBarMetrics.horizontalPadding : widget.titleSpacing,
            backgroundColor: glass ? Colors.transparent : null,
            forceMaterialTransparency: glass,
            systemOverlayStyle:
                glass ? context.fitSystemUiOverlayStyle : null,
            elevation: glass ? 0 : null,
            scrolledUnderElevation: glass ? 0 : null,
            title: glass
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: widget.compactTitle ? double.infinity : 720),
                      child: Row(children: [
                        Expanded(
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                key: const ValueKey('glass-top-title'),
                                height: height - 16,
                                child: widget.glassTitle!(context),
                              )),
                        ),
                        if (widget.onSearch != null) ...[
                          const SizedBox(width: TopBarMetrics.searchGap),
                          LiquidGlassButton(
                            key: const ValueKey('glass-search'),
                            level: GStorage.liquidGlassLevel,
                            enabled: GStorage.liquidGlass,
                            tooltip: '搜索',
                            height: height - 16,
                            width: height - 16,
                            onPressed: widget.onSearch!,
                            child: const Center(child: Icon(Icons.search)),
                          ),
                        ],
                        if (widget.glassActions != null)
                          ...widget.glassActions!(context),
                      ]),
                    ),
                  )
                : widget.title,
            actions: glass
                ? null
                : [...widget.actions, if (widget.onSearch != null) search],
          );
          final bodyChild = Padding(
            padding: EdgeInsets.only(top: overlay ? 0 : inset),
            child: MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(top: overlay ? inset : 0),
              ),
              child: widget.body,
            ),
          );
          return Scaffold(
            extendBodyBehindAppBar: true,
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(height),
              child: TopBarGlassScope(
                backdrop: _effectiveBackdrop,
                child: appBar,
              ),
            ),
            // 外部录制覆写在场时，正文内部已有录制层（如关注页
            // 信息流），不再叠包第二层——同一内容只录一次。
            body: widget.externalBackdrop != null
                ? bodyChild
                : BackdropLayer(
                    backdrop: _effectiveBackdrop,
                    // 滚动期动态降级（miuix26）：正文连帧变化（滚动）
                    // 时捕获分辨率降到设备像素比的一半（捕获像素数
                    // 降到 1/4，玻璃采样本就带模糊、运动中不可辨）；
                    // 停下后的下一帧自动以全分辨率重捕——静止画面
                    // 观感与光学参数零变化（pixelRatio 不动）。
                    motionPixelRatio: media.devicePixelRatio * 0.5,
                    child: bodyChild,
                  ),
          );
        },
      );
}
