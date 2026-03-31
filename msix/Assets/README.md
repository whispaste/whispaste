# MSIX Icon Assets

This folder must contain the following PNG icon files for MSIX packaging.
Generate them from the app icon source (`winres\icon_256.png` or `app-icon.afdesign`).

## Required

| File                              | Size      | Description                  |
|-----------------------------------|-----------|------------------------------|
| `StoreLogo.png`                   | 50×50     | Store listing logo           |
| `Square44x44Logo.png`             | 44×44     | Plated tile icon             |
| `Square150x150Logo.png`           | 150×150   | Medium tile                  |

## Taskbar (unplated) — required for transparent taskbar icons

Windows puts a colored plate behind MSIX app icons by default.
To show a transparent icon in the taskbar, provide `_altform-unplated` variants:

| File                                                    | Size    |
|---------------------------------------------------------|---------|
| `Square44x44Logo.targetsize-16_altform-unplated.png`    | 16×16   |
| `Square44x44Logo.targetsize-24_altform-unplated.png`    | 24×24   |
| `Square44x44Logo.targetsize-32_altform-unplated.png`    | 32×32   |
| `Square44x44Logo.targetsize-48_altform-unplated.png`    | 48×48   |
| `Square44x44Logo.targetsize-256_altform-unplated.png`   | 256×256 |

These must have **transparent backgrounds**. Windows auto-discovers them by naming convention.

## Optional (recommended)

| File                              | Size      | Description                  |
|-----------------------------------|-----------|------------------------------|
| `Wide310x150Logo.png`             | 310×150   | Wide tile                    |
| `Square310x310Logo.png`           | 310×310   | Large tile                   |
| `*.scale-{100,125,150,200}.png`   | varies    | DPI scale variants           |
| `*.targetsize-{16..256}.png`      | varies    | Plated target-size variants  |

## Notes

- All images must be PNG with transparent background.
- The `_altform-unplated` suffix is required for transparent taskbar rendering.
- If optional logos are not provided, remove their references from `AppxManifest.xml`.
