"""Generate branded NSIS installer bitmaps using WhisPaste design system colors."""
from PIL import Image, ImageDraw, ImageFont
import os
import sys

NAVY_DARK = (0x13, 0x18, 0x26)
NAVY_MID = (0x1D, 0x25, 0x38)
CYAN_ACCENT = (0x38, 0xD9, 0xF0)
CYAN_DARK = (0x0A, 0x99, 0xB8)
TEXT_PRIMARY = (0xF0, 0xF4, 0xFA)
TEXT_SECONDARY = (0xAB, 0xB8, 0xCC)

def lerp(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    icon_path = os.path.join(project_root, "resources", "app-icon ohne bg for dark.png")
    print(f"Icon path: {icon_path}")
    print(f"Icon exists: {os.path.exists(icon_path)}")

    # ─── Welcome/Finish Sidebar Bitmap (164×314) ───
    w, h = 164, 314
    img = Image.new("RGB", (w, h))
    
    # Diagonal gradient background
    for y in range(h):
        for x in range(w):
            t = (y / h * 0.7 + x / w * 0.3)
            img.putpixel((x, y), lerp(NAVY_DARK, NAVY_MID, t))

    # Top accent stripe (4px cyan gradient)
    for y in range(4):
        for x in range(w):
            img.putpixel((x, y), lerp(CYAN_ACCENT, CYAN_DARK, x / w))

    # Soft glow below accent stripe
    for y in range(4, 28):
        alpha = (1.0 - (y - 4) / 24.0) ** 2 * 0.2
        for x in range(w):
            base = img.getpixel((x, y))
            img.putpixel((x, y), lerp(base, (0x1A, 0x60, 0x78), alpha))

    # Overlay app icon (72px, centered horizontally, upper area)
    if os.path.exists(icon_path):
        icon = Image.open(icon_path).convert("RGBA").resize((72, 72), Image.LANCZOS)
        ix, iy = (w - 72) // 2, 50
        for py in range(72):
            for px in range(72):
                r, g, b, a = icon.getpixel((px, py))
                if a > 0:
                    al = a / 255.0
                    base = img.getpixel((ix + px, iy + py))
                    blended = tuple(
                        int(base[i] * (1 - al) + (r, g, b)[i] * al) for i in range(3)
                    )
                    img.putpixel((ix + px, iy + py), blended)
        print("Icon composited onto welcome bitmap")
    else:
        print("WARNING: Icon not found, skipping overlay")

    # Brand text
    draw = ImageDraw.Draw(img)
    try:
        font_bold = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 18)
        font_reg = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 11)
        print("Segoe UI fonts loaded")
    except Exception as e:
        print(f"Font error: {e}, using default")
        font_bold = font_reg = ImageFont.load_default()

    texts = [
        ("WhisPaste", font_bold, 135, TEXT_PRIMARY),
        ("Dictate anywhere.", font_reg, 163, TEXT_SECONDARY),
        ("Paste everywhere.", font_reg, 179, TEXT_SECONDARY),
    ]
    for txt, fnt, yy, col in texts:
        bb = draw.textbbox((0, 0), txt, font=fnt)
        tx = (w - (bb[2] - bb[0])) // 2
        draw.text((tx, yy), txt, fill=col, font=fnt)

    # Bottom accent line (3px, subtle)
    for y in range(h - 3, h):
        for x in range(w):
            base = img.getpixel((x, y))
            accent = lerp(CYAN_DARK, CYAN_ACCENT, x / w)
            img.putpixel((x, y), lerp(base, accent, 0.4))

    welcome_path = os.path.join(script_dir, "welcome.bmp")
    img.save(welcome_path, "BMP")
    print(f"Created: welcome.bmp ({w}x{h}, {os.path.getsize(welcome_path)} bytes)")

    # ─── Header Bitmap (150×57) ───
    hw, hh = 150, 57
    himg = Image.new("RGB", (hw, hh))
    
    # Horizontal gradient
    for y in range(hh):
        for x in range(hw):
            himg.putpixel((x, y), lerp(NAVY_DARK, NAVY_MID, x / hw * 0.6))

    # Top accent line (2px)
    for y in range(2):
        for x in range(hw):
            himg.putpixel((x, y), lerp(CYAN_ACCENT, CYAN_DARK, x / hw))

    # Small icon right-aligned
    if os.path.exists(icon_path):
        icon_sm = Image.open(icon_path).convert("RGBA").resize((36, 36), Image.LANCZOS)
        sx = hw - 36 - 8
        sy = (hh - 36) // 2 + 1
        for py in range(36):
            for px in range(36):
                r, g, b, a = icon_sm.getpixel((px, py))
                if a > 0:
                    al = a / 255.0
                    base = himg.getpixel((sx + px, sy + py))
                    blended = tuple(
                        int(base[i] * (1 - al) + (r, g, b)[i] * al) for i in range(3)
                    )
                    himg.putpixel((sx + px, sy + py), blended)
        print("Icon composited onto header bitmap")

    header_path = os.path.join(script_dir, "header.bmp")
    himg.save(header_path, "BMP")
    print(f"Created: header.bmp ({hw}x{hh}, {os.path.getsize(header_path)} bytes)")
    
    print("\nAll bitmaps generated successfully!")

if __name__ == "__main__":
    main()
