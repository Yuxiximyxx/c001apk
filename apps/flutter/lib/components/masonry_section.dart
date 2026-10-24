import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

/// Keeps a fully measured section's extent while it is above the cache.
///
/// flutter_staggered_grid_view 0.7.0 retains only its last child after a whole
/// section is scrolled past. On the next layout it can lose the other columns'
/// offsets and request an incorrect jump backwards. A completed section needs
/// no child layout until it comes back into the cache or its content changes.
class MasonrySection extends SliverMasonryGrid {
  const MasonrySection({
    super.key,
    required super.delegate,
    required super.gridDelegate,
    super.crossAxisSpacing,
  });

  @override
  RenderSliverMasonryGrid createRenderObject(BuildContext context) =>
      _RenderMasonrySection(
          childManager: context as SliverMultiBoxAdaptorElement,
          gridDelegate: gridDelegate,
          crossAxisSpacing: crossAxisSpacing);
}

class _RenderMasonrySection extends RenderSliverMasonryGrid {
  _RenderMasonrySection({
    required super.childManager,
    required super.gridDelegate,
    required super.crossAxisSpacing,
  }) : super(mainAxisSpacing: 0);

  double? _completedExtent;
  double? _measuredWidth;

  @override
  void markNeedsLayout() {
    _completedExtent = null;
    super.markNeedsLayout();
  }

  @override
  void performLayout() {
    final extent = _completedExtent;
    if (extent != null &&
        _measuredWidth == constraints.crossAxisExtent &&
        constraints.scrollOffset + constraints.cacheOrigin >= extent) {
      geometry = SliverGeometry(scrollExtent: extent, maxPaintExtent: extent);
      return;
    }
    super.performLayout();
    final correction = geometry!.scrollOffsetCorrection;
    final firstData = firstChild?.parentData;
    if (correction != null &&
        correction < 0 &&
        firstData is SliverMasonryGridParentData &&
        firstData.index == 0) {
      var child = firstChild;
      var invalidOffset = false;
      while (child != null) {
        final data = child.parentData! as SliverMasonryGridParentData;
        invalidOffset |= data.layoutOffset?.isFinite == false;
        child = childAfter(child);
      }
      if (invalidOffset) {
        // The library has already rebuilt the missing prefix, but propagated
        // Infinity from a missing column. Recompute that prefix at this offset
        // instead of passing its invalid correction up to the viewport.
        final columns =
            gridDelegate.getCrossAxisCount(constraints, crossAxisSpacing);
        child = firstChild;
        while (child != null) {
          final data = child.parentData! as SliverMasonryGridParentData;
          data.layoutOffset = 0;
          data.crossAxisIndex = data.index! % columns;
          child = childAfter(child);
        }
        super.performLayout();
      }
    }
    final data = lastChild?.parentData;
    if (geometry!.scrollOffsetCorrection == null &&
        data is SliverMultiBoxAdaptorParentData &&
        data.index == childManager.childCount - 1) {
      _completedExtent = geometry!.scrollExtent;
      _measuredWidth = constraints.crossAxisExtent;
    }
  }
}
