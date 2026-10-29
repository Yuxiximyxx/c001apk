import 'dart:math' as math;

import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/storage_util.dart';
import '../utils/extensions.dart';
import 'basic_glass.dart';
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
  });

  final Widget title, body;

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

  @override
  void dispose() {
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
          return Scaffold(
            extendBodyBehindAppBar: true,
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(height),
              child: TopBarGlassScope(
                backdrop: _bodyBackdrop,
                child: appBar,
              ),
            ),
            body: BackdropLayer(
              backdrop: _bodyBackdrop,
              child: Padding(
                padding: EdgeInsets.only(top: overlay ? 0 : inset),
                child: MediaQuery(
                  data: media.copyWith(
                    padding: media.padding.copyWith(top: overlay ? inset : 0),
                  ),
                  child: widget.body,
                ),
              ),
            ),
          );
        },
      );
}
