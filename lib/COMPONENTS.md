# Base components (ticket status)

Reference for the shared `Wp*` base components as they stand on the ticket
branch. Values come from `design-tokens/*.tokens.json` through
`lib/core/theme/generated/wp_tokens.g.dart`; the spec is
`internal-notes` (§3 list/detail,
§4 form elements). Components resolve colours at build time through
`WpColors`, so a theme switch repaints them without a restart.

## Tokens used

| Token | Value | Used by |
|---|---|---|
| `WpRadiusTokens.xs` | 4 px | checkbox, segmented active indicator |
| `WpRadiusTokens.sm` | 8 px | buttons, search field, dropdown, icon button, tabs, text link, tooltip, popup menu |
| `WpRadiusTokens.control` | 10 px | list rows, example box, keycap, banner |
| `WpShellTokens.fieldHeight` | 44 px | search field, icon button |
| `WpShellTokens.controlHeight` | 40 px | dropdown trigger |
| `WpShellTokens.controlHeightSm` | 32 px | dense button |
| `WpShellTokens.focusRingWidth` | 2.5 px | focus ring stroke (app) |
| `WpShellTokens.focusRingGap` | 3 px | focus ring gap (app) |
| `WpLayout.minTouchTarget` | 48 px | standard button |

Colour roles in `WpThemeColors` (light, dark and navy sets) that the
components above read through `WpColors`: `highlight`, `highlightSoft`,
`highlightText` (amber marking), `shadow` (floating surfaces), plus
`surfaceMutedFill` for sunken panels.

Helper: `wpDialogBarrierColor()` (`lib/core/theme/colors.dart`) is the flat
scrim behind every dialog barrier. Dialogs use no backdrop blur (no glass).

## Components

