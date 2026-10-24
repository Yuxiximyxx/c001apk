import 'package:flutter/material.dart';

import 'feed_navigation.dart';
import 'keyboard_scroll_region.dart';

enum ReadingMode { automatic, enabled, disabled }

/// Keeps the original page mounted while a detail is read beside it. The same
/// detail becomes full width when the window can no longer fit both panes.
class AdaptiveReadingPane extends StatefulWidget {
  const AdaptiveReadingPane(
      {super.key,
      required this.child,
      required this.detailBuilder,
      this.mode = ReadingMode.automatic});

  final Widget child;
  final ReadingMode mode;
  final Widget Function(BuildContext, String, VoidCallback) detailBuilder;

  @override
  State<AdaptiveReadingPane> createState() => AdaptiveReadingPaneState();
}

class AdaptiveReadingPaneState extends State<AdaptiveReadingPane> {
  String? _selectedId;
  LocalHistoryEntry? _history;
  bool _disposing = false;
  bool _canSplit = false;

  bool _open(String id) {
    if (!_canSplit || ModalRoute.of(context)?.isCurrent != true) return false;
    if (_selectedId == id) return true;
    if (_history == null) {
      _history = LocalHistoryEntry(onRemove: () {
        _history = null;
        if (!_disposing && mounted) setState(() => _selectedId = null);
      });
      ModalRoute.of(context)!.addLocalHistoryEntry(_history!);
    }
    setState(() => _selectedId = id);
    return true;
  }

  void close() => _history?.remove();

  @override
  void dispose() {
    _disposing = true;
    _history?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scale =
            (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1.0, 1.5);
        final minimumWidth = widget.mode == ReadingMode.automatic &&
                MediaQuery.sizeOf(context).shortestSide < 600
            ? double.infinity
            : 720.0;
        _canSplit = widget.mode != ReadingMode.disabled &&
            width >= minimumWidth * scale;
        final split = _canSplit && _selectedId != null;
        final detailWidth =
            split ? (width * .55).clamp(390.0 * scale, 760.0 * scale) : width;
        // LocalHistoryEntry alone does not notify Flutter 3.24's native back
        // bridge. PopScope keeps Android back inside the app while reading.
        return PopScope(
            canPop: _selectedId == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) close();
            },
            child: Stack(children: [
              Positioned.fill(
                left: split ? detailWidth + 1 : 0,
                child: FeedNavigation(
                  openFeed: _open,
                  selectedId: _selectedId,
                  child: ExcludeFocus(
                      excluding: _selectedId != null && !split,
                      child: ExcludeSemantics(
                          excluding: _selectedId != null && !split,
                          child: KeyboardScrollRegion(child: widget.child))),
                ),
              ),
              if (_selectedId != null)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  width: detailWidth,
                  child: ClipRect(
                      child: Material(
                    child: KeyboardScrollRegion(
                        key: ValueKey(_selectedId),
                        autofocus: true,
                        child: FeedNavigation(
                            openFeed: _open,
                            selectedId: _selectedId,
                            child: widget.detailBuilder(
                                context, _selectedId!, close))),
                  )),
                ),
              if (split)
                Positioned(
                    top: 0,
                    bottom: 0,
                    left: detailWidth,
                    child: const VerticalDivider(width: 1)),
            ]));
      });
}
