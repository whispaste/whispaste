#!/usr/bin/env python3
# WCAG contrast of the picture's text-like and graphic colour pairs, per theme.
#   usage: scripts/contrast-check.py
# Reads themes/<theme>.css (generated from the design tokens). Text pairs need
# 4.5:1 (WCAG AA); graphic pairs (outlines, bars, placeholders) need 3:1 (1.4.11).
# Exits 1 when a text pair falls below 4.5:1.
import os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
themes_dir = os.path.join(here, "..", "themes")

TEXT = [("ink", "panel"), ("ink", "chip"), ("ink-muted", "panel")]
GRAPHIC = [("action-on-light", "panel"), ("action-on-light", "chip"), ("accent-on-light", "panel"),
           ("action-on-stage", "stage"), ("line-strong", "panel"), ("action-bright", "pill")]

def lum(hex_):
    c = [int(hex_[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def ratio(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)

def roles(theme):
    css = open(os.path.join(themes_dir, f"{theme}.css")).read()
    return {m.group(1): m.group(2) for m in re.finditer(r"--([a-z-]+):\s*(#[0-9a-fA-F]{6})", css)}

failed = False
for theme in ["hell", "dunkel", "marine"]:
    r = roles(theme)
    print(f"== {theme}")
    for a, b in TEXT:
        v = ratio(r[a], r[b])
        ok = v >= 4.5
        failed = failed or not ok
        print(f"  text     {a:13} on {b:6} {v:5.2f}:1  {'PASS' if ok else 'FAIL'} (>= 4.5)")
    for a, b in GRAPHIC:
        v = ratio(r[a], r[b])
        print(f"  graphic  {a:13} on {b:6} {v:5.2f}:1  {'pass' if v >= 3 else 'below 3:1'} (>= 3)")
sys.exit(1 if failed else 0)