| Component | File | State |
|---|---|---|
| `WpButton` | `lib/widgets/wp_button.dart` | 8 px radius, 48 px standard / 32 px dense, border `borderDefault` on the accent tone, palette read per build. |
| `WpIconButton` | `lib/widgets/wp_icon_button.dart` | 44 px outlined square, 8 px radius, tooltip and label, focus ring. `danger` uses the error role, `loading` shows a spinner and blocks taps. Never primary. |
| `WpFavouriteStar` | `lib/widgets/wp_favourite_star.dart` | 44 px hit area, 20 px star. Off: outline `textMuted`. On: filled `highlight` with `highlightText` stroke. |
| `WpSearchField` | `lib/widgets/wp_search_field.dart` | 44 px height, 8 px radius, `borderDefault` edge, palette read per build. |
| `WpTextField` | `lib/widgets/wp_text_field.dart` | `borderDefault` edge, palette read per build (fixed a frozen-palette bug on theme switch). |
| `WpListTileSurface` | `lib/widgets/wp_list_tile_surface.dart` | Panel rows (spec §3): rest flat with a `borderSubtle` rule at the text start, padding 16/14, hover is a fill without a border, selected is a white `surfaceElevated` card with a `borderDefault` edge, 10 px radius and the soft `shadow` lift. Every state paints the same border width, so the label does not move. Card rows (snippets, replacements) still rest as cards and cannot be selected (asserted). |
| `WpDropdown` | `lib/widgets/wp_dropdown.dart` | 40 px trigger, 8 px radius, palette read per build. |
| `WpSegmentedSelector` | `lib/widgets/wp_segmented_selector.dart` | Active segment `accentSubtle` with `accent` text. No caller yet. |
| `WpAccentBadge` | `lib/widgets/wp_accent_badge.dart` | Tones `accent` (imported, interactive) and `highlight` (suggestions, amber). |
| `WpFilterChip` | `lib/widgets/wp_filter_chip.dart` | Already on roles only (resting, hover, selected, count). Unchanged in ticket. |
| `WpTriggerChip` | `lib/widgets/trigger_chip.dart` | Value pill on accent roles. Unchanged in ticket. |
| `WpToast` | `lib/widgets/toast.dart` | Floating surface, `shadow` role, labelled focusable close button. Optional `body:` widget replaces the icon and message line; the body gets its own line and the buttons sit below it. |
| Dialogs (`showWpDialog`, `showWpConfirmDialog`, `showWpChoiceDialog`, `showWpFormDialog` + `WpFormDialogShell`) | `lib/widgets/dialog.dart` | One card for all: floating surface, `cardEdgeHighlight` rim, elevated shadow, 420 px (760 px `wide`), flat scrim. One footer for all, see "Dialogs" below. |
| `WpEmptyState` | `lib/widgets/empty_state.dart` | Icon disc `accentSubtle` with a `borderSubtle` ring; primary action only where the area has one. |
| `WpDiscoverabilityHint` | `lib/widgets/wp_discoverability_hint.dart` | Body text (13 px) in `textMuted`. |
| Tooltip and popup menu | `lib/core/theme/theme.dart` | Floating surface, rim, label role text with the explicit UI font. |
| `WpTextLink` | `lib/widgets/wp_text_link.dart` | Accent text, optional leading icon, underline on hover, focus ring. Disabled: `textMuted`. |
| `WpExampleBox` | `lib/widgets/wp_example_box.dart` | `surfaceMutedFill`, 10 px radius, overline, amber (`highlight`) marker on the leading edge. |
| `WpKeycap` | `lib/widgets/wp_keycap.dart` | Page variant: `surface` with `borderDefault` rim, 10 px radius. `WpKeycap.dock`: `WpColorsDark` frost (`cardFill`) on the navy stage with a 30 % frost rim (`frostBorder30`), 10 px radius. |
| Dock popup (Mehr, output, microphone, Smart Mode, language and speech-recognition dropdowns) | `lib/widgets/recording_dock_controls.dart` (`showWpDockMenu`) | One shared popup: navy `card` one step above the dock surface, `borderDefault` outline, `WpRadius.sm` corners, elevation 8, 280 px wide. It opens above the dock with a 8 px gap, aligned to its trigger. Overline group headers; status rows are non-interactive info rows. Focus starts on the checked or first entry; Escape closes. Each dropdown is a `WpDockChoiceSet` (options, current value, `onChanged`) that writes the same settings as Settings; picking an option closes the popup. In Mehr the dropdowns are submenus that expand in place with the same entries; a footer link opens the matching Settings row. A locked set (speech recognition) is disabled while a dictation records or transcribes. |
| `WpStatusDot` | `lib/widgets/wp_status_dot.dart` | 8 px circle; tones ready (accent), success (green, dock ready state only, allowlisted), busy (warning), error, idle (`textMuted`). Decorative unless `semanticsLabel` is set. |
| `WpBanner` | `lib/widgets/wp_banner.dart` | Tones info (accent), warning (amber soft fill, `highlightText` icon, 4.5:1 gated), error (red); each a tinted fill with a rim from the roles, optional action. No success tone: green is earned, see open items. |
| `WpErrorNotice` | `lib/widgets/wp_error_notice.dart` | Error notice with a cause line and a next-step line (separate texts), optional trailing action. Error red, same tokens as `WpBanner` error tone. Used as the body of recording error toasts via `WpToast.show(body:)` (missing model, denied microphone, failed transcription) and of the GPU-to-CPU fallback toast. |
| `WpTabs` | `lib/widgets/wp_tabs.dart` | Text tabs, selected accent with a 2 px underline over a 1 px `borderSubtle` rule. Left/Right move focus (mirrored under RTL, wrapping), Home/End jump to the ends; Enter/Space select. Selected state in semantics. |
| `WpPageHeader` | `lib/widgets/wp_page_header.dart` | Bricolage page title (28 px, bold) as a heading, optional trailing action slot (the 44 px outlined `WpIconButton`). Not applied to pages yet (ticket). |
| `WpRowDivider` | `lib/widgets/wp_row_divider.dart` | The 1 px subtle line between two rows of a card or list; `inset` starts it under the row text. Replaces the private dividers of the first steps and the Übersicht. |
| Switch | `lib/core/theme/theme.dart` (`switchTheme`) | Track `accent` when on, `borderDefault` when off; white thumb. |
| Checkbox | `lib/core/theme/theme.dart` (`checkboxTheme`), `lib/widgets/wp_row_checkbox.dart` | 20 px box inside a 24 px slot, 4 px corners, 1.5 px `borderDefault` side. |

## Dialogs

Every dialog is one of four shapes on the same card and the same footer. No
dialog builds its own card, barrier or footer buttons; native alerts remain
only where the OS must speak (macOS permission and restart alerts).

| Shape | Helper | Use for |
|---|---|---|
| Confirm | `showWpConfirmDialog` | Yes or no on one action. `destructive: true` when it deletes, resets or overwrites. Both labels are required, named after the action ("Delete", not "OK"). |
| Choice | `showWpChoiceDialog` | Three or more named answers, exactly one recommended. |
| Info / content | `showWpDialog` | A body to read or pick from (licence, shortcuts, a list), one closing action or a few. |
| Form | `showWpFormDialog` + `WpFormDialogShell` | Fields or a selection with state; the subtitle says what the input does. |

The footer is laid out by `WpDialogAction.role`, never by the caller:

- **Roles.** `primary` (filled cyan, the recommendation), `deliberate` (looks
  like `primary`, for an answer given on purpose: consent, sharing data,
  sending text into another app), `destructive`
  (filled red), `alternative` (outlined grey), `cancel` (way out),
  `destructiveExit` (quiet red label, e.g. quit). At most one main action
  (`primary`, `deliberate` or `destructive`).
- **Row or stack.** A main action with Cancel is one row, Cancel first, both
  the same width; Cancel is outlined there so both boxes weigh the same and
  only colour marks the recommendation. If either label does not fit half the
  card (long translation, large text) the pair stacks. Every other set stacks
  at full width: main action on top, alternatives below, exits as quiet labels
  at the bottom with a larger gap. A lone action sits at the end of the row.
