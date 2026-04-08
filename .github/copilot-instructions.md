# WhisPaste — Technical Reference for AI Assistants

This document provides comprehensive technical details about the WhisPaste project for AI assistants working on the codebase. Read this before making any changes.

**Current version**: **1.2.0** (Flutter)
**NEVER auto-bump the version** without explicit owner approval. The version in `lib/core/app_info.dart` (`appVersion`) is the single source of truth.

**License**: MIT — WhisPaste is **open-source**, publicly hosted on GitHub. The full source code is visible to everyone. Implications:
- **No copyright notices** in the UI (e.g., "© All rights reserved" is inappropriate for MIT-licensed OSS).
- **Never commit secrets, API keys, credentials, or proprietary data** — the repo is public.
- Reference the MIT license and link to GitHub in the About page.
- Encourage community contributions, sponsoring, and starring in the About page.

## Security & Cloud Boundaries — MANDATORY

- **Zero-trust for every Supabase/cloud/premium surface** — the open-source client is always potentially inspectable, replayed, modified, or replaced. Never trust client code for entitlement checks, premium gating, share permissions, quota enforcement, or data isolation.
- **Server-side enforcement only** — premium access, collaborator permissions, sync ownership, and managed cloud usage must be enforced by Supabase-backed auth, RLS, edge functions, rate limits, and server-side request validation. UI locks are not security boundaries.
- **Secrets stay server-side** — upstream provider keys, service-role credentials, share-token raw values, and other privileged material must never ship in the client or rely on obscurity.
- **Explicit consent when data leaves the device** — any feature that sends user data through Supabase or WhisPaste-managed services must clearly disclose that behavior and remain opt-in.
- **Apply hardening retroactively, not only to new features** — the same zero-trust and secure-by-design standard applies to existing crash-report, feedback, analytics, sharing, sync, and future premium-service paths.

### Edge Function Security Conventions

Every Supabase Edge Function MUST follow these patterns:

| Pattern | Rule |
|---------|------|
| **Admin auth** | `ADMIN_API_KEY` via `x-api-key` header ONLY. Never accept via query param (logged in access logs). |
| **Rate limiting** | Per-device AND per-IP as separate queries (both must pass). Never use `.or()` for rate limit filters. |
| **X-Forwarded-For** | Always use the **last** entry (`split(",").pop().trim()`). The first entry is client-controlled; the last is appended by Supabase. |
| **Discord protection** | Server-side circuit breaker: max 20 Discord posts per minute. Excess reports are stored in DB with status `discord_throttled`. |
| **Uniform responses** | Public POST endpoints always return `{ "status": "accepted" }` with 202. Never leak internal state (dedup, auto-dismiss, rate limit reason). |
| **CORS** | Public read endpoints: `Access-Control-Allow-Origin: *`. Admin endpoints: **no CORS origin header** (server-to-server only). |
| **Security headers** | ALL responses: `X-Content-Type-Options: nosniff`, `Cache-Control: no-store`. |
| **Input validation** | All string inputs: length-capped, type/severity from allowlists, hashes validated as hex. Use `requireToken`, `requireString`, `optionalString` helpers. |
| **DB layer** | RLS: `USING(false)` deny-all + `REVOKE ALL` on anon/authenticated + service_role bypass. Edge Functions use service_role key server-side. |

## Product Vision

WhisPaste is a premium **cross-platform** dictation application optimized for **short dictations, quick notes, and spontaneous ideas**. It replaces typing with speaking — designed for people who think faster than they type.

- **Dictation tool** (like Whisper/WhisperFlow) — fast, reliable, AI-powered speech-to-text
- **Organized dictation history** — searchable, taggable archive of everything you've dictated

…wrapped in a UI that feels like:

- **Steam / gaming dashboards** — warm, immersive, emotionally engaging, makes you want to use it
- **WhatsApp / ChatGPT** — conversational, approachable, modern chat-style interactions

**Core promise**: Dictate anywhere, paste everywhere — with AI-powered post-processing that transforms raw speech into polished, context-aware text.

**Primary use case**: Short-form dictation — messages, emails, notes, code comments, ideas, to-dos, social media posts. Not meeting transcription or long-form recording. The typical dictation is 5–60 seconds.

**Quality bar**: This is a $20M-caliber product. Every feature, every UI element, every interaction must reflect premium craftsmanship. We ship polished, not "good enough."

**UI philosophy**: This is NOT a boring desktop productivity tool. It must be **fun to use**, emotionally engaging, and visually impressive — the kind of app users show off to friends. Inspired by gaming dashboards and modern chat interfaces while remaining clean and uncluttered. All features must be quickly accessible. Hide complexity behind progressive disclosure — not behind missing functionality. Usability FIRST, beauty SECOND — but beauty is NOT optional.

**AI is the CORE**: Speech-to-text and post-processing are the **critical** features. They MUST work reliably and performantly on every platform. Every architecture decision must prioritize AI inference performance and reliability.

## Target Audience

WhisPaste is built for **keyboard-heavy professionals** across **all major platforms** (Windows, macOS, Linux, iOS, Android) who want to replace typing with speaking: founders, freelancers, writers, consultants, developers, and anyone who spends hours typing messages, emails, notes, and comments. They value speed, clarity, and privacy, but they should not need technical knowledge to understand the product.

When writing UI copy, onboarding, landing-page copy, or release notes, optimize for:
- immediate comprehension by non-specialists
- confidence and trust around privacy / cloud vs local processing
- professional usefulness rather than hobbyist tinkering language
- lightweight, premium workflows instead of enterprise-heavy jargon

## Design System Rules — MANDATORY

These rules apply to ALL UI code. Violations will be caught in tests and code review.

### Visual Identity
- **Warm, vibrant, high-contrast** — text/background pairs MUST pass WCAG AA (4.5:1 body, 3.0:1 large). Tested in CI via `wcag_contrast_test.dart`.
- **Gradients over flat colors** — Content surfaces use warm diagonal gradients, not flat single-tone backgrounds. Gradients should be *visible* but not garish.
- **Frosted glass effects** — Use `WpGlassPanel` / `BackdropFilter` (σ ≈ 8–12, nearly-transparent tint) for overlays, modals, and the status bar. Glass effects should be FELT, not SEEN — subtle atmospheric depth, not iOS-style heavy blur.
- **NO glow effects** — Glow, neon bloom, colored box shadows, and text-shadow glow are **banned**. They look cheap and "AI slop." Prefer clean depth via layered neutral shadows, subtle gradients, and crisp borders.
- **Minimal borders** — Prefer spacing + dividers over visible borders. When a border IS needed, use `borderSubtle` (barely visible) or `borderDefault` (structural). Never thick, colorful borders.

