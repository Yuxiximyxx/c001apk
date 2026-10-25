import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:get/get.dart';

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

  @override
  Widget build(BuildContext context) {
    return MiuixBasicComponent(
      enabled: widget.enabled,
      title: widget.title,
      summary: widget.subtitle,
      startAction: Icon(widget.icon),
      endActions: [
        // The Miuix end slot is width-capped (~134dp); at a 2x text scale
        // the widest dropdown item (4 CJK chars + arrow) needs ~137dp and
        // overflows by a few pixels. Clamp the button's text scaling so it
        // always fits the slot.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.75,
          child: DropdownButton<int>(
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: widget.enabled
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).disabledColor),
        value: value,
        onChanged: !widget.enabled
            ? null
            : (int? newValue) {
                if (newValue != null) {
                  GStorage.settings.put(widget.boxKey, newValue);
                  setState(() => value = newValue);
                  if (widget.forceAppUpdate) {
                    Get.forceAppUpdate();
                  }
                }
              },
          items: widget.items
              .map((item) => DropdownMenuItem<int>(
                    value: item.value,
                    onTap: item.onTap,
                    child: Text(
                      item.child is Text
                          ? (item.child as Text).data ?? ''
                          : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          ),
        ),
      ],
    );
  }
}
