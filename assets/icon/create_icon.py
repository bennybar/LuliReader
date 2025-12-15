#!/usr/bin/env python3
"""
Script to create a simple app icon for Luli Reader.
This creates a basic icon - you may want to replace it with a professionally designed icon.

Requirements: pip install Pillow
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_icon(size=1024, is_dark=False):
    """Create an app icon with a book and RSS feed symbol."""
    # Create image with transparent background
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Colors
    if is_dark:
        # Dark mode: white/light colors
        primary_color = (255, 255, 255, 255)  # White
        secondary_color = (200, 200, 200, 255)  # Light gray
        bg_color = (30, 30, 30, 255)  # Dark background for preview
    else:
        # Light mode: vibrant colors
        primary_color = (66, 133, 244, 255)  # Material Blue
        secondary_color = (25, 118, 210, 255)  # Darker blue
        bg_color = (255, 255, 255, 255)  # White background for preview
    
    # Draw background circle (for preview, will be transparent in final)
    margin = size // 10
    draw.ellipse([margin, margin, size - margin, size - margin], 
                 fill=bg_color if is_dark else None, outline=None)
    
    # Draw a book shape (simplified)
    book_width = size // 2
    book_height = size // 1.5
    book_x = (size - book_width) // 2
    book_y = size // 4
    
    # Book cover
    draw.rectangle([book_x, book_y, book_x + book_width, book_y + book_height],
                  fill=primary_color, outline=None)
    
    # Book pages (white/light)
    page_color = (255, 255, 255, 200) if not is_dark else (50, 50, 50, 200)
    draw.rectangle([book_x + 5, book_y + 5, book_x + book_width - 5, book_y + book_height - 5],
                  fill=page_color, outline=None)
    
    # Draw lines representing text (simplified)
    line_color = (100, 100, 100, 150) if not is_dark else (200, 200, 200, 150)
    for i in range(3, 8):
        y = book_y + (book_height // 10) * i
        draw.line([book_x + 15, y, book_x + book_width - 15, y], 
                 fill=line_color, width=2)
    
    # Draw RSS feed symbol (three curved lines)
    rss_x = book_x + book_width // 2
    rss_y = book_y + book_height + size // 8
    rss_size = size // 6
    
    # RSS waves
    for i, radius in enumerate([rss_size * 0.3, rss_size * 0.5, rss_size * 0.7]):
        # Draw partial arc (RSS symbol)
        bbox = [rss_x - radius, rss_y - radius, rss_x + radius, rss_y + radius]
        draw.arc(bbox, start=45, end=135, fill=primary_color, width=size // 50)
        # Dot in center
        if i == 0:
            dot_size = size // 40
            draw.ellipse([rss_x - dot_size, rss_y - dot_size, 
                         rss_x + dot_size, rss_y + dot_size],
                       fill=primary_color)
    
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

