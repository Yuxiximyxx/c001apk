import 'package:flutter/material.dart';
import 'package:c001apk_flutter/components/masonry_section.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:sliver_tools/sliver_tools.dart';

/// Lazy masonry cards use the shortest column without truncating content.
/// Structural cards separate masonry sections and span the available width.
class AdaptiveCardList extends StatefulWidget {
  const AdaptiveCardList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.isFullWidth,
    this.controller,
    this.physics =
        const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
    this.padding = const EdgeInsets.all(10),
    this.leading,
    this.footer,
  }) : sliver = false;

  const AdaptiveCardList.sliver({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.isFullWidth,
    this.leading,
    this.footer,
    this.padding = const EdgeInsets.all(10),
  })  : sliver = true,
        controller = null,
        physics = const AlwaysScrollableScrollPhysics();

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool Function(int)? isFullWidth;
  final ScrollController? controller;
  final ScrollPhysics physics;
  final EdgeInsets padding;
  final Widget? leading;
  final Widget? footer;
  final bool sliver;

  @override
  State<AdaptiveCardList> createState() => _AdaptiveCardListState();
}

class _AdaptiveCardListState extends State<AdaptiveCardList> {
  final _ownedController = ScrollController();
  final _viewportKey = GlobalKey();
  final _itemKeys = <int, GlobalKey>{};
  Widget? _cachedCards;
  double? _cachedWidth;
  double? _cachedScale;
  int? _columns;
  int? _anchorIndex;
  double _anchorDy = 0;
  int _attempts = 0;
  int _anchorGeneration = 0;
  ScrollController get _scroll => widget.controller ?? _ownedController;
  ScrollPosition? get _position => widget.sliver
      ? Scrollable.maybeOf(context)?.position
      : _scroll.hasClients
          ? _scroll.position
          : null;

