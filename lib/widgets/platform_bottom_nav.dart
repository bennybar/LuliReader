import 'package:flutter/material.dart';

class BottomNavItem {
  final IconData icon;
  final String label;
  final bool hasNotification;

  const BottomNavItem({
    required this.icon,
    required this.label,
    this.hasNotification = false,
  });
}

class PlatformBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<BottomNavItem> items;

  const PlatformBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      height: 60,
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      destinations: items
          .map(
            (item) => NavigationDestination(
              icon: _buildIcon(context, item, false),
              selectedIcon: _buildIcon(context, item, true),
              label: item.label,
            ),
          )
          .toList(),
    );
  }

  Widget _buildIcon(BuildContext context, BottomNavItem item, bool selected) {
    final icon = Icon(
      item.icon,
      color: selected
          ? Theme.of(context).colorScheme.onPrimaryContainer
          : null,
    );

    if (!item.hasNotification) {
      return icon;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