### Layout & Components
- **NOT everything is a card** — Flat content on surfaces, cards ONLY for actionable items (history entries, model download items, onboarding prompts). Analytics dashboards, settings pages, and about pages use flat sections with `WpSection`, NOT card wrappers.
- **Desktop-native scaling** — Content MUST scale with the window. Use `LayoutBuilder`, `Flexible`, `Expanded` — never hardcoded widths for content areas. The app must look equally good at 1024×768 and 2560×1440.
- **No collapsible sections in settings** — All settings sections are flat and always visible. Use logical grouping and ordering instead of accordion/collapse patterns.

### Motion & Animations — CRITICAL
Micro-animations are **mandatory** for every state transition. They make the app feel premium and alive.

| Transition | Duration | Animation |
|---|---|---|
| **Hover enter** | `WpMotion.hoverIn` (0ms = instant) | Instant color change, no delay |
| **Hover exit** | `WpMotion.hoverOut` (80ms) | Smooth fade-out |
| **Page navigation** | `WpMotion.smooth` (300ms) | Fade + subtle slide-up via `AnimatedSwitcher` |
| **Detail panel open/close** | `WpMotion.smooth` (300ms) | Animated width expansion + opacity |
| **Detail content swap** | `WpMotion.fast` (120ms) | Crossfade via `AnimatedSwitcher` keyed by entry ID |
| **View mode switch** | `WpMotion.normal` (200ms) | Crossfade via `AnimatedSwitcher` keyed by view mode |
| **Filter chip toggle** | `WpMotion.fast` (120ms) | `AnimatedContainer` color transition |
| **Collapse/expand** | `WpMotion.smooth` (300ms) | `AnimatedSize` or `AnimatedContainer` |
| **Toast/notification** | `WpMotion.smooth` (300ms) | Slide in from right + fade |

**Rules:**
- Use `AnimatedSwitcher` for content that changes identity (different entries, different pages)
- Use `AnimatedContainer` for same-widget property changes (color, size, padding)
- Use `AnimatedSize` for content that grows/shrinks
- NEVER block the UI thread for animations
- NEVER use `Duration.zero` for any animation except hover-in

### Icons
- **Primary**: `lucide_icons_flutter` (v3.1.12+) — NOT the old `lucide_icons` package
- **Complementary**: `font_awesome_flutter` (Free — Solid, Regular, Brands) — use whenever Lucide lacks a fitting icon or the FA variant is visually better. NOT just a fallback — it's a first-class complementary icon source.
- **License**: Font Awesome Free icons are CC BY 4.0 (icons), SIL OFL 1.1 (fonts), MIT (code). Always verify you're using only Free-tier icons, never Pro.
- **Selection rule**: Check Lucide first. If no match or FA's icon communicates the concept better, use FA. Never use Material Icons — they're too chunky for this brand.
- Icon name changes (Lucide v3): `barChart3` → `chartNoAxesColumn`, `code2` → `codeXml`, `wand2` → `wandSparkles`

## Architecture Overview

### Architecture: Flutter + Native Subprocesses

WhisPaste is a **pure Flutter** application:

- **Frontend + Logic**: Flutter (Dart) — single codebase for Windows, macOS, Linux, iOS, Android
- **Database**: SQLite via `drift` (Dart, cross-platform, type-safe)
- **AI Inference**: whisper.cpp (STT) and llama.cpp (LLM) as managed native subprocesses (desktop)
- **State Management**: Riverpod
- **System Integration**: Platform channels + native plugins

### Key Architectural Decisions

1. **Pure Dart architecture**: All business logic is in Dart. AI subprocess management (whisper-server, llama-server), GPU detection, audio processing, and download management are implemented directly in Dart services.

2. **Cross-platform FIRST**: Every feature, every widget, every service MUST be designed cross-platform from the start. Where platform-specific code is needed, use Flutter platform channels with implementations for all target platforms.

3. **Provider abstraction**: STT and LLM backends are pluggable via provider interfaces. Local inference (whisper.cpp, llama.cpp) and cloud APIs (OpenAI, Groq, Deepgram, Anthropic, Gemini) share the same interface.

4. **Multi-vendor GPU support**: GPU detection covers NVIDIA (nvidia-smi), AMD, and Intel. Binary selection: CUDA for NVIDIA, Vulkan for AMD/Intel, OpenBLAS for CPU. Detection via platform-specific Dart services.

5. **AI performance is CRITICAL**: Audio capture, STT inference, and LLM post-processing must run with minimal latency. Use Dart Isolates for compute-heavy work. Native subprocess management for inference servers. Never block the UI thread with AI operations.

6. **Feature naming**: Post-processing is called **"Post-Processing"** (EN) / **"Nachbearbeitung"** (DE). Internal config keys use `smart_mode` for backward compatibility.

### Core Flutter Packages

| Purpose | Package | Platforms |
|---------|---------|-----------|
| Window management | `window_manager` | Desktop |
| Window effects (Mica/Acrylic) | `flutter_acrylic` | Desktop |
| System tray | `tray_manager` | Desktop |
| Global hotkeys | `hotkey_manager` | Desktop |
| Audio recording | `record` + platform channels | All |
| SQLite database | `drift` | All |
| State management | `riverpod` | All |
| Clipboard | `super_clipboard` | All |
| Auto-update | `auto_updater` / `sparkle_flutter` | Desktop |
| Single instance | `window_single_instance` | Desktop |
| Autostart | `launch_at_startup` | Desktop |

## Project Structure

