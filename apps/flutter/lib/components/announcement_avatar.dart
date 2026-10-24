import 'package:flutter/material.dart';

/// A theme-colored app mark, without the launcher icon's baked-in background.
class AnnouncementAvatar extends StatelessWidget {
  const AnnouncementAvatar({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
        child: CircleAvatar(
            radius: size / 2,
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            child: Icon(Icons.all_inclusive, size: size * .64)));
  }
}
