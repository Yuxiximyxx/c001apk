import 'package:flutter/material.dart';

import '../glass_menu.dart';

/// 设置域统一的下拉选择器（miuix24）：触发区是「当前值 + 下箭头」
/// 一行，菜单走应用内既有的玻璃菜单（[showGlassMenu]，Regular/
/// medium 玻璃面），替代原生 DropdownButton 弹出的白底 Material
/// 菜单（图五：外观与字号页的液态玻璃档位菜单与其它弹窗不一致）。
/// 全设置域共用这一处实现，与 [DropDownMenuItem] 的菜单构造同口径
/// （条目 48dp 高、16dp 横距、选中项打勾）。
class GlassDropdownPicker<T> extends StatelessWidget {
  const GlassDropdownPicker({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    this.onChanged,
    this.isExpanded = false,
  });

  final T value;
  final List<T> items;
  final String Function(T value) labelOf;

  /// 为空时禁用（灰显、无点按），与 DropdownButton 的口径一致。
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;

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
    final newValue = await showGlassMenu<T>(
      context: context,
      position: position,
      items: [
        for (final item in items)
          CheckedPopupMenuItem<T>(
            value: item,
            checked: item == value,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(labelOf(item),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
    if (newValue != null) onChanged?.call(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final theme = Theme.of(context);
    final color =
        enabled ? theme.colorScheme.onSurface : theme.disabledColor;
    return Builder(
      builder: (context) => InkWell(
        onTap: enabled ? () => _openMenu(context) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize:
                isExpanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (isExpanded)
                Expanded(
                  child: Text(labelOf(value),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                )
              else
                Text(labelOf(value),
                    style:
                        theme.textTheme.bodyMedium?.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              Icon(Icons.arrow_drop_down, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