```
whispaste/
├── .github/
│   ├── workflows/           # CI/CD (ci.yml, release.yml, codeql.yml, deploy-pages.yml, build-whisper-server.yml)
│   └── copilot-instructions.md
├── .agents/skills/          # Copilot agent skills
├── lib/                     # Flutter/Dart source (main codebase)
│   ├── main.dart            # Entry point
│   ├── app.dart             # MaterialApp, routing, theme
│   ├── core/
│   │   ├── theme/           # Design tokens, ThemeData (light + dark)
│   │   ├── l10n/            # Translations (EN + DE, ARB files)
│   │   ├── config/          # App configuration (SQLite persistence)
│   │   └── platform/        # Platform channel interfaces
│   ├── features/
│   │   ├── recording/       # Audio capture, VAD, safety guard, state machine
│   │   ├── transcription/   # STT provider abstraction (local + cloud)
│   │   ├── postprocessing/  # LLM provider abstraction (local + cloud)
│   │   ├── history/         # SQLite history, search, CRUD, export
│   │   ├── settings/        # Settings UI + state
│   │   ├── replacements/    # Voice shortcuts
│   │   ├── analytics/       # Usage statistics
│   │   ├── about/           # App info, credits
│   │   └── feedback/        # User feedback
│   ├── widgets/             # Shared widget library
│   │   ├── sidebar.dart     # Left icon navigation (70px)
│   │   ├── status_bar.dart  # Bottom status bar with chips
│   │   ├── fab.dart         # Recording FAB with pulse animation
│   │   ├── section.dart     # Flat content section with header
│   │   ├── card.dart        # Card (ONLY for actionable items)
│   │   ├── toggle.dart      # Custom switch
│   │   ├── dropdown.dart    # Custom styled select
│   │   ├── slider.dart      # Range input
│   │   ├── chip.dart        # Status/tag pill
│   │   ├── dialog.dart      # Centered modal with frosted backdrop
│   │   ├── toast.dart       # Slide-in notification
│   │   ├── search_box.dart  # Input with icon + clear
│   │   └── empty_state.dart # Centered illustration + text + action
│   └── services/
│       ├── audio_service.dart       # Audio capture abstraction
│       ├── stt_service.dart         # STT subprocess + provider management
│       ├── llm_service.dart         # LLM subprocess + provider management
│       ├── gpu_service.dart         # GPU detection
│       ├── hotkey_service.dart      # Global hotkey registration
│       ├── tray_service.dart        # System tray icon + menu
│       ├── clipboard_service.dart   # Clipboard + paste simulation
│       ├── update_service.dart      # Auto-updater
│       ├── notification_service.dart
│       └── crash_service.dart       # Crash reporting (Supabase relay)
├── test/                    # Flutter widget + integration tests
├── integration_test/        # End-to-end platform tests
├── assets/
│   ├── icons/               # App icons (all sizes, all platforms)
│   ├── fonts/               # Custom fonts (if any)
│   └── sounds/              # UI sounds (recording start/stop)
├── installer/               # NSIS installer scripts (Windows legacy)
├── msix/                    # Windows MSIX packaging
├── scripts/                 # Build & utility scripts
├── website/                 # Astro-based project website (separate)
├── supabase/                # Supabase Edge Functions + migrations
│   ├── functions/           # crash-relay, crash-cleanup, analytics, feedback
│   └── migrations/          # Database migrations
├── resources/               # App icons and assets (source files)
├── pubspec.yaml             # Flutter dependencies
└── README.md
```

## Build & Test Commands

### Flutter (Primary — UI + full app)

```bash
# Run in development (hot reload)
flutter run -d windows    # or: macos, linux, chrome
flutter run -d <device>   # iOS/Android device or emulator

# Build (production)
flutter build windows --release
flutter build macos --release
flutter build linux --release
flutter build appbundle --release   # Android AAB
flutter build ios --release         # iOS

# Test (all)
flutter test

# Test (specific file)
flutter test test/features/history/history_test.dart

# Test (integration)
flutter test integration_test/

# Analyze (lint)
flutter analyze

# Format
dart format lib/ test/
```

## Cross-Platform Strategy

### MANDATORY: Cross-Platform First

Every feature MUST work on all target platforms or gracefully degrade with clear user communication. This is not optional — it is a core architectural requirement.

### Platform Support Matrix

| Feature | Windows | macOS | Linux | Android | iOS |
|---------|---------|-------|-------|---------|-----|
| Flutter UI | ✅ | ✅ | ✅ | ✅ | ✅ |
| Custom window chrome | ✅ Mica/Acrylic | ✅ Transparent | ✅ System WM | N/A | N/A |
| System tray | ✅ | ✅ Menu bar | ✅ AppIndicator | N/A | N/A |
| Global hotkeys | ✅ | ✅ (Accessibility) | ✅ | N/A | N/A |
| Floating button | ✅ Multi-window | ✅ Multi-window | ✅ Multi-window | ⚠️ Overlay service | ❌ Not possible |
| Recording overlay | ✅ | ✅ | ✅ | ✅ Stack | ✅ Stack |
| Audio capture | ✅ WASAPI | ✅ AVAudioEngine | ✅ ALSA/Pulse | ✅ | ✅ |
| Clipboard + paste sim | ✅ SendInput | ✅ CGEventPost | ✅ xdotool | ⚠️ Clipboard only | ⚠️ Clipboard only |
| Local STT (whisper.cpp) | ✅ | ✅ | ✅ | ⚠️ Performance | ⚠️ Performance |
| Local LLM (llama.cpp) | ✅ | ✅ | ✅ | ⚠️ Limited | ⚠️ Limited |
| Cloud STT/LLM | ✅ | ✅ | ✅ | ✅ | ✅ |
| GPU detection | ✅ nvidia-smi + WMI | ✅ IOKit | ✅ sysfs | ✅ Auto | ✅ Auto |
| Auto-update | ✅ MSIX/NSIS | ✅ Sparkle | ✅ AppImage | Play Store | App Store |
| Autostart | ✅ Registry | ✅ launchd | ✅ XDG | N/A | N/A |
| Single instance | ✅ | ✅ | ✅ | N/A | N/A |

### Platform-Specific Code Rules

1. **Flutter platform channels** for all OS-specific features. Define a common Dart interface, implement per-platform in native code (Kotlin/Swift/C++).

2. **Graceful degradation**: If a feature is not available on a platform (e.g., floating button on iOS), hide it from the UI entirely — never show a broken/disabled feature.

