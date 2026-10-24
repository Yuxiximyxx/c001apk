import 'package:flutter/material.dart';

/// Keeps Material navigation semantics, focus and touch targets while adding
/// a compact tonal surface and a small spring response to selection.
class ExpressiveNavigationBar extends StatelessWidget {
  const ExpressiveNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    const icons = [
      Icons.home_outlined,
      Icons.feed_outlined,
      Icons.person_outline
    ];
    const selectedIcons = [Icons.home, Icons.feed, Icons.person];
    const labels = ['主页', '关注', '我的'];
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        // Match KernelSU Manager's Material short navigation content height.
        // NavigationBar adds the system bottom safe area separately.
        height:
            64 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 32),
        backgroundColor: colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: colors.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? colors.onSurface
                  : colors.onSurfaceVariant,
            )),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        animationDuration:
            reduced ? Duration.zero : const Duration(milliseconds: 400),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (var i = 0; i < labels.length; i++)
            NavigationDestination(
              label: labels[i],
              icon: AnimatedScale(
                scale: selectedIndex == i ? 1.12 : 1,
                duration:
                    reduced ? Duration.zero : const Duration(milliseconds: 400),
                curve: Curves.easeOutBack,
                child: Icon(selectedIndex == i ? selectedIcons[i] : icons[i]),
              ),
            ),
        ],
      ),
    );
  }
}
