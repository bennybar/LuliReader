import 'package:flutter/material.dart';

class LiquidGlassToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  const LiquidGlassToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: value ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      selected: value,
      onSelected: onChanged,
      avatar: Icon(
        value ? Icons.filter_list : Icons.filter_list_off,
        size: 18,
      ),
      showCheckmark: false,
    );
  }
}