3. **Test on ALL platforms**: CI must build and test on Windows, macOS, and Linux. Mobile builds verified per release.

### GPU Detection Cross-Platform

| Platform | NVIDIA | AMD | Intel |
|----------|--------|-----|-------|
| Windows | `nvidia-smi` + registry | WMI + registry | WMI + registry |
| macOS | `nvidia-smi` (rare) | IOKit `SPDisplaysDataType` | IOKit |
| Linux | `nvidia-smi` + `/proc/driver/nvidia/` | `/sys/class/drm/card*/device/vendor` | sysfs |
| Android | Auto (Vulkan preferred) | Auto | Auto |
| iOS | N/A (Metal only) | N/A | N/A |

Flutter implements detection per platform in `lib/services/hardware_info_service.dart`.

### AI Inference Binary Selection (Desktop Only)

| GPU Vendor | STT Binary | LLM Binary |
|------------|-----------|------------|
| NVIDIA (CUDA) | `cublas-12` | `cuda-12` |
| AMD/Intel (Vulkan) | `vulkan` | `vulkan` |
| CPU fallback | `openblas` / `cpu` | `cpu` |

On mobile: Cloud providers are the default. On-device inference is available but with performance warnings for large models.

## Coding Conventions

### Dart/Flutter Style

- **Formatting**: `dart format` (enforced by CI)
- **Naming**: Follow Dart conventions — `UpperCamelCase` for types, `lowerCamelCase` for members, `snake_case` for files
- **Effective Dart**: Follow all rules from https://dart.dev/effective-dart
- **State management**: Riverpod providers — never use `setState` in feature code (OK for simple widget-local state)
- **Immutability**: Prefer immutable data classes (`@freezed` or manual `copyWith`)
- **Null safety**: Sound null safety everywhere. Never use `!` without a preceding null check or assertion

### Logging

**Flutter (Dart)**:
```dart
// Use a structured logger (e.g., logger package or custom)
logger.d('Detailed operational data: $value');  // Debug
logger.i('User-facing milestone: model loaded'); // Info
logger.w('Recoverable issue: $err');             // Warning
logger.e('Unrecoverable failure: $err');          // Error
```

**Never log API keys, tokens, or credentials.** Log presence only: `key.isNotEmpty`.

### Configuration

Config persists as JSON. Accessed through Riverpod providers in Dart:

```dart
// ✅ Correct — via provider
final apiKey = ref.watch(configProvider.select((c) => c.apiKey));

// ❌ Wrong — direct mutable access
final apiKey = config.apiKey;
config.apiKey = newValue;
```

Config file locations:
- Windows: `%APPDATA%\WhisPaste\config.json`
- macOS: `~/Library/Application Support/WhisPaste/config.json`
- Linux: `~/.config/whispaste/config.json`
- Android: App internal storage
- iOS: App documents directory

### Error Handling

**Dart**:
```dart
// Use Result types or try-catch with specific exceptions
try {
  await sttService.transcribe(audio);
} on SttException catch (e) {
  logger.e('STT failed: $e');
  // Show user-friendly error in UI
} catch (e, stack) {
  logger.e('Unexpected error', error: e, stackTrace: stack);
  crashService.report(e, stack);
}
```

### Widget Architecture

Follow these rules for all Flutter widgets:

1. **Reusable widgets** go in `lib/widgets/` — shared across features
2. **Feature-specific widgets** stay in their feature directory
3. **No business logic in widgets** — use Riverpod providers/notifiers
4. **Composition over inheritance** — prefer small, composable widgets
5. **Use `const` constructors** wherever possible
6. **Keys**: Use `ValueKey` or `ObjectKey` for list items, never index-based keys

### Design System — Design Tokens

Use the theme system — never hardcode colors, spacing, or typography:

```dart
// ✅ Correct
color: Theme.of(context).colorScheme.primary,
padding: EdgeInsets.all(WhisPasteSpacing.md),
borderRadius: BorderRadius.circular(WhisPasteRadius.md),

// ❌ Wrong
color: Color(0xFF0891B2),
padding: EdgeInsets.all(16),
```

### Design Token Values

#### Colors (Dark Theme — Primary)
| Token | Value | Usage |
|-------|-------|-------|
| `background` | `#0B0E14` | Window background |
| `surface` | `#12161F` | Sidebar, content base |
| `surfaceVariant` | `#1A1F2E` | Cards, elevated sections |
| `primary` | `#22D3EE` | Accent (cyan) |
| `onPrimary` | `#0B0E14` | Text on accent |
| `secondary` | `#8B95A8` | Secondary text |
| `error` | `#F87171` | Errors, destructive |
| `outline` | `rgba(255,255,255,0.10)` | Borders |

#### Colors (Light Theme)
| Token | Value | Usage |
|-------|-------|-------|
| `background` | `#F1F5F9` | Window background |
| `surface` | `#FFFFFF` | Content areas |
| `primary` | `#0891B2` | Accent (darker cyan) |

#### Spacing Scale
`4px, 8px, 12px, 16px, 20px, 24px, 32px, 48px`

#### Border Radius
| Token | Value | Usage |
|-------|-------|-------|
| `sm` | `6px` | Buttons, inputs, chips |
| `md` | `10px` | Cards, dialogs |
| `lg` | `14px` | Large cards, modals |
| `full` | `9999px` | Pills, avatars, FAB |

#### Typography Scale
| Level | Size | Weight | Usage |
|-------|------|--------|-------|
| Display | 24px | 700 | Page titles |
| Heading | 18px | 600 | Section headers |
| Subheading | 15px | 600 | Card titles |
| Body | 14px | 400 | Default text |
| Caption | 12px | 400 | Metadata |
| Micro | 11px | 500 | Status chips |

Font: System font stack (Segoe UI / SF Pro / Roboto).

### UI Design DNA — MANDATORY

Every UI decision MUST reflect this design DNA. Read this before writing any widget, page, or component.

#### Product Identity
WhisPaste is NOT a generic SaaS tool or boring productivity app. It must feel like a premium consumer app that users **love** to open. Think: "I WANT to use this" — not "I HAVE to use this."

