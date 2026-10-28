import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:get/get.dart';

import '../../components/glass_menu.dart';
import '../../utils/storage_util.dart';

class DropDownMenuItem extends StatefulWidget {
  const DropDownMenuItem({
    super.key,
    required this.icon,
    required this.title,
    required this.boxKey,
    required this.items,
    this.subtitle,
    this.enabled = true,
    this.forceAppUpdate = false,
    this.defaultValue = 0,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String boxKey;
  final List<DropdownMenuItem<int>> items;
  final bool enabled;
  final bool forceAppUpdate;
  final int defaultValue;

  @override
  State<DropDownMenuItem> createState() => _DropDownMenuItemState();
}

class _DropDownMenuItemState extends State<DropDownMenuItem> {
  late int value;

  @override
  void initState() {
    super.initState();
    value = GStorage.settings.get(widget.boxKey, defaultValue: widget.defaultValue);
  }

  String _labelOf(DropdownMenuItem<int> item) =>
      item.child is Text ? (item.child as Text).data ?? '' : '';

  Future<void> _openMenu(BuildContext context) async {
    final button = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null || !button.hasSize) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    // miuix17：下拉菜单面换液态玻璃（Regular/medium），菜单项与选中
    // 回写逻辑与原 DropdownButton 一致。
    final newValue = await showGlassMenu<int>(
      context: context,
      position: position,
      items: widget.items
          .map((item) => PopupMenuItem<int>(
                value: item.value,
                onTap: item.onTap,
                // miuix18：条目密度回标准菜单量级（48dp 高、16dp 横距），
                // 全设置页下拉共用这一处构造。
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_labelOf(item),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
    );
    if (newValue != null && mounted) {
      GStorage.settings.put(widget.boxKey, newValue);
      setState(() => value = newValue);
      if (widget.forceAppUpdate) {
        Get.forceAppUpdate();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.items.firstWhere(
      (item) => item.value == value,
      orElse: () => widget.items.first,
    );
    return MiuixBasicComponent(
      enabled: widget.enabled,
      title: widget.title,
      summary: widget.subtitle,
      startAction: Icon(widget.icon),
      endActions: [
        // The Miuix end slot is width-capped (~134dp); at a 2x text scale
        // the widest dropdown item (4 CJK chars + arrow) needs ~137dp and
        // overflows by a few pixels. Clamp the button's text scaling so it
        // always fits the slot (1.5 leaves margin under wider test fonts;
        // 1.75 still overflowed by 2px there, miuix23).
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.5,
          child: Builder(
            builder: (context) => InkWell(
              onTap: widget.enabled ? () => _openMenu(context) : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _labelOf(selected),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: widget.enabled
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).disabledColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      color: widget.enabled
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).disabledColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
