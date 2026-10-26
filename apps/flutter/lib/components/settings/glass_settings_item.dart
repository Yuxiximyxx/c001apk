import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../glass_surface.dart';

/// 设置页「玻璃材质」区（miuix17）：三预设 chips + 七个参数滑杆 +
/// 恢复预设值。数据模型（单一事实源，见 glass_surface.dart）：
/// - 选中预设 = 把该预设的数值整表写入自定义参数（dockGlassCustom），
///   此后有效 spec 由滑杆值决定；
/// - 拖动任一滑杆即写入绝对值并进入「自定义」态（chips 无选中、
///   显示「自定义」）；
/// - 从未存过自定义参数时，有效 spec = 已存预设（默认磨砂；老用户
///   存的是液态就用液态数值），升级后观感不变；
/// - 所有写入经 dockGlassSettingsListenable 即时触发全应用玻璃面
///   重建，拖动时当场可见效果。
class GlassSettingsItem extends StatelessWidget {
  const GlassSettingsItem({super.key});

  static String _presetLabel(DockGlassMaterial material) => switch (material) {
        DockGlassMaterial.clear => '毛玻璃',
        DockGlassMaterial.frosted => '磨砂玻璃',
        DockGlassMaterial.liquid => '液态玻璃',
      };

  @override
  Widget build(BuildContext context) {
    final listenable = dockGlassSettingsListenable();
    if (listenable == null) return _buildBody(context);
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: listenable,
      builder: (context, _, __) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final material = currentDockGlassMaterial();
    final preset = material.spec;
    final spec = resolveDockGlassSpec(material: material);
    final customized = dockGlassIsCustomized();
    // 高光滑杆是倍率：相对「上次选中预设」的高光值缩放 0–200%。
    final highlightScale = preset.highlightAlphaDark > 0
        ? (spec.highlightAlphaDark / preset.highlightAlphaDark)
            .clamp(0.0, 2.0)
            .toDouble()
        : 1.0;

    void update(DockGlassSpec next) => unawaited(writeDockGlassCustom(next));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MiuixBasicComponent(
          title: '玻璃材质',
          summary: customized
              ? '自定义参数（拖动滑杆调整，立即生效）'
              : '当前预设：${_presetLabel(material)}，可拖动滑杆自定义',
          startAction: const Icon(Icons.blur_on_outlined),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in DockGlassMaterial.values)
                _PresetChip(
                  label: _presetLabel(m),
                  selected: !customized && m == material,
                  onTap: () => unawaited(selectDockGlassPreset(m)),
                ),
              if (customized)
                const _PresetChip(label: '自定义', selected: true),
            ],
          ),
        ),
        MiuixSliderPreference(
          title: '透明度',
          value: spec.tintAlphaDark.clamp(0.0, 0.8),
          min: 0,
          max: 0.8,
          valueText: spec.tintAlphaDark.toStringAsFixed(2),
          onValueChange: (v) {
            // 深/浅同值缩放：浅色纱按当前深浅比例跟随（钳在 0.8 内）。
            final ratio = spec.tintAlphaDark > 0
                ? spec.tintAlphaLight / spec.tintAlphaDark
                : (preset.tintAlphaDark > 0
                    ? preset.tintAlphaLight / preset.tintAlphaDark
                    : 1.0);
            update(spec.copyWith(
              tintAlphaDark: v,
              tintAlphaLight: (v * ratio).clamp(0.0, 0.8).toDouble(),
            ));
          },
        ),
        MiuixSliderPreference(
          title: '折射强度',
          value: spec.refractionAmountDp.clamp(0.0, 48.0),
          min: 0,
          max: 48,
          valueText: '${spec.refractionAmountDp.toStringAsFixed(0)}dp',
          onValueChange: (v) => update(spec.copyWith(refractionAmountDp: v)),
        ),
        MiuixSliderPreference(
          title: '折射范围',
          value: spec.refractionBandDp.clamp(0.0, 40.0),
          min: 0,
          max: 40,
          valueText: '${spec.refractionBandDp.toStringAsFixed(0)}dp',
          onValueChange: (v) => update(spec.copyWith(refractionBandDp: v)),
        ),
        MiuixSliderPreference(
          title: '模糊强度',
          value: spec.sigma.clamp(0.0, 30.0),
          min: 0,
          max: 30,
          valueText: spec.sigma.toStringAsFixed(0),
          onValueChange: (v) => update(spec.copyWith(sigma: v)),
        ),
        MiuixSliderPreference(
          title: '饱和度',
          value: spec.saturate.clamp(1.0, 2.2),
          min: 1,
          max: 2.2,
          valueText: spec.saturate.toStringAsFixed(2),
          onValueChange: (v) => update(spec.copyWith(saturate: v)),
        ),
        MiuixSliderPreference(
          title: '色散强度',
          value: spec.dispersion.clamp(0.0, 0.5),
          min: 0,
          max: 0.5,
          valueText: spec.dispersion.toStringAsFixed(2),
          onValueChange: (v) => update(spec.copyWith(dispersion: v)),
        ),
        MiuixSliderPreference(
          title: '高光强度',
          value: highlightScale,
          min: 0,
          max: 2,
          valueText: '${(highlightScale * 100).round()}%',
          onValueChange: (v) => update(spec.copyWith(
            highlightAlphaDark:
                (preset.highlightAlphaDark * v).clamp(0.0, 1.0).toDouble(),
            highlightAlphaLight:
                (preset.highlightAlphaLight * v).clamp(0.0, 1.0).toDouble(),
          )),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: TextButton(
              onPressed: () => update(preset),
              child: Text('恢复「${_presetLabel(material)}」预设值'),
            ),
          ),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? colors.onPrimary : colors.onSurface,
              ),
        ),
      ),
    );
  }
}