- **Keyboard.** No footer button is focused when the dialog opens, so no
  focus ring greets a mouse user. Enter triggers a `primary` main action while
  no control in the dialog holds focus; it never triggers `deliberate` or
  `destructive`. Esc
  and a tap outside cancel (the caller's dismiss value). Tab walks the footer
  in visual order.
- **Colour.** The main action is cyan everywhere, except over the first-run
  setup, whose own main action is the amber hero button: dialogs raised there
  pass `cta: WpDialogCta.hero` and continue that colour.
- **Ids.** Every action carries a `testId` (`<screen>-<element>`), which is
  also its key. Confirm dialogs use `confirm-dialog-confirm` and
  `confirm-dialog-cancel`.

## Deviations from the spec

- **Panel rows rest flat (spec §3).** Only the selected row is a card. Card
  rows (snippets, replacements) still rest as cards; flattening them is a
  separate decision, see open items.
- **Selected list row lifts with the soft `shadow` role.** Spec §3 asks for
  it. The depth guard (`test/core/design/depth_source_test.dart`) still forbids
  shadows on content-plane rows, and carries one narrow exemption: the
  surface file may paint exactly one shadow, inside `selectedLift`, and that
  lift is the selected state only. Resting and hovered rows stay shadow-free.
- **Checkbox is 20 px.** Material's checkbox size is not themeable, so the
  18 px Material box is scaled to 20 px inside the 24 px slot.
- **Focus ring uses the app values** (2 px solid outline, 3 px gap, no blur,
  UIA-VIS-12). The website's 2 px token matches it. One source per surface.
- **No `surfaceSunken` role.** The example box uses `surfaceMutedFill`, the
  nearest existing sunken tint.
- **Banner colours are not in the spec.** Info uses `accentSubtle`, warning
  the amber `highlightSoft` fill with `highlightText` (amber marks notices and
  hints; the warning text reaches 4.5:1 as a design requirement, judged by visual
  review, not by a test since 2026-10-30), error `errorActiveFill`.
- **Learned replacements badge is amber** (`highlight` tone): it marks an
  app suggestion to check, not an action.
- **Loud-action rule retired for list toolbars.** The outlined add icon is
  never primary. Populated lists and History's empty state carry no loud
  action; empty states with their own call to action keep the primary button.
- **Neighbour buttons beside the search field are 44 px icon buttons** in
  notes, replacements, snippets and history. Pinned by
  a design requirement (Teststrategie 2026-10-30: geometry is judged by visual review,
  not by a test).

## Open items

- **Dock ready dot is green, allowlisted.** `WpStatusDot` has one `success`
  tone, allowlisted in `test/core/design/earned_green_test.dart` with the reason
  "dock ready state, successor of the status bar". No other dot paints green.
  The dock itself (ticket) must use this tone for its ready state.
- **Card rows still rest as cards.** Snippets and replacements use the card
  variant, whose resting plate contradicts spec §3's flat list row. Decision
  needed: flatten the card variant too (touches two refreshed screens) or keep
  it as a deliberate card list.
- **WpPageHeader is not applied to any page.** The 44 px "+" slot exists, but
  pages adopt `WpPageHeader` in ticket.
- Hover look of chips and tabs is judged visually. Keyboard focus and keyboard operation are behaviour and stay covered by widget tests.

## Tests

- `test/widgets/wp_components_spec_test.dart`: token values, switch and
  checkbox themes, button palette following `WpColors.activate`.
- Contrast of the role pairs (WCAG AA, light, dark, navy) is a design
  requirement since 2026-10-30. `test/core/theme/wp_component_contrast_test.dart`
  is a render-contrast gate and is to be deleted, not adapted.
- `test/widgets/wp_icon_button_test.dart`, `wp_text_link_test.dart`,
  `wp_example_box_test.dart`, `wp_status_dot_test.dart`, `wp_banner_test.dart`,
  `wp_tabs_test.dart` (incl. arrow keys and RTL), `wp_keycap_test.dart`,
  `wp_page_header_test.dart`, `wp_banner_test.dart` (warning tone): behaviour,
  semantics and roles. The label-position and flat-row checks in
  `wp_list_tile_selected_test.dart` are design tests and are to be deleted
  (Teststrategie 2026-10-30).
- Teststrategie 2026-10-30: no golden, screenshot, layout, overflow or text-scale
  tests. Visual states are judged by visual review. Store screenshots are a
  generator outside the suite: `generators/store/store_screenshots_test.dart`
  (run per path with `--update-goldens` before a store release).
- Palettes of `WpButton`, `WpSearchField`, `WpTextField` and `WpDropdown` are
  built per call, not held in `static final` fields, so a theme switch takes
  effect at the next build.
