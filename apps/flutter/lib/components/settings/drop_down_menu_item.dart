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
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String boxKey;
  final List<DropdownMenuItem<int>> items;
  final bool enabled;
  final bool forceAppUpdate;

  @override
  State<DropDownMenuItem> createState() => _DropDownMenuItemState();
}

class _DropDownMenuItemState extends State<DropDownMenuItem> {
  late int value;

  @override
  void initState() {
    super.initState();
    value = GStorage.settings.get(widget.boxKey, defaultValue: 0);
  }

  @override
  Widget build(BuildContext context) {
    return MiuixBasicComponent(
      enabled: widget.enabled,
      title: widget.title,
      summary: widget.subtitle,
      startAction: Icon(widget.icon),
      endActions: [
        DropdownButton<int>(
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
          items: widget.items,
        ),
      ],
    );
  }
}
