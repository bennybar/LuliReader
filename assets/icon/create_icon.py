#!/usr/bin/env python3
"""
Script to create a simple app icon for Luli Reader.
This creates a basic icon - you may want to replace it with a professionally designed icon.

Requirements: pip install Pillow
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_icon(size=1024, is_dark=False):
    """Create an RSS feed icon."""
    # Create image with transparent background
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Colors
    if is_dark:
        # Dark mode: white/light colors
        primary_color = (255, 255, 255, 255)  # White
        secondary_color = (220, 220, 220, 255)  # Light gray
    else:
        # Light mode: vibrant orange (classic RSS color)
        primary_color = (255, 126, 0, 255)  # RSS Orange
        secondary_color = (255, 165, 0, 255)  # Lighter orange
    
    # Center of icon
    center_x = size // 2
    center_y = size // 2
    
    # RSS icon consists of:
    # 1. A radio wave symbol (curved lines)
    # 2. A dot in the center
    
    # Draw the RSS radio waves (three concentric arcs)
    # Outer arc
    outer_radius = size // 2.5
    bbox_outer = [center_x - outer_radius, center_y - outer_radius, 
                   center_x + outer_radius, center_y + outer_radius]
    draw.arc(bbox_outer, start=45, end=135, fill=primary_color, width=size // 30)
    
    # Middle arc
    middle_radius = size // 3.5
    bbox_middle = [center_x - middle_radius, center_y - middle_radius,
                   center_x + middle_radius, center_y + middle_radius]
    draw.arc(bbox_middle, start=45, end=135, fill=primary_color, width=size // 30)
    
    # Inner arc
    inner_radius = size // 5
    bbox_inner = [center_x - inner_radius, center_y - inner_radius,
                  center_x + inner_radius, center_y + inner_radius]
    draw.arc(bbox_inner, start=45, end=135, fill=primary_color, width=size // 30)
    
    # Draw the dot in the center
    dot_size = size // 12
    draw.ellipse([center_x - dot_size, center_y - dot_size,
                  center_x + dot_size, center_y + dot_size],
                fill=primary_color)
    
    # Add a small circle around the dot for better visibility
    circle_size = size // 8
    draw.ellipse([center_x - circle_size, center_y - circle_size,
                  center_x + circle_size, center_y + circle_size],
                outline=primary_color, width=size // 60)
    
    return img

def main():
    """Generate all required icon files."""
    print("Creating app icons for Luli Reader...")
    
    # Create light mode foreground
    print("Creating light mode foreground icon...")
    light_icon = create_icon(1024, is_dark=False)
    light_icon.save('app_icon_foreground.png', 'PNG')
    print("✓ Created app_icon_foreground.png")
    
    # Create dark mode foreground
    print("Creating dark mode foreground icon...")
    dark_icon = create_icon(1024, is_dark=True)
    dark_icon.save('app_icon_foreground_dark.png', 'PNG')
    print("✓ Created app_icon_foreground_dark.png")
    
    # Create base icon (same as light foreground for iOS)
    print("Creating base icon...")
    base_icon = create_icon(1024, is_dark=False)
    base_icon.save('app_icon.png', 'PNG')
    print("✓ Created app_icon.png")
    
    print("\nAll icons created successfully!")
    print("Next steps:")
    print("1. Review the generated icons")
    print("2. If needed, replace with professionally designed icons")
    print("3. Run: flutter pub get")
    print("4. Run: flutter pub run flutter_launcher_icons")

if __name__ == '__main__':
    main()

