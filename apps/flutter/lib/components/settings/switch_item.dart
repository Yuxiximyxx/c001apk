import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:get/get.dart';

import '../../utils/storage_util.dart';

class SwitchItem extends StatefulWidget {
  const SwitchItem({
    super.key,
    required this.icon,
    required this.title,
    required this.boxKey,
    required this.defaultValue,
    this.subtitle,
    this.forceAppUpdate = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String boxKey;
  final bool defaultValue;
  final bool forceAppUpdate;

  @override
  State<SwitchItem> createState() => _SwitchItemState();
}

class _SwitchItemState extends State<SwitchItem> {
  late bool value;

  @override
  void initState() {
    super.initState();
    value =
        GStorage.settings.get(widget.boxKey, defaultValue: widget.defaultValue);
  }

  void onChanged(bool value) async {
    await GStorage.settings.put(widget.boxKey, value);
    if (widget.forceAppUpdate) {
      Get.forceAppUpdate();
    }
    if (mounted) setState(() => this.value = value);
  }

  @override
  Widget build(BuildContext context) {
    return MiuixSwitchPreference(
      value: value,
      onChanged: onChanged,
      title: widget.title,
      summary: widget.subtitle,
      startAction: Icon(widget.icon),
    );
  }
}
