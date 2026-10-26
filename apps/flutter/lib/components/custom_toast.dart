import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// 悬浮提示（miuix17：toast 是悬浮控制层，面换液态玻璃 Regular/small，
/// 与底栏、FAB 同一套参数；文字色改 onSurface 保证在纱上的对比度）。
class CustomToast extends StatelessWidget {
  const CustomToast({super.key, required this.msg});

  final String msg;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:
          EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 30),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
          child: Text(
            msg,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