#### Design Inspirations (blend, don't copy)
| Source | What to take | What NOT to take |
|--------|-------------|-----------------|
| **Steam / Gaming dashboards** | Immersive dark surfaces, warm depth, inviting layout, emotional engagement | Cluttered game library grids, excessive animations |
| **WhatsApp / ChatGPT** | Conversational feel, approachable interactions, modern chat patterns | Messaging-specific patterns (bubbles, typing indicators) that don't apply |
| **Notion** | Clean organization, elegant typography, smart use of whitespace | Cold/corporate feel, over-reliance on plain text |
| **Spotify** | Smooth transitions, premium dark theme, delightful micro-interactions | Music-specific UI patterns |

#### Non-Negotiable Style Rules
1. **NO glow effects** — They look cheap and AI-generated ("AI slop"). Achieve depth through layered shadows, subtle gradients, and clean borders instead.
2. **NO generic SaaS aesthetic** — Flat white cards on grey backgrounds are banned. Every surface should have depth and personality.
3. **NO excessive animations** — Motion serves feedback and comprehension, never decoration. Keep it snappy and purposeful.
4. **Use Lucide icons** — Thin, elegant line icons. Material Icons are too chunky/bold for this brand.
5. **Warm, immersive dark theme** as primary — Light theme available but dark is the hero.
6. **Premium = restraint** — Elegance comes from what you leave out, not what you add.

#### Visual Polish Techniques (REQUIRED for every surface)

These techniques make the difference between "fine" and "premium". Apply them consistently:

1. **Subtle warm gradients** — Never use flat solid colors for large surfaces. The frame (sidebar, title bar, status bar) uses a soft top-to-bottom gradient (`frameGradient`). The content panel uses a warm diagonal gradient (`warmSurfaceGradient`). Both are defined in `colors.dart`.
2. **Hinted glass/frost effects** — Use `WpGlassPanel` or `wpGlassDecoration()` for elevated panels, modals, and overlays. Use `BackdropFilter` with σ ≈ 8–12 and nearly-transparent tints. Glass effects should be *felt*, not *seen* — subtle atmospheric depth, NOT iOS-style heavy blur. Appropriate for: status bar backdrop, modal overlays, floating action panels. NOT for: every card, every section, every container.
3. **Micro-animations on navigation** — Page transitions use fade + slight upward slide (0.015 offset, 300ms easeOutCubic). Sidebar hover pills animate with 120ms easeOut. Active indicator bar slides. These are mandatory, not optional polish.
4. **Hover micro-feedback** — Every interactive element (buttons, nav items, chips, rows) must respond to hover with a subtle background change + cursor change. Transition in 120ms. Never "snap" between states.
5. **Depth through layered surfaces** — Frame (darkest) → Content panel (mid) → Elevated cards (lightest). Each layer is visually distinct. Use warm surface gradients, NOT flat colors.
6. **Sidebar icon sizing** — Icons at 21px in 38×38 pill containers. Not too small (hard to click), not too large (looks clunky). Lucide thin line style reinforces premium feel.
7. **Onboarding awareness** — When building new features, always consider the first-run experience. How does a new user discover this feature? Progressive disclosure > hidden complexity. Plan for onboarding integration from the start.

#### Accessibility Requirements (CI-enforced)

1. **WCAG AA contrast** — All text/background color pairs MUST pass WCAG AA: ≥ 4.5:1 for body text, ≥ 3.0:1 for large text. This is enforced by `test/core/theme/wcag_contrast_test.dart` — it runs in CI and will fail the build if any color token pair fails. When changing colors in `colors.dart`, run this test.
2. **Touch targets** — All interactive elements must have ≥ 44×44 logical pixel hit areas. Small icons get padded containers.
3. **Responsive overflow** — Every page must render without `RenderFlex overflow` errors from 800×600 to 2560×1440. Enforced by `test/core/design/responsive_overflow_test.dart`.
4. **Text overflow** — Use `TextOverflow.ellipsis` on text in constrained `Row` widgets. Wrap flexible text in `Expanded` or `Flexible`.

#### Desktop-Native Scaling

This is a **desktop app**, not a web page or mobile app. Content MUST scale fluidly with the window:

1. **Use `LayoutBuilder`** to adapt layouts to available width. Switch between 2-column and stacked at ~900px.
2. **Use `Flexible`/`Expanded`** — never hardcode widths for content areas (sidebars and fixed panels excepted).
3. **Wrap on narrow** — Stats rows, button groups, and chip bars must wrap or scroll when space is tight.
4. **Test at multiple sizes** — The responsive overflow test covers this, but also visually verify at common breakpoints.
5. **Feel native** — The app should feel like a native desktop application, not a web page in a frame. Content fills space, panels resize, and layout adapts seamlessly.

#### The "Wow" Test
Before shipping any UI change, ask: "Would a user screenshot this and share it because it looks cool?" If the answer is "no" or "it's fine", it's not good enough. Push further.

### UI Layout Philosophy

**NOT everything is a card!** Follow these rules:

**USE cards for**: Discrete, actionable items with clear boundaries
- History entries (transcription results — actionable, deletable)
- Download/model cards (with progress bars, install actions)
- Onboarding/promo banners

**DON'T use cards for**: Flat content on dark surfaces
- Settings sections → flat rows with section headers + subtle dividers
- Status information → inline text/badges
- Lists of options → flat rows with hover highlight
- Navigation → flat sidebar
- Form controls → directly on surface with clear labels
- **Analytics/dashboard sections** → flat panels with section headers, NOT card wrappers around every chart

**Section separation**: Use subtle dividers (`outline` color) or spacing + bold section headers — NOT card wrappers.

## Testing Requirements

### Philosophy

**Test pyramid**: Unit (broad) → Widget (medium) → Integration (narrow). Test critical business logic, AI pipeline, and widget contracts thoroughly. UI layout and cosmetic details are verified through widget tests and manual review.

**Tests gate CI.** `flutter test` MUST pass for a PR to merge. No `continue-on-error`, no skipping, no excuses.

### Test Strategy

| Layer | Scope | Tools | Coverage Target |
|-------|-------|-------|-----------------|
| **Unit** | Pure logic, models, services, providers | `flutter_test`, `mocktail` | Broad — every service, every provider |
| **Widget** | Individual widgets in isolation | `flutter_test`, `makeTestable()` helper | Medium — all shared widgets, feature pages |
| **Integration** | Full app flows, page navigation | `integration_test/`, `patrol` (future) | Narrow — critical user journeys |

