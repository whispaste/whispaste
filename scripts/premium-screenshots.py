#!/usr/bin/env python3
"""
Premium Store screenshot framing for WhisPaste.

Takes raw UI screenshots from screenshots/raw/ and composites them into
professional, Store-ready marketing images with:
  - Gradient backgrounds (dark with brand accent)
  - Rounded corners + drop shadow on the app screenshot
  - Marketing headline + optional subtitle
  - Consistent 1920×1080 output

Usage:
    python scripts/premium-screenshots.py           # Process all screenshots
    python scripts/premium-screenshots.py --preview  # Show dimensions only

Output: screenshots/store/ directory with framed PNGs.
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Optional

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ── Paths ──────────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
SCREENSHOT_DIR = ROOT / "screenshots" / "raw"
LEGACY_SCREENSHOT_DIR = ROOT / "screenshots"
OUTPUT_DIR = ROOT / "screenshots" / "store"

# ── Dimensions ─────────────────────────────────────────────────────────────────
CANVAS_W, CANVAS_H = 1920, 1080
CORNER_RADIUS = 14
SHADOW_RADIUS = 30
SHADOW_OFFSET = (0, 8)
SHADOW_COLOR = (0, 0, 0, 120)

# ── Fonts (cross-platform) ─────────────────────────────────────────────────────
def _resolve_font(*candidates: str) -> Optional[str]:
    """Return the first existing font path from the candidates list."""
    for path in candidates:
        if Path(path).exists():
            return path
    return None


_BOLD_FONT = _resolve_font(
    # Windows
    r"C:\Windows\Fonts\segoeuib.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
    # macOS
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    # Linux
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
)

_LIGHT_FONT = _resolve_font(
    # Windows
    r"C:\Windows\Fonts\segoeuil.ttf",
    r"C:\Windows\Fonts\arial.ttf",
    # macOS
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial.ttf",
    # Linux
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
)

FONT_HEADLINE = _BOLD_FONT
FONT_SUBTITLE = _LIGHT_FONT
FONT_BADGE    = _BOLD_FONT

# ── Brand Colors ───────────────────────────────────────────────────────────────
# Dark gradient base colors (matches WhisPaste dark theme)
GRAD_TOP    = (15, 17, 23)      # Deep dark (near-black blue)
GRAD_BOTTOM = (25, 30, 45)      # Slightly lighter navy

# Accent glow colors per screenshot type
ACCENT_COLORS = {
    "workspace":    ((201, 160, 255), (110, 90, 210)),   # Purple → deep violet
    "settings":     ((56, 217, 240), (8, 145, 178)),     # Cyan → teal
    "analytics":    ((54, 217, 139), (56, 217, 240)),    # Green → cyan
    "replacements": ((255, 138, 101), (201, 160, 255)),  # Orange → purple
    "recording":    ((239, 68, 68), (255, 138, 101)),    # Red → orange
    "default":      ((201, 160, 255), (255, 138, 101)),  # Purple → orange
}

# Text colors
TEXT_WHITE = (255, 255, 255, 255)
TEXT_SUBTLE = (180, 190, 210, 200)
BADGE_BG = (201, 160, 255, 200)  # Purple badge

# ── Screenshot Definitions ─────────────────────────────────────────────────────
SCREENSHOTS = {
    "screenshot-01-history": {
        "accent": "workspace",
        "headline_en": "Keep your dictation workspace organized",
        "headline_de": "Halte deinen Diktier-Workspace organisiert",
        "subtitle_en": "Search, favorite, tag and revisit every capture without losing your flow",
        "subtitle_de": "Suche, favorisiere, tagge und finde jede Aufnahme wieder, ohne den Fluss zu verlieren",
        "badge_en": "Workspace",
        "badge_de": "Workspace",
    },
    "screenshot-02-replacements": {
        "accent": "replacements",
        "headline_en": "Trigger whole phrases with your voice",
        "headline_de": "Löse ganze Phrasen per Stimme aus",
        "subtitle_en": "Voice shortcuts insert repeated text in a second and keep repetitive writing light",
        "subtitle_de": "Sprachkürzel fügen wiederkehrende Texte in einem Moment ein und sparen Tipparbeit",
        "badge_en": "Voice shortcuts",
        "badge_de": "Sprachkürzel",
    },
    "screenshot-03-analytics": {
        "accent": "analytics",
        "headline_en": "See what voice saves you",
        "headline_de": "Sieh, was dir Stimme spart",
        "subtitle_en": "Track usage, momentum and your growing habit of speaking instead of typing",
        "subtitle_de": "Behalte Nutzung, Fortschritt und deine neue Gewohnheit im Blick, öfter zu sprechen statt zu tippen",
        "badge_en": "Insights",
        "badge_de": "Einblicke",
    },
    "screenshot-06-settings": {
        "accent": "settings",
        "headline_en": "Tune the app around your workflow",
        "headline_de": "Passe die App an deinen Workflow an",
        "subtitle_en": "Dial in language, hotkey and behavior once, then stay in your flow",
        "subtitle_de": "Stelle Sprache, Hotkey und Verhalten einmal sauber ein und bleib dann im Flow",
        "badge_en": "Settings",
        "badge_de": "Einstellungen",
    },
    "screenshot-07-recording": {
        "accent": "recording",
        "headline_en": "Start dictation in a heartbeat",
        "headline_de": "Starte Diktate in einem Augenblick",
        "subtitle_en": "The recording overlay keeps your next thought one shortcut away",
        "subtitle_de": "Das Aufnahme-Overlay hält deinen nächsten Gedanken nur einen Hotkey entfernt",
        "badge_en": "Recording",
        "badge_de": "Aufnahme",
    },
}


# ── Helper Functions ───────────────────────────────────────────────────────────

def create_gradient(width: int, height: int, top_color: tuple, bottom_color: tuple,
                    accent_colors: tuple = None) -> Image.Image:
    """Create a vertical gradient background with optional radial accent glow."""
    img = Image.new("RGBA", (width, height))
    draw = ImageDraw.Draw(img)

    # Vertical gradient
    for y in range(height):
        ratio = y / height
        r = int(top_color[0] + (bottom_color[0] - top_color[0]) * ratio)
        g = int(top_color[1] + (bottom_color[1] - top_color[1]) * ratio)
        b = int(top_color[2] + (bottom_color[2] - top_color[2]) * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))

    # Radial accent glow (subtle, centered behind the screenshot area)
    if accent_colors:
        glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        glow_draw = ImageDraw.Draw(glow)
        cx, cy = width // 2, int(height * 0.55)
        max_r = int(width * 0.45)
        c1, c2 = accent_colors

        for i in range(max_r, 0, -2):
            ratio = i / max_r
            alpha = int(18 * (1 - ratio) ** 2)  # Subtle glow, quadratic falloff
            r = int(c1[0] + (c2[0] - c1[0]) * ratio)
            g = int(c1[1] + (c2[1] - c1[1]) * ratio)
            b = int(c1[2] + (c2[2] - c1[2]) * ratio)
            glow_draw.ellipse(
                [cx - i, cy - int(i * 0.6), cx + i, cy + int(i * 0.6)],
                fill=(r, g, b, alpha)
            )

        img = Image.alpha_composite(img, glow)

    return img


def add_rounded_corners(img: Image.Image, radius: int) -> Image.Image:
    """Apply rounded corners to an image using an alpha mask."""
    w, h = img.size
    img = img.convert("RGBA")

    # Create rounded rectangle mask
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, w, h], radius=radius, fill=255)

    # Apply mask
    result = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    result.paste(img, mask=mask)
    return result


def create_shadow(size: tuple, radius: int, corner_radius: int,
                  offset: tuple = (0, 8), color: tuple = (0, 0, 0, 120)) -> Image.Image:
    """Create a drop shadow image for a given size."""
    # Expand canvas for shadow blur
    pad = radius * 2
    sw = size[0] + pad * 2
    sh = size[1] + pad * 2

    shadow = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)

    # Draw the shadow shape (rounded rect)
    x1 = pad + offset[0]
    y1 = pad + offset[1]
    x2 = pad + size[0] + offset[0]
    y2 = pad + size[1] + offset[1]
    draw.rounded_rectangle([x1, y1, x2, y2], radius=corner_radius, fill=color)

    # Blur the shadow
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=radius))

    return shadow, pad


def render_badge(draw: ImageDraw.Draw, text: str, x: int, y: int,
                 font: ImageFont.FreeTypeFont, bg_color: tuple) -> tuple:
    """Render a small rounded badge (pill shape) and return its bounding box."""
    bbox = font.getbbox(text)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    pad_x, pad_y = 14, 6
    bw = tw + pad_x * 2
    bh = th + pad_y * 2

    # Draw pill
    draw.rounded_rectangle([x, y, x + bw, y + bh], radius=bh // 2, fill=bg_color)

    # Draw text centered in pill
    tx = x + pad_x
    ty = y + pad_y - bbox[1]
    draw.text((tx, ty), text, fill=(255, 255, 255, 255), font=font)

    return bw, bh


def compose_premium_screenshot(raw_path: str, config: dict, lang: str) -> Image.Image:
    """Compose a single premium Store screenshot."""
    # Load raw screenshot
    raw = Image.open(raw_path).convert("RGBA")
    raw_w, raw_h = raw.size

    # Scale the screenshot to fit nicely in the canvas
    # Leave room for headline above and padding around
    headline_zone = 160   # Space for headline + subtitle at top
    padding_x = 80        # Horizontal padding
    padding_bottom = 50   # Bottom padding

    available_w = CANVAS_W - padding_x * 2
    available_h = CANVAS_H - headline_zone - padding_bottom

    # Scale to fit while maintaining aspect ratio
    scale = min(available_w / raw_w, available_h / raw_h)
    new_w = int(raw_w * scale)
    new_h = int(raw_h * scale)
    raw_scaled = raw.resize((new_w, new_h), Image.LANCZOS)

    # Center horizontally
    screenshot_x = (CANVAS_W - new_w) // 2
    screenshot_y = headline_zone + (available_h - new_h) // 2

    # Get accent colors
    accent_key = config.get("accent", "default")
    accent = ACCENT_COLORS.get(accent_key, ACCENT_COLORS["default"])

    # Create gradient background
    canvas = create_gradient(CANVAS_W, CANVAS_H, GRAD_TOP, GRAD_BOTTOM, accent)

    # Add drop shadow behind screenshot
    shadow_img, shadow_pad = create_shadow(
        (new_w, new_h), SHADOW_RADIUS, CORNER_RADIUS, SHADOW_OFFSET, SHADOW_COLOR
    )
    shadow_x = screenshot_x - shadow_pad
    shadow_y = screenshot_y - shadow_pad
    canvas = Image.alpha_composite(canvas, _place_on_canvas(shadow_img, shadow_x, shadow_y, CANVAS_W, CANVAS_H))

    # Add rounded corners to screenshot
    rounded = add_rounded_corners(raw_scaled, CORNER_RADIUS)

    # Place screenshot on canvas
    canvas.paste(rounded, (screenshot_x, screenshot_y), rounded)

    # Add subtle border around screenshot (1px, semi-transparent white)
    border_draw = ImageDraw.Draw(canvas)
    border_draw.rounded_rectangle(
        [screenshot_x - 1, screenshot_y - 1, screenshot_x + new_w, screenshot_y + new_h],
        radius=CORNER_RADIUS, outline=(255, 255, 255, 40), width=1
    )

    # ── Text overlay ──
    draw = ImageDraw.Draw(canvas)

    # Headline
    headline_key = f"headline_{lang}"
    subtitle_key = f"subtitle_{lang}"
    badge_key = f"badge_{lang}"

    headline = config.get(headline_key, config.get("headline_en", ""))
    subtitle = config.get(subtitle_key, config.get("subtitle_en", ""))
    badge_text = config.get(badge_key, "")

    try:
        if FONT_HEADLINE and FONT_SUBTITLE and FONT_BADGE:
            font_h = ImageFont.truetype(FONT_HEADLINE, 38)
            font_s = ImageFont.truetype(FONT_SUBTITLE, 20)
            font_b = ImageFont.truetype(FONT_BADGE, 13)
        else:
            raise OSError("No suitable font found on this platform")
    except (IOError, OSError):
        font_h = ImageFont.load_default(size=38)
        font_s = ImageFont.load_default(size=20)
        font_b = ImageFont.load_default(size=13)

    # Badge (above headline)
    badge_y = 30
    if badge_text:
        bbox_b = font_b.getbbox(badge_text)
        bw = bbox_b[2] - bbox_b[0] + 28
        badge_x = (CANVAS_W - bw) // 2
        render_badge(draw, badge_text, badge_x, badge_y, font_b, BADGE_BG)
        headline_y = badge_y + 40
    else:
        headline_y = badge_y + 10

    # Headline text (centered)
    h_bbox = font_h.getbbox(headline)
    h_w = h_bbox[2] - h_bbox[0]
    h_x = (CANVAS_W - h_w) // 2
    draw.text((h_x, headline_y), headline, fill=TEXT_WHITE, font=font_h)

    # Subtitle (centered, below headline)
    subtitle_y = headline_y + 52
    s_bbox = font_s.getbbox(subtitle)
    s_w = s_bbox[2] - s_bbox[0]
    s_x = (CANVAS_W - s_w) // 2
    draw.text((s_x, subtitle_y), subtitle, fill=TEXT_SUBTLE, font=font_s)

    return canvas


def _place_on_canvas(img: Image.Image, x: int, y: int, cw: int, ch: int) -> Image.Image:
    """Place an image on a transparent canvas of given size at (x, y)."""
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    # Clip to canvas bounds
    paste_x = max(0, x)
    paste_y = max(0, y)
    canvas.paste(img, (paste_x, paste_y))
    return canvas


# ── Main ───────────────────────────────────────────────────────────────────────

def process_all(preview: bool = False):
    """Process all raw screenshots into premium versions."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    raw_files = sorted(SCREENSHOT_DIR.glob("screenshot-*.png"))
    if not raw_files:
        raw_files = sorted(LEGACY_SCREENSHOT_DIR.glob("screenshot-*.png"))
    if not raw_files:
        print("❌ No raw screenshots found in screenshots/raw/ or screenshots/")
        print("   Run 'python scripts/capture-store-screenshots.py --all-pages' first.")
        sys.exit(1)

    processed = 0
    skipped = 0

    for raw_path in raw_files:
        name = raw_path.stem  # e.g. "screenshot-02-smartmode" or "screenshot-02-smartmode_de"

        # Determine base name and language
        if name.endswith("_de"):
            base_name = name[:-3]
            lang = "de"
        else:
            base_name = name
            lang = "en"

        config = SCREENSHOTS.get(base_name)
        if not config:
            print(f"  ⏭ Skipping {raw_path.name} (no config)")
            skipped += 1
            continue

        out_name = f"store-{raw_path.name}"
        out_path = OUTPUT_DIR / out_name

        if preview:
            raw = Image.open(raw_path)
            print(f"  📐 {raw_path.name}: {raw.size[0]}×{raw.size[1]} → {CANVAS_W}×{CANVAS_H}")
            continue

        print(f"  🎨 {raw_path.name} → store/{out_name}...")

        result = compose_premium_screenshot(str(raw_path), config, lang)

        # Save as RGB PNG (no alpha needed for Store)
        result = result.convert("RGB")
        result.save(str(out_path), "PNG", optimize=True)

        file_size = out_path.stat().st_size / 1024
        print(f"    ✓ Saved {CANVAS_W}×{CANVAS_H} ({file_size:.0f} KB)")
        processed += 1

    print(f"\n{'='*60}")
    if preview:
        print(f"  Preview complete. {len(raw_files)} files found, {skipped} without config.")
    else:
        print(f"  ✅ {processed} premium screenshots generated.")
        print(f"  📁 Output: {OUTPUT_DIR}")
        if skipped:
            print(f"  ⏭ {skipped} files skipped (no config)")
    print(f"{'='*60}")


def main():
    parser = argparse.ArgumentParser(description="Create premium Store screenshots")
    parser.add_argument("--preview", action="store_true", help="Show dimensions only, don't process")
    args = parser.parse_args()
    process_all(preview=args.preview)


if __name__ == "__main__":
    main()