  double? _top(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    final viewport = widget.sliver
        ? Scrollable.maybeOf(context)?.context.findRenderObject()
        : _viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        !box.hasSize ||
        viewport is! RenderBox ||
        !viewport.hasSize) return null;
    return box.localToGlobal(Offset.zero).dy -
        viewport.localToGlobal(Offset.zero).dy;
  }

  void _captureAnchor() {
    if (_position == null || _position!.pixels <= 0) return;
    final indices = _itemKeys.keys.toList()..sort();
    double? nearest;
    for (final index in indices) {
      final key = _itemKeys[index]!;
      final dy = _top(key);
      final box = key.currentContext?.findRenderObject();
      if (dy != null &&
          box is RenderBox &&
          dy + box.size.height - 10 > 0.5 &&
          dy < _position!.viewportDimension &&
          (nearest == null || dy.abs() < nearest)) {
        _anchorIndex = index;
        _anchorDy = dy;
        _attempts = 0;
        nearest = dy.abs();
      }
    }
  }

  void _restoreAnchor(int generation) {
    if (!mounted ||
        generation != _anchorGeneration ||
        _anchorIndex == null ||
        _position == null) return;
    final target = _anchorIndex!;
    if (target >= widget.itemCount || _attempts++ >= 20) {
      _anchorIndex = null;
      return;
    }
    final targetKey = _itemKeys[target];
    final dy = targetKey == null ? null : _top(targetKey);
    double? correction;
    if (dy != null) {
      correction = dy - _anchorDy;
      if (correction.abs() < 1) {
        _anchorIndex = null;
        return;
      }
    } else {
      // Seek with measured card heights, then align the actual target once
      // it is laid out. Offscreen cards remain lazy even after a column change.
      var first = target;
      while (first > 0 && widget.isFullWidth?.call(first - 1) != true) {
        first--;
      }
      var end = target + 1;
      while (end < widget.itemCount && widget.isFullWidth?.call(end) != true) {
        end++;
      }
      final indices = _itemKeys.keys
          .where((i) =>
              i >= first && i < end && widget.isFullWidth?.call(i) != true)
          .toList()
        ..sort((a, b) => (a - target).abs().compareTo((b - target).abs()));
      for (final i in indices) {
        final key = _itemKeys[i]!;
        final top = _top(key);
        final box = key.currentContext?.findRenderObject();
        if (top != null && box is RenderBox && box.size.height > 0) {
          correction =
              top - _anchorDy + (target - i) * box.size.height / _columns!;
          break;
        }
      }
    }
    if (correction == null) {
      _anchorIndex = null;
      return;
    }
    final position = _position!;
    position.jumpTo((position.pixels + correction)
        .clamp(position.minScrollExtent, position.maxScrollExtent));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _restoreAnchor(generation));
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _ownedController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AdaptiveCardList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cachedCards = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedCards = null;
  }

  @override
  Widget build(BuildContext context) => widget.sliver
      ? SliverLayoutBuilder(
          builder: (context, constraints) =>
              _buildCards(context, constraints.crossAxisExtent))
      : LayoutBuilder(
          builder: (context, constraints) =>
              _buildCards(context, constraints.maxWidth));

  Widget _card(BuildContext context, int index) => Padding(
        key: _itemKeys.putIfAbsent(index, () => GlobalKey()),
        padding: const EdgeInsets.only(bottom: 10),
        child: IndexedSemantics(
            index: index, child: widget.itemBuilder(context, index)),
      );

  // Separate slivers must not build pagination footers just to estimate their
  // scroll extent. Wait until they enter the viewport's cache region.
  Widget _deferredSliver(Widget Function() builder) => SliverLayoutBuilder(
        builder: (_, constraints) =>
            constraints.remainingCacheExtent > 0 || constraints.scrollOffset > 0
                ? builder()
                : const SliverToBoxAdapter(child: SizedBox.shrink()),
      );

  Iterable<Widget> _sections(int columns) sync* {
    for (var start = 0; start < widget.itemCount;) {
      final first = start;
      final fullWidth = widget.isFullWidth?.call(first) == true;
      var end = first + 1;
      while (end < widget.itemCount &&
          (widget.isFullWidth?.call(end) == true) == fullWidth) {
        end++;
      }
      final delegate = SliverChildBuilderDelegate(
        (context, i) => _card(context, first + i),
        childCount: end - first,
        addSemanticIndexes: false,
      );
      if (fullWidth) {
        yield _deferredSliver(() => SliverList(delegate: delegate));
      } else if (end - first < columns) {
        // An incomplete row has no further cards to fill its gaps. The library
        // cannot restore missing columns in such a short masonry section.
        final count = end - first;
        yield _deferredSliver(() => SliverToBoxAdapter(
                child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: 10),
                  Expanded(
                      child: col < count
                          ? _card(context, first + col)
                          : const SizedBox.shrink()),
                ],
              ],
            )));
      } else {
        yield MasonrySection(
          key: ValueKey((first, columns)),
          gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns),
          crossAxisSpacing: 10,
          delegate: delegate,
        );
      }
      start = end;
    }
  }

  Widget _buildCards(BuildContext context, double width) {
    final scale =
        (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1.0, 2.0);
    // SliverLayoutBuilder also runs on scrolling. Reusing the child avoids
    // rebuilding unchanged delegates and invalidating measured section extents.
    if (_cachedCards != null &&
        _cachedWidth == width &&
        _cachedScale == scale) {
      return _wrapCards(_cachedCards!);
    }
    final columns =
        ((width - widget.padding.horizontal + 10) / (360 * scale + 10))
            .floor()
            .clamp(1, 4);
    if (_columns != null && _columns != columns) {
      final generation = ++_anchorGeneration;
      if (_anchorIndex == null) _captureAnchor();
      if (_anchorIndex != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _restoreAnchor(generation));
      }
    }
    _columns = columns;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _itemKeys.removeWhere((_, key) => key.currentContext == null);
      }
    });
    final cards = SliverPadding(
      padding: widget.padding,
      // Flutter 3.24's group drops masonry scrollOffsetCorrection. MultiSliver
      // forwards it immediately instead of laying out subsequent sections.
      sliver: MultiSliver(children: [
        if (widget.leading != null)
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: widget.leading)),
        ..._sections(columns),
        if (widget.footer != null)
          _deferredSliver(() => SliverToBoxAdapter(child: widget.footer!)),
      ]),
    );
    _cachedCards = cards;
    _cachedWidth = width;
    _cachedScale = scale;
    return _wrapCards(cards);
  }

  Widget _wrapCards(Widget cards) => widget.sliver
      ? cards
      : CustomScrollView(
          key: _viewportKey,
          controller: _scroll,
          physics: widget.physics,
          semanticChildCount: widget.itemCount,
          slivers: [cards]);
}
