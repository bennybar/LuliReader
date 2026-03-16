import 'package:flutter/material.dart';

class AppCountBadge extends StatelessWidget {
  const AppCountBadge({
    super.key,
    required this.count,
    this.label,
    this.compact = false,
    this.highlight = false,
  });

  final int count;
  final String? label;
  final bool compact;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveLabel = label ?? count.toString();
    final backgroundColor = highlight
        ? scheme.primaryContainer
        : scheme.secondaryContainer.withValues(alpha: 0.72);
    final foregroundColor =
        highlight ? scheme.onPrimaryContainer : scheme.onSecondaryContainer;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: count <= 0
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey<int>(count),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: compact ? 4 : 5,
              ),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(compact ? 999 : 14),
              ),
              child: Text(
                effectiveLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
              ),
            ),
    );
  }
}
