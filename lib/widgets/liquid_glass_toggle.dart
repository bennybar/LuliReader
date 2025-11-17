import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import '../utils/platform_utils.dart';

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
    if (isIOS) {
      return _buildLiquidGlassToggle(context);
    } else {
      return _buildMaterialToggle(context);
    }
  }

  Widget _buildLiquidGlassToggle(BuildContext context) {
    return LiquidGlassLayer(
      settings: const LiquidGlassSettings(
        thickness: 15,
        blur: 20,
        glassColor: Color(0x33FFFFFF),
      ),
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.filter_list : Icons.filter_list_off,
                color: value ? Theme.of(context).colorScheme.primary : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: value ? Theme.of(context).colorScheme.primary : Colors.grey,
                  fontWeight: value ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialToggle(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      avatar: Icon(
        value ? Icons.filter_list : Icons.filter_list_off,
        size: 18,
      ),
    );
  }
}