### Test Directory Structure

```
test/
  core/
    theme/
      colors_test.dart              — Theme color contract tests
      tokens_test.dart              — Design token value tests
    config/
      config_test.dart              — Config persistence tests
  widgets/
    sidebar_test.dart               — Sidebar navigation tests
    fab_test.dart                   — FAB widget tests
    empty_state_test.dart           — Empty state rendering
    section_test.dart               — Section header + content
    status_bar_test.dart            — Status bar tests
  features/
    settings/
      settings_page_test.dart       — Settings sections + controls
    history/
      history_page_test.dart        — History list + search
    replacements/
      replacements_page_test.dart   — Voice shortcuts CRUD
  fixtures/
    test_helpers.dart               — makeTestable(), shared builders
  widget_test.dart                  — App smoke test
integration_test/
  app_test.dart                     — Full app integration tests
```

### Test Conventions (MANDATORY)

1. **File naming**: `{source_file}_test.dart` — e.g., `sidebar.dart` → `sidebar_test.dart`
2. **File path mirrors lib/**: `lib/core/theme/colors.dart` → `test/core/theme/colors_test.dart`
3. **Mocking**: Use `mocktail` — NOT `mockito`. No codegen mocks.
4. **Shared fixtures**: Reusable test data in `test/fixtures/test_helpers.dart` (DRY)
5. **Standalone execution**: Every test file runs independently: `flutter test test/path/to/file_test.dart`
6. **Descriptive names**: `'Dark theme background is warm slate-blue (#0F1117)'`, NOT `'test1'`
7. **Group related tests**: Use `group('ThemeName', () { ... })` for organization
8. **No generated code tests**: Don't test `.g.dart` or `.freezed.dart` files
9. **Wrap in makeTestable()**: All widget tests use the shared helper for consistent Riverpod + Theme setup

### What MUST Be Tested

**Critical AI pipeline** (regressions here = broken core feature):
- Audio capture initialization and level metering
- STT provider interface compliance (local + cloud)
- LLM provider interface compliance (local + cloud)
- Post-processing preset application
- Dead mic detection guard timing
- Auto-stop on silence detection
- Model download + SHA256 verification

**Data integrity** (regressions here = user data loss):
- History database CRUD, search, tagging (drift)
- Configuration save/load and field marshaling
- Export format generation (TXT, MD, CSV, JSON, DOCX)
- Voice shortcuts CRUD

**Design system contracts** (regressions here = broken theme, inconsistent UI):
- Theme colors defined for both light and dark
- Design tokens (spacing, radius, shadows) have valid values
- Layout constants (sidebar width, app bar height) are sensible
- Glass/gradient tokens exist and produce valid objects

**Hardware detection** (regressions here = wrong binary, GPU not detected):
- GPU vendor identification from device names
- GPU VRAM threshold checks
- Asset key recommendation for STT/LLM binary selection
- Preflight hardware checks

**Provider abstraction** (regressions here = cloud API calls fail):
- Provider interface compliance per provider
- Request/response format validation
- Retry logic with exponential backoff

**Widget contracts** (regressions here = broken navigation, broken layout):
- Sidebar renders correct number of nav items, selection callback fires
- FAB is tappable, shows mic icon
- Empty state renders title + subtitle + optional action
- Section renders header + child content
- Settings page renders all sections

### Testing Patterns

**Flutter — Widget test with makeTestable()**:
```dart
testWidgets('FAB shows mic icon and is tappable', (tester) async {
  var tapped = false;
  await tester.pumpWidget(makeTestable(
    WhisPasteFab(onPressed: () => tapped = true),
  ));
  await tester.tap(find.byType(WhisPasteFab));
  expect(tapped, isTrue);
  expect(find.byIcon(LucideIcons.mic), findsOneWidget);
});
```

**Flutter — Unit test with Riverpod**:
```dart
test('SttService transcribes audio successfully', () async {
  final container = ProviderContainer(overrides: [
    sttProviderProvider.overrideWithValue(MockSttProvider()),
  ]);
  final service = container.read(sttServiceProvider);
  final result = await service.transcribe(testAudio);
  expect(result.text, isNotEmpty);
});
```

**Flutter — Theme contract test**:
```dart
test('Dark and light themes have distinct backgrounds', () {
  final dark = WpColors.dark();
  final light = WpColors.light();
  expect(dark.background, isNot(equals(light.background)));
});
```

### When to Add Tests

- **New feature**: Widget test + unit test for business logic — BEFORE marking done
- **Bug fix**: Regression test that would have caught the bug — MANDATORY
- **New widget**: Widget test verifying rendering + interaction contract
- **New provider**: Interface compliance + request format validation
- **Config field**: Marshal/unmarshal test case
- **Design token changes**: Verify values didn't break contracts

### When Tests Are NOT Required

- Pure styling changes (covered by visual review)
- Documentation changes
- CI/CD workflow changes
- Asset changes (icons, fonts)

### Logging & Monitoring Checklist (New Features)

When implementing new features, ensure:

- [ ] User actions wrapped in `try/catch`
- [ ] `crashService.report(error, stackTrace)` in catch blocks
- [ ] Category set appropriately (e.g., `recording`, `stt`, `history`)
- [ ] Action named specifically (e.g., `save_entry`, not just `save`)
- [ ] Extras include relevant context (IDs, types, states)
- [ ] User-friendly error shown via snackbar/toast
- [ ] `logger.i()` for main actions, `logger.d()` for details
- [ ] Expected exceptions handled gracefully (don't report known-benign errors)

## AI Inference Architecture — CRITICAL

AI inference is WhisPaste's **core value proposition**. This section is the most important for understanding the product.

### STT (Speech-to-Text)

**Local** (Desktop only): whisper.cpp `whisper-server` subprocess
- CUDA and CPU binaries downloaded from `ggml-org/whisper.cpp` GitHub releases
- Vulkan binary built by `build-whisper-server.yml` workflow, hosted in WhisPaste repo under the `whisper-server-latest` release tag
- Asset selection per GPU vendor (CUDA / Vulkan / OpenBLAS)
- Models: Whisper Tiny → Large v3 Turbo (31 MB → 547 MB)
- All models verified via SHA256 before use
- Managed by `SttService` in `lib/services/stt_service.dart`
- Download logic in `lib/services/model_download_service.dart`

**Cloud** (All platforms): Provider-based
- OpenAI Whisper API
- Groq Whisper API
- Deepgram Nova API
- Interface: `SttProvider.transcribe(audio, language, options)`
- Automatic retry with exponential backoff (3 attempts)

**Mobile strategy**: Cloud providers are the default on mobile. On-device inference is experimental and limited to small models.

### LLM (Post-Processing / Nachbearbeitung)

**Local** (Desktop only): llama.cpp `llama-server` subprocess
- Binary downloaded from `ggml-org/llama.cpp` GitHub releases
- Model: Qwen3-1.7B (default, only local model)
- Asset selection: CUDA 12.x (NVIDIA), Vulkan (AMD/Intel), CPU fallback
- Context size: 4096 tokens, thread cap: 12
- 3 presets ONLY: cleanup, concise, translate (no custom presets)

**Cloud** (All platforms): Provider-based
- OpenAI (gpt-4o-mini, gpt-4o)
- Anthropic (claude-haiku, claude-sonnet)
- Gemini (gemini-2.0-flash, gemini-2.5-pro)
- Groq (llama-4-scout)
- Max 2 models per provider in selection dropdown
- Interface: `LlmProvider.chatCompletion(messages, options)`

### GPU Detection Flow

```
Detect() → nvidia-smi (NVIDIA?) → yes: CUDA backend
                                  → no: platform-specific (WMI/IOKit/sysfs)
                                        → AMD/Intel? → yes: Vulkan backend
                                        → no: CPU fallback
```

Results cached — detection runs once per app lifecycle.

### Audio Safety Guard (New in 1.2.0)

**Dead Mic Detection**: After recording starts, monitor audio level for `deadMicTimeout` seconds (default 3). If silence persists (peak < 0.02) → auto-stop + error notification. Once voice detected → disable guard.

**Auto-Stop on Silence**: After speech detected and silence returns for `autoStopSilence` seconds → auto-stop → transcribe. Default: 0 (disabled, opt-in). Configurable: 0=disabled, 2-10s.

### Download Safety

- All model downloads include SHA256 verification against hardcoded manifest
- Server binaries from official GitHub releases only
- Downloads support resume for interrupted transfers
- Progress callbacks update the Flutter UI via streams

### Performance Requirements

- **Audio latency**: < 50ms from capture to level meter display
- **STT latency**: < 2s for local inference on mid-range GPU (Whisper Tiny)
- **LLM latency**: < 3s for local post-processing (Qwen3-1.7B, cleanup preset)
- **UI frame rate**: 60fps minimum, no jank during recording
- **Memory**: < 200MB base app, + model size when loaded
- **Cold start**: < 3s to usable UI (excluding model loading)

## Legal Compliance — GDPR / DSGVO (MANDATORY)

WhisPaste is subject to **German and European law**. Every feature, data flow, and external communication MUST comply with the **EU General Data Protection Regulation (GDPR / DSGVO)** and the **German BDSG (Bundesdatenschutzgesetz)**. This is not aspirational — it is a hard legal requirement.

### Non-Negotiable Rules

1. **Privacy by Design & Default (Art. 25 GDPR)**: Every new feature must be designed with data minimization from the start. Collect only what is strictly necessary. Default settings must be the most privacy-protective option.

2. **No data collection without explicit consent (Art. 6, 7 GDPR)**: Any feature that transmits user data externally (crash reports, analytics, telemetry, cloud API calls) MUST be **opt-in** — disabled by default. The user must give informed, freely given, specific, and unambiguous consent before any data leaves the device.

3. **Transparency (Art. 13, 14 GDPR)**: Whenever data is collected or transmitted, the user must be told **what** data is sent, **where** it goes, **why**, and **how long** it is stored — in clear, non-technical language. Both in German and English.

4. **Data minimization (Art. 5(1)(c) GDPR)**: Never send more data than needed. Crash reports must strip personal data (paths, usernames, API keys). Cloud transcription must send only the audio segment — no metadata, device info, or history.

5. **Right to erasure (Art. 17 GDPR)**: Users must be able to delete their data (history, crash reports, config). Deletion must be real — not soft-delete with hidden retention.

6. **Local-first architecture**: Voice recordings, transcriptions, and history are stored locally by default. No cloud sync without explicit user opt-in. Local AI inference is the default on desktop — cloud providers are optional.

7. **No tracking, no fingerprinting**: No analytics SDKs, no device fingerprinting, no usage tracking. The crash reporter uses a hashed hostname — never a persistent user ID.

8. **Third-party data processors**: When cloud STT/LLM providers process user audio or text, the user must understand that data leaves the device. The UI must clearly indicate when a cloud provider is active vs. local inference.

9. **Secure storage**: API keys and credentials stored locally must have restrictive file permissions (`0600` on desktop). On mobile, use platform secure storage (Keychain/Keystore). Never log, transmit, or expose credentials.

10. **No embedded secrets**: Webhook URLs, credentials, and private endpoints must NEVER be hardcoded in the binary. Public relay URLs are allowed, but secrets must stay server-side only.

### Checklist for Every New Feature

Before implementing any feature that touches user data or external communication:

- [ ] Is it opt-in by default?
- [ ] Is the user informed about what data is collected/sent?
- [ ] Is the data minimized to the absolute minimum?
- [ ] Can the user delete the data?
- [ ] Are i18n strings provided (EN + DE) for all consent/privacy UI?
- [ ] Are credentials/sensitive data excluded from any transmitted payload?
- [ ] Does the feature work fully offline (graceful degradation)?
- [ ] Does it work on ALL target platforms?

**When in doubt, do NOT collect or transmit.** Legal compliance always takes priority over feature convenience.

## Security Considerations

### API Keys & Credentials

- Desktop: Stored in `config.json` with file permission `0600`
- Mobile: Stored in platform secure storage (iOS Keychain / Android Keystore)
- Never logged (not even at debug level) — log presence only: `key.isNotEmpty`
- Never included in error messages
- Never transmitted to unintended endpoints

### Crash Logging & Debugging

- Crash reporting goes through a **Supabase Edge Function relay**, not a direct webhook
- The client ships only the public relay URL. Secrets remain server-side in Supabase
- Check **both** local logs AND Supabase relay when debugging
- Treat crash reports as primary evidence for root-cause analysis

### Network Security

- Local AI servers bind to `127.0.0.1` only — never exposed on network
- HTTP for localhost only (no TLS needed for loopback)
- All external API calls use HTTPS
- Certificate pinning for critical endpoints (optional, future)

### Binary Downloads

- SHA256 verification for all model files
- Server binaries from official GitHub releases only
- No arbitrary code execution from downloaded content

### Platform Security

- **Windows**: Single-instance guard via named mutex, no elevation required
- **macOS**: App Sandbox where possible, Hardened Runtime for notarization
- **Linux**: Standard user permissions, no root required
- **Android**: Scoped storage, runtime permissions
- **iOS**: App Sandbox, no background execution without entitlement

## Git Commit Hygiene

### Git Branching Strategy — Solo Developer (MANDATORY)

WhisPaste uses a **two-branch model** optimized for solo development:

| Branch | Purpose | Who commits |
|--------|---------|-------------|
| `dev` | Active development. ALL work happens here. | Developer + Copilot |
| `main` | Stable releases only. Never commit directly. | Merge from dev only |

**Rules:**
1. **All commits go to `dev`** — never commit directly to `main`.
2. **No feature branches** — no `feature/*`, no `amboss/*`, no temporary branches. The only branches are `dev` and `main`.
3. **No PRs for own work** — Copilot and the developer push directly to `dev`. Never use `gh pr create`. PRs exist only for external contributors.
4. **Release flow**: `git checkout main && git merge dev --no-ff && git tag vX.Y.Z && git push origin main --tags && git checkout dev`
5. **CI runs on both branches** — every push to `dev` and `main` triggers CI.

### Commit Message Format (Conventional Commits)

```
<type>(<scope>): <short description>

<optional body — what and why, not how>

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

### Types
| Type | When to use |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests |
| `style` | Formatting, design tokens, CSS/theme changes (no logic change) |
| `docs` | Documentation only |
| `chore` | CI, build, dependencies, tooling |
| `perf` | Performance improvement |

### Scopes
Use the affected area: `design`, `sidebar`, `settings`, `history`, `recording`, `stt`, `llm`, `ffi`, `ci`, `i18n`, `theme`, etc.

### Rules (MANDATORY)

1. **Atomic commits**: Each commit does ONE thing. Don't mix test additions with feature changes.
2. **Tests with features**: When adding a feature that has testable logic, include tests in the same commit or immediately after.
3. **Run tests before commit**: `flutter test` must pass before every commit. No committing broken tests.
4. **Run analyze before commit**: `flutter analyze` must show 0 issues before every commit.
5. **No WIP commits on main**: Main is the release branch — only merge complete, tested work from dev. All development happens on dev.
6. **Meaningful descriptions**: `"fix stuff"` or `"update"` are not acceptable. Describe WHAT changed and WHY.
7. **Co-authored-by trailer**: Always include the Copilot co-author trailer.

### Pre-Commit Checklist

Before every commit:
- [ ] `flutter analyze` — 0 issues
- [ ] `flutter test` — all pass
- [ ] Commit message follows conventional format
- [ ] No secrets in staged files

## CI/CD Pipeline

### CI (`ci.yml`) — Runs on every push to dev and main

1. **Flutter**: `flutter analyze` + `flutter test` + `flutter build` (Windows, macOS, Linux)
2. **Secret scan**: grep for API key patterns (`sk-`, `AKIA`, `ghp_`, `password=`)
3. Upload artifacts (14-day retention)

### Release (`release.yml`) — Triggered by `v*` tags

1. Version validation: git tag must match `AppVersion` in source
2. Build Flutter apps (Windows MSIX, macOS DMG, Linux AppImage, Android AAB, iOS IPA)
3. SHA256 checksum generation
4. GitHub Release creation with all artifacts

### Security Scanning

- **CodeQL**: Automated on push + weekly schedule (Dart)
- **Secret scan**: Regex patterns in CI
- **flutter analyze**: Static analysis with all rules enabled
- **DevSkim + gitleaks**: Multi-language security scanning

## Localization (i18n)

**Supported languages**: English (en), German (de)

**Storage**: ARB files in `lib/core/l10n/` (Flutter standard)

**Key namespaces**:
- `app.*` — App metadata (name, description)
- `tray.*` — System tray menu items
- `settings.*` — Settings UI labels
- `error.*` — Error messages
- `state.*` — Recording state labels
- `preflight.*` — Hardware compatibility messages
- `recording.*` — Recording guard messages

**Adding new strings**:
1. Add key to both `app_en.arb` and `app_de.arb`
2. Run `flutter gen-l10n` to generate Dart code
3. Use in Dart: `AppLocalizations.of(context).keyName`

**Rules**:
- Every user-visible string must be localized (both EN + DE)
- Use du-Form (informal "you") in German translations
- Keep translations concise — mobile space is limited
- Technical terms may stay in English if commonly used (e.g., "API Key", "GPU")
- Feature name: **"Post-Processing"** (EN) / **"Nachbearbeitung"** (DE) — never "Smart Mode" or "Text Refinement" in user-facing text

## Competitor Awareness

When implementing new features or optimizing existing ones, research how leading voice-to-text and productivity tools solve similar problems. Look at their approaches for inspiration — particularly around:

- Cross-platform binary management and GPU acceleration
- Audio pipeline reliability and format handling
- Privacy-first local inference with cloud fallback
- Meeting detection and context-aware dictation
- History management with search and organization
- Mobile dictation UX patterns

**Rules**:
- Never reference competitors by name in code, comments, or documentation
- Never copy code verbatim — understand the approach, then implement it better
- Always verify that our solution handles edge cases the reference may miss
- Our quality bar is higher: if the reference solution is "good enough," make ours excellent
- Cross-platform consistency: if it works great on one platform, it must work great on ALL platforms
