import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Connected list rows: large outer corners, small inner corners and a narrow
/// gap. Children keep their own gestures, focus, semantics and storage logic.
class ExpressiveListSection extends StatelessWidget {
  const ExpressiveListSection({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(height: 2),
              _ConnectedRow(
                first: index == 0,
                last: index == children.length - 1,
                child: children[index],
              ),
            ],
          ],
        ),
      );
}

class _ConnectedRow extends StatefulWidget {
  const _ConnectedRow(
      {required this.first, required this.last, required this.child});
  final bool first, last;
  final Widget child;

  @override
  State<_ConnectedRow> createState() => _ConnectedRowState();
}

class _ConnectedRowState extends State<_ConnectedRow> {
  final Map<int, Offset> _pointers = {};

  void _release(int pointer) {
    if (_pointers.remove(pointer) != null && _pointers.isEmpty) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Older system dynamic palettes omit M3's container roles. Their getters
    // fall back to surface, which makes the connected shape disappear against
    // the scaffold. Keep that palette and add a small neutral tonal layer.
    final containerColor =
        colors.surfaceContainer == theme.scaffoldBackgroundColor
            ? Color.alphaBlend(
                colors.onSurface.withValues(alpha: .08), colors.surface)
            : colors.surfaceContainer;
    final shape = RoundedRectangleBorder(
      borderRadius: _pointers.isNotEmpty
          ? BorderRadius.circular(16)
          : BorderRadius.vertical(
              top: Radius.circular(widget.first ? 28 : 4),
              bottom: Radius.circular(widget.last ? 28 : 4),
            ),
    );
    return Listener(
      onPointerDown: (event) =>
          setState(() => _pointers[event.pointer] = event.position),
      // A scroll winning the gesture arena cancels the child's tap, but does
      // not send a raw PointerCancelEvent to this listener.
      onPointerMove: (event) {
        final origin = _pointers[event.pointer];
        final slop =
            MediaQuery.maybeGestureSettingsOf(context)?.touchSlop ?? kTouchSlop;
        if (origin != null && (event.position - origin).distance > slop) {
          _release(event.pointer);
        }
      },
      onPointerUp: (event) => _release(event.pointer),
      onPointerCancel: (event) => _release(event.pointer),
      child: Material(
        color: containerColor,
        shape: shape,
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        clipBehavior: Clip.antiAlias,
        child: ListTileTheme(
          data: ListTileTheme.of(context).copyWith(
            shape: shape,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            minVerticalPadding: 12,
            minLeadingWidth: 24,
            horizontalTitleGap: 16,
            minTileHeight: 64,
            iconColor: colors.onSurfaceVariant,
            textColor: colors.onSurface,
            selectedColor: colors.onSecondaryContainer,
            selectedTileColor: colors.secondaryContainer,
            titleTextStyle: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w500),
            subtitleTextStyle: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          child: SwitchTheme(
            data: SwitchTheme.of(context).copyWith(
              thumbIcon: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? const Icon(Icons.check, size: 16)
                      : null),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
