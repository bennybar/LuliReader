import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../utils/platform_utils.dart';

class PlatformAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const PlatformAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  @override
  Widget build(BuildContext context) {
    if (isIOS) {
      return _buildCupertinoAppBar(context);
    } else {
      return _buildMaterialAppBar(context);
    }
  }

  Widget _buildCupertinoAppBar(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    
    return CupertinoNavigationBar(
      middle: title != null ? Text(title!) : null,
      trailing: actions != null && actions!.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: actions!,
            )
          : null,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      // Disable nav-bar hero transitions to avoid multiple-hero bugs with
      // nested scaffolds / tab stacks, while keeping back-swipe gesture.
      transitionBetweenRoutes: false,
      backgroundColor: isDark ? CupertinoColors.black : CupertinoColors.white,
      border: Border(
        bottom: BorderSide(
          color: isDark 
              ? CupertinoColors.separator.darkColor 
              : CupertinoColors.separator,
          width: 0.0, // iOS 15+ style - no border
        ),
      ),
    );
  }

  Widget _buildMaterialAppBar(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    
    return AppBar(
      title: title != null ? Text(title!) : null,
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: isDark ? Colors.black : Colors.white,
      foregroundColor: isDark ? Colors.white : Colors.black,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

