# WhisPaste Design System

## Design Identity
Premium consumer app feel — emotionally engaging, visually impressive. Inspired by Steam/gaming dashboards + WhatsApp/ChatGPT conversational UI.

### Non-Negotiables
1. NO glow/neon effects — cheap "AI slop" aesthetic
2. NO flat SaaS cards — every surface needs depth + personality
3. NO excessive animations — snappy + purposeful
4. Use Lucide icons — Material Icons are too chunky
5. Warm dark theme PRIMARY — light secondary
6. Premium = restraint — elegance from what you leave out

## Colors (Dark Theme — WpColorsDark)
| Token | Value | Usage |
|-------|-------|-------|
| background | `#131826` | Window |
| surface | `#171D2C` | Sidebar |
| surfaceElevated | `#1D2538` | Panels |
| surfaceVariant | `#232C40` | Cards |
| accent | `#38D9F0` | Accent (cyan) |
| textPrimary | `#F0F4FA` | Primary text |
| textSecondary | `#ABB8CC` | Secondary |
| textMuted | `#8A99B2` | Muted |
| error | `#FF7B7B` | Errors |
| success | `#36D98B` | Success |
| warning | `#F5C842` | Warnings |
| borderSubtle | `rgba(255,255,255,0.12)` | Barely visible |
| borderDefault | `rgba(255,255,255,0.19)` | Structural |

## Spacing (WpSpacing)
xxs=4, xs=8, sm=12, md=16, lg=20, xl=24, xxl=32, xxxl=48

## Border Radius (WpRadius)
sm=6px, md=10px, lg=14px, xl=18px, full=9999px

## Animation Timing (WpMotion)
| Transition | Duration |
|------------|----------|
| Hover enter | 0ms (instant) |
| Hover exit | 80ms |
| Page navigation | 300ms |
| Detail panel | 300ms |
| View mode switch | 200ms |
| Filter chip toggle | 120ms |
| Toast/notification | 300ms |

## Visual Techniques
- Warm surface gradients on all large surfaces (not flat)
- Glass effects: `BackdropFilter` σ=8–12 + nearly-transparent tint
- Micro-animations: every state transition (not optional)
- Layered surfaces: darkest frame → mid content → lightest cards
- Sidebar: 21px Lucide icons in 38×38 pill containers

## Accessibility
- WCAG AA: 4.5:1 body text, 3:1 large text — enforced by test
- Touch targets ≥ 48×48px (Material 3 standard)
- Responsive: 320px → 2560px without overflow
- Use `TextOverflow.ellipsis` in constrained Rows

## Layout Rules
- NOT everything is a card — flat sections for settings/analytics
- Cards for: history entries, download items, onboarding prompts
- No collapsible/accordion sections in settings
- Mobile-first: design 320px first, enhance for desktop

## The "Wow" Test
"Would a user screenshot and share this?" If not, push further.
