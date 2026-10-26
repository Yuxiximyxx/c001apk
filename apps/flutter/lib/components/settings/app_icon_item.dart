import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../../utils/app_icon_util.dart';
import '../../utils/storage_util.dart';
import '../glass_dialog.dart';

/// 设置项「应用图标」（仅 Android）：在默认图标与「酷安绿」之间切换
/// 桌面启动图标。选中即经原生通道切换 activity-alias 并持久化到设置
/// 存储；本项显示以存储值为准——桌面刷新自身图标可能稍有延迟，属
/// 系统行为，与实际启用的 alias 无关。
class AppIconItem extends StatefulWidget {
  const AppIconItem({super.key});

  @override
  State<AppIconItem> createState() => _AppIconItemState();
}

class _AppIconItemState extends State<AppIconItem> {
  late AppIconVariant _variant;

  @override
  void initState() {
    super.initState();
    _variant = AppIconVariant.fromId(GStorage.appIcon);
  }

  Future<void> _select(AppIconVariant variant) async {
    if (variant == _variant) return;
    final applied = await AppIconUtil.applyIcon(variant);
    if (!mounted) return;
    if (applied == null) {
      SmartDialog.showToast('图标切换失败，请稍后再试');
      return;
    }
    GStorage.setAppIcon(applied.id);
    setState(() => _variant = applied);
  }

  Future<void> _openPicker(BuildContext context) {
    return showGlassDialog<void>(
      context: context,
      builder: (dialogContext) => GlassAlertDialog(
        title: const Text('应用图标'),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final variant in AppIconVariant.values)
              _AppIconOptionTile(
                variant: variant,
                selected: variant == _variant,
                onTap: () async {
                  Navigator.of(dialogContext).pop();
                  await _select(variant);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MiuixArrowPreference(
      title: '应用图标',
      summary: '当前：${_variant.label}',
      startAction: const Icon(Icons.app_shortcut_outlined),
      onClick: () => _openPicker(context),
    );
  }
}

class _AppIconOptionTile extends StatelessWidget {
  const _AppIconOptionTile({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final AppIconVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                variant.previewAsset,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                variant.label,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? colors.primary : colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
