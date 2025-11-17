import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cupertino_native/cupertino_native.dart';

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
    final isApplePlatform = Platform.isIOS || Platform.isMacOS;
    return isApplePlatform ? _buildCupertinoNativeNav(context) : _buildMaterialNav(context);
  }

  Widget _buildCupertinoNativeNav(BuildContext context) {
    // CNTabBar already handles safe areas; returning it directly keeps it closer
    // to the bottom edge while still respecting the system inset.
    return CNTabBar(
      items: items
          .map(
            (item) => CNTabBarItem(
              label: item.label,
              icon: CNSymbol(_symbolNameForItem(item)),
            ),
          )
          .toList(),
      currentIndex: currentIndex,
      onTap: onTap,
    );
  }

  Widget _buildMaterialNav(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      destinations: items
          .map(
            (item) => NavigationDestination(
              icon: Icon(item.icon),
              label: item.label,
            ),
          )
          .toList(),
    );
  }

  Widget _buildNavItem(BuildContext context, BottomNavItem item, int index) {
    final isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.icon,
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
            size: 28,
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  String _symbolNameForItem(BottomNavItem item) {
    switch (item.label.toLowerCase()) {
      case 'home':
        return 'house';
      case 'unread':
        // Only show the badge symbol when there are unread items; otherwise
        // use the plain envelope icon to avoid a misleading dot.
        return item.hasNotification ? 'envelope.badge' : 'envelope';
      case 'starred':
        return 'star';
      case 'settings':
        return 'gearshape';
      default:
        return 'circle';
    }
  }
}

