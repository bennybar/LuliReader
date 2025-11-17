import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import '../utils/platform_utils.dart';

class BottomNavItem {
  final IconData icon;
  final String label;

  const BottomNavItem({required this.icon, required this.label});
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
    if (isIOS) {
      return _buildLiquidGlassNav(context);
    } else {
      return _buildMaterialNav(context);
    }
  }

  Widget _buildLiquidGlassNav(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    
    return LiquidGlassLayer(
      settings: const LiquidGlassSettings(
        thickness: 15,
        blur: 20,
        glassColor: Color(0x33FFFFFF),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
        ),
        child: CupertinoTabBar(
          currentIndex: currentIndex,
          onTap: onTap,
          items: items
              .map(
                (item) => BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  label: item.label,
                ),
              )
              .toList(),
          backgroundColor: Colors.transparent,
          border: null,
          activeColor: Theme.of(context).colorScheme.primary,
          inactiveColor: isDark ? (Colors.grey[600] ?? Colors.grey) : Colors.grey,
        ),
      ),
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
}

