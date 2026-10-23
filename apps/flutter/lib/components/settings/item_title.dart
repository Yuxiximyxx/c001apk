import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

class ItemTitle extends StatelessWidget {
  const ItemTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          color: MiuixTheme.of(context).colors.primary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
