# MSIX Icon Assets

This folder must contain the following PNG icon files for MSIX packaging.
Generate them from the app icon source (`winres\icon.ico` or `app-icon.afdesign`).

## Required

| File                              | Size      | Description                  |
|-----------------------------------|-----------|------------------------------|
| `StoreLogo.png`                   | 50×50     | Store listing logo           |
| `Square44x44Logo.png`             | 44×44     | Taskbar & small tile         |
| `Square44x44Logo.targetsize-44.png` | 44×44   | Unplated taskbar icon        |
| `Square150x150Logo.png`           | 150×150   | Medium tile                  |

## Optional (recommended)

| File                              | Size      | Description                  |
|-----------------------------------|-----------|------------------------------|
| `Wide310x150Logo.png`             | 310×150   | Wide tile                    |
| `Square310x310Logo.png`           | 310×310   | Large tile                   |

## Notes

- All images must be PNG with transparent or `#2563EB` background.
- For best results, also provide scaled variants (e.g., `*.scale-200.png`).
- If optional logos are not provided, remove their references from `AppxManifest.xml`.
