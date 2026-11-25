# Base components

Reference for the shared `Wp*` base components. Values come from `design-tokens/*.tokens.json` through
`lib/core/theme/generated/wp_tokens.g.dart`. Components resolve colours at build time through
`WpColors`, so a theme switch repaints them without a restart.

## Tokens used

| Token | Value | Used by |
|---|---|---|
| `WpRadiusTokens.xs` | 4 px | checkbox, segmented active indicator |
| `WpRadiusTokens.sm` | 8 px | buttons, search field, dropdown, icon button, tabs, text link, tooltip, popup menu |
| `WpRadiusTokens.control` | 8 px | list rows, example box, keycap, banner |
| `WpLayout.controlHeight` (`WpShellTokens.controlHeight`) | 48 px | form field, search field, dropdown trigger, standard button, icon button, favourite star: one height, so controls sharing a line are flush (UX-131) |
| `WpShellTokens.controlHeightSm` | 32 px | dense button |
| `WpShellTokens.focusRingWidth` | 2.5 px | focus ring stroke (app) |
| `WpShellTokens.focusRingGap` | 3 px | focus ring gap (app) |
| `WpLayout.minTouchTarget` | 48 px | standard button |
| `WpShellTokens.readingMeasure` | 720 px | `WpReadingWidth`: the one reading measure for prose and free-text forms (feedback form, transcript); pages never pick a width of their own (#197) |
| `WpTypography` (generated) | caption 11, small 12, body 13, subheading 14, row-title 15, heading 16, title 17, headline 22, display 28 | the one type scale from `type` in `app.tokens.json` (#197); dock labels 11/500 in normal case, values 13/600, main action 15/600 |

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
| `WpIconButton` | `lib/widgets/wp_icon_button.dart` | 44 px outlined square (`extent`, beside the search field), 8 px radius, tooltip and label, focus ring. `danger` uses the error role, `loading` shows a spinner and blocks taps, `selected` marks a toggle (select mode). Every icon control of a collection toolbar uses this variant, never the ghost (#1498). Never primary. |
| `WpCollectionPage` / `WpCollectionToolbar` | `lib/widgets/wp_collection_page.dart` | Frame and one-row head of Recordings, Notes, Snippets (`internal-notes`): search, marks, filter, status, tools (or `toolsOverflow` below 880 px), `addActions` (Recordings: `history-import-add`), `primaryAction`. Add and new actions never collapse. |
| `WpCollectionListPane` / `WpListFocusReveal` | `lib/widgets/wp_collection_list_pane.dart` | The one left column of Recordings (list and dense mode), Notes and Snippets (#1498): page inset on both sides (rows line up with the toolbar), xs top, xxl bottom, xs gap under each item (`rowGap: 0` only in the dense mode), a `WpCopyAnchor` per row (`<prefix>-<id>`), scroll offset kept per `storageKey`, and the keyboard cursor's row kept on screen (`WpListFocusReveal`, also for rows not yet built). Rows are `WpCollectionHeaderRow` (date, favourites, "other notes") or `WpCollectionItemRow`; the feature builds only the tile. Fixed areas, switched on per page: `leading` only for a tool that scrolls with the rows (the audio import of Recordings), `placeholder` for loading (`WpListSkeleton`), error, empty and no matches (`WpEmptyState`). A page's explanation (what it is for, the trash retention, a link to its settings) lives in the empty state's hint and footer, never as text above the rows, so every list starts right under the search. |
| `WpCollectionSplit` | `lib/widgets/wp_collection_split.dart` | The one list/detail frame of Recordings, Notes, Snippets and Replacements (#1498): list 340 px (min 240, at most 0.65 of the width), draggable 8 px divider with a 1 px line, detail from 280 px; below that the open item takes the whole pane. Closed without a selection (no right-hand empty state), crossfade between items (`crossFadeDetail: false` for the note editor), `detailOnly` for the writing focus. The feature passes `selectedItem`, `idOf`, `listBuilder` and `detailBuilder` only. |
| `WpFavouriteStar` | `lib/widgets/wp_favourite_star.dart` | The one favourite toggle of every list (#1498), built on `WpRowAction`: dense 28 px in item rows (recordings, notes, snippets, via `WpListItemActions`), 48 px in the dictionary; `WpFavouriteStar.head` is the same star in every editor head (recording detail, note, snippet detail) as the 32 px compact ghost of its `WpHeadActions` neighbours, with an optional key hint in the tooltip. Off: Lucide outline `textMuted`. On: solid star `pinnedAccent`. Name states the press: `historyPinToTop` / `historyUnpin` (`WpFavouriteStar.labelFor`, also used by context menus); reported as a toggle in rows and heads. |
| `WpListItemContent` / `WpListItemTypeGlyph` / `WpListItemActions` / `WpListItemStarMark` / `WpListItemMeta` | `lib/widgets/wp_list_item_content.dart` | The one row layout for recordings, notes and snippets (#1498): card surface, muted type glyph (`WpListItemTypeGlyph`, also the recordings card and the recording detail head, which no longer paint a coloured avatar), title with the dense actions right-aligned at its end, preview only when it differs from the title, one ellipsized meta line (`WpListItemMeta.segments` drops missing facts, no empty slot between separators), footer. `WpListItemActions` fixes the revealed set and order: Copy, Star, Delete (trash: Copy, Restore, Delete forever), shown on hover, keyboard cursor or the open row. While hidden, a favourite shows the resting `WpListItemStarMark` after the title. Title priority as in `WpEditorHead`: the marks after the title (badges, star, quick-note bolt) show only while the title keeps `titleMinShare` (0.6) of the title line, and drop out from the last one instead of cutting the title short. Duplicate and setting the quick-note mark live in the context menu and as screen-reader actions. |
| `WpRowAction` / `WpRowActions` | `lib/widgets/wp_row_action.dart` | Row icon actions, revealed on hover or focus with reserved height. Dense (28 px) in item rows, 48 px in replacements. Item rows reveal Copy, Star, Delete together (`WpListItemActions`); the only permanently visible action is the notes quick-note mark. |
| `WpSearchField` | `lib/widgets/wp_search_field.dart` | 48 px height, 8 px radius, `borderDefault` edge, palette read per build. |
| `WpTextField` | `lib/widgets/wp_text_field.dart` | `form`/`embedded`: at least 48 px (`WpLayout.controlHeight`), text centred; `borderDefault` edge, palette read per build (fixed a frozen-palette bug on theme switch). `heading`/`passage`/`bare` (editor title and writing surfaces): unfilled, no edge at rest, the focus ring only while focused (#1498); read-only titles and `WpTextFieldSurface` use `headingContentPadding`/the same variant so read and edit mode do not shift. |
| `WpCollectionListItem` / `WpCollectionListItemTitle` / `WpCollectionListItemPreview` | `lib/widgets/wp_collection_list_item.dart` | The one item row of the collection lists (#1498), on `WpListTileSurface` (card) and `WpListItemContent`. Owns hover and focus state, when the actions show (hover, keyboard focus, arrow cursor, open item; `revealActions: false` in multi-select), the resting star mark of a favourite, the meta tint (muted at rest, secondary on any tinted state, handed to the `meta` builder), title and preview styles, right-click through `showWpContextMenu`, optional own focus with Enter/Space and Delete/Backspace, and the row semantics. `isHighlighted` draws the focus look only (a just-saved snippet) without revealing actions or tinting the meta. Recordings, notes and snippets (main, draft and trash rows) pass only data and slots. |
| `WpContextMenuEntry` / `showWpContextMenu` | `lib/widgets/wp_context_menu.dart` | The one right-click menu of a list row (#1498): same floating surface and radius as the editor head's … menu, one `WpMenuRow` per entry (icon, regular weight), destructive entries last after a divider in the error colour. Entry keys follow `<screen>-<action>-<id>`. |
| `WpEditorHead` / `WpHeadActions` / `WpHeadMenuButton` / `WpMenuRow` | `lib/widgets/wp_head_actions.dart` | The one editor head of note, recording detail, snippet editor and the snippet trash view (#1498): 52 px (`padding` 24/8/17/4 plus `rowExtent` 40; the right inset is 24 minus `closeOverhang` 7, the room between the 32 px slot and the 18 px close glyph, so the X ends on the page toolbar's right edge in all three editors), slots `leading` (unused by the three editors since #1498: no leading mark, the note's quick-note bolt sits in the pane's meta row), `title` (heading field or read-only title), `meta` (short muted text after the title, the recording's time: shown only while it fits whole and the title keeps `titleMinShare` 60 % of the row, otherwise dropped, the list row shows the same time), `actions`, `below`. Actions in fixed order: copy, star, the object's own action, the … menu (`WpMenuRow` entries, destructive last after a divider), close. |
| `WpEditorPane` / `WpEditorPaneBody` | `lib/widgets/wp_editor_pane.dart` | The one right-hand side of Recordings, Notes and Snippets (detail and editor) (#1498), fixed slots in fixed order: `head` (a `WpEditorHead`, no leading mark), full-width `notices` (notice slot, undo row, source links), optional `meta` (chips, retention notice, quick-note bolt with hotkey line, usage and fields, draft/save banners; `metaGap` 12), `editor` (always one `WpTextEditor`, which draws the 24 page inset itself), `extras` below (`extrasGap` 12: the recording's edit bar, original transcript and annotations; snippet warnings and the field list), optional fixed `footer` (`footerPadding` 24/12/24/16). Owns every inset: 24 at the sides on the search bar's line, 8 below the head, 24 at the end (0 above a footer). `bodyMode`: `fill` (note, snippet detail, static snippet: the surface reaches the status line) or `scroll` (recording, interactive snippet form). No own scroll frames, paddings or reading-width caps in the panels. Snippets edit in place like notes (#1498): no edit, save or discard button and no footer, a debounced autosave (`SnippetEditor.autosaveDelay`, Ctrl/Cmd+S at once, closing stores a pending valid state) writes only valid states; an invalid one shows `snippets-editor-invalid` in `notices`, with `snippets-editor-revert` back to the stored state. Head actions as in the note: copy, star, delete, … (duplicate), close. Keyboard focus puts the caret at the text end, a click keeps it where clicked. Recordings edit the same way (#1498): the transcript is written directly, no edit, save or cancel button; a debounced autosave and Ctrl/Cmd+S write it, the draft status sits in `WpTextEditor.status` (first in the status line), and one editing session (focus or first typing until focus loss, entry switch or close) is exactly one version while the original stays as the baseline version. The read view (`SnippetDetailPanel`) is left only for the trash. |
| `WpTextEditor` | `lib/widgets/wp_text_editor.dart` | The one text editor (#638, #1498) of transcript, note and snippet (detail and editor): tool row (`WpMarkdownToolbar` with undo/redo, on, off via `showToolbar` or disabled while read-only; tags in `toolbarTrailing`), the writing surface, a status line with the save status (`saveStatus`, a `ValueListenable<WpSaveStatus>` drawn by `WpSaveStatusLabel` from `lib/widgets/wp_save_status.dart`: saving, saved, failed, invalid; idle shows nothing; id `<testId>-save-status`, key `<testId>-save-status-<state>`), word count, reading time and the Ctrl/Cmd+S save hint (only with `onSave`, and only while the status is idle: the status replaces it). All three pages feed the same states: Recordings from the draft autosave, Notes from `NoteAutosave`, Snippets from the editor's validity check (invalid = not saved). Ctrl/Cmd+S sets saved as soon as the write is through. Always pads itself with the page inset (24), so tool row, surface and status line share one left and right edge on every page. Read-only (`editable: false`) is a state of the same surface: `readView` (a `WpTextFieldSurface` of the same variant) and `readText` for the counts. The long note edits one paragraph at a time inside one `WpTextFieldSurface` (`focused: true` while any paragraph has focus), so the focus contour frames the whole surface, never the paragraph. |
| `WpListTileSurface` | `lib/widgets/wp_list_tile_surface.dart` | Panel rows (spec §3): rest flat with a `borderSubtle` rule at the text start, padding 16/14, hover is a fill without a border, selected is a white `surfaceElevated` card with a `borderDefault` edge, 10 px radius and the soft `shadow` lift. Every state paints the same border width, so the label does not move. Card rows (recordings, notes, snippets) rest as frost cards with a `borderSubtle` edge; selected swaps the edge for `controlEdge` at the same width. |
| `WpDropdown` | `lib/widgets/wp_dropdown.dart` | 48 px trigger, 8 px radius, palette read per build. |
| `WpControlRow` | `lib/widgets/wp_control_row.dart` | A field with the button or dropdown that acts on it: `WpSpacing.sm` gap, every child stretched to the tallest, so the edges stay shared at larger text sizes. |
| `WpSegmentedSelector` | `lib/widgets/wp_segmented_selector.dart` | Active segment `accentSubtle` with `accent` text. `iconOnly` segments show the icon and name themselves by label as tooltip and accessible name (side panel tabs); `testId` per segment. |
| `WpProviderTile` | `lib/widgets/wp_provider_tile.dart` | Support provider tile in the provider's own `WpBrandTokens` colours with its logo, name and one line; the whole tile is one button named "Support with <provider>", focus ring, `testId` required. Support page only. |
| `WpAccentBadge` | `lib/widgets/wp_accent_badge.dart` | Tones `accent` (imported, interactive) and `highlight` (suggestions, amber). |
| `WpFilterChip` | `lib/widgets/wp_filter_chip.dart` | Already on roles only (resting, hover, selected, count). |
| `WpFilterChipScroller` | `lib/widgets/filter_chip_scroller.dart` | The one chip row: a single line that scrolls sideways, trailing fade as the scroll hint as soon as chips overflow (collection filters, handbook chapters; UX-031/UX-032). |
| `WpPageShell` / `WpReadingWidth` | `lib/widgets/page_shell.dart` | Page frame (inset, scroll owner, sticky header). `WpSearchableListPage` and the collection pages render through it; Help tabs own one scroll view each with the shell inset inside it. `WpReadingWidth` caps prose at `readingMeasure`. |
| `WpEditorText` / `WpEditorTextBody` | `lib/widgets/editor_text_view_scope.dart` | Editor text view (#648): `WpTextEditor` wraps itself in `WpEditorText` (shared text size, line length, line spacing; Ctrl/Cmd +/−/0) and its body in `WpEditorTextBody` (scales only the text, reset chip). `WpTextField`, `WpTextFieldSurface` and the long-note editor read it; nothing else does. |
| `WpTriggerChip` | `lib/widgets/trigger_chip.dart` | Value pill on accent roles. |
| Dialogs (`showWpDialog`, `showWpConfirmDialog`, `showWpChoiceDialog`, `showWpFormDialog` + `WpFormDialogShell`) | `lib/widgets/dialog.dart` | One card for all: floating surface, `cardEdgeHighlight` rim, elevated shadow, 420 px (760 px `wide`), flat scrim. One footer for all, see "Dialogs" below. |
| `WpTagChip` / `WpTagChipRow` | `lib/widgets/wp_tag_chip.dart` | Shared category-tinted tag in recordings, notes and the tag editor (#1757). Compact chips optionally filter on tap; `.editable` adds a localized remove control. The row shows up to three tags and a remaining count. |
| `WpEmptyState` | `lib/widgets/empty_state.dart` | `.panel` is the compact shared empty state for the side panel and snippet picker, without the illustration. Calm static illustration: the base "nothing here yet" state of Recordings, Notes and Snippets passes `motif:` (`WpCutIllustration`, paper-cut SVG from `assets/illustrations/` tinted from `WpColors`, 160 px, #1595, `design-tokens/illustration/STYLE.md` §12); every other state keeps `WpEmptyIllustration` (tinted circle, two cards, icon badge, theme tokens only, so it follows light, dark and Marine) and exactly one first action (`actionTestId` required in practice). Below 400 px pane height (plus the motif's extra 56 px) it drops the illustration so the action stays visible; inside slivers use `SliverFillRemaining(hasScrollBody: true)` (no intrinsics). `WpEmptyState.searchNoMatches(query:, onClear:, testId:)` is the one "search found nothing" state of every list with a search field (#1498): shared title and query-naming hint (`searchNoMatches*`), "Clear search" with the test id `<screen>-search-clear`; never mint page-specific no-match strings. |
| `WpConfirmPop` | `lib/widgets/wp_copy_feedback.dart` | Short paint-only entrance for confirmations at the trigger (copy, insert, duplicate); new key per repeat, direct switch under reduce motion. `confirmAtTrigger` marks a `WpCopyAnchor` target for non-copy actions. |
| `settingsSwitchedOffWhen` | `lib/features/settings/settings_widgets.dart` | Rows that only matter while a parent switch is on: kept at full contrast (helper text 4.5:1) plus a text marker "Switched off", no dimming. |
| `WpDiscoverabilityHint` | `lib/widgets/wp_discoverability_hint.dart` | Body text (13 px) in `textMuted`. |
| Tooltip and popup menu | `lib/core/theme/theme.dart` | Floating surface, rim, label role text with the explicit UI font. |
| `WpTextLink` | `lib/widgets/wp_text_link.dart` | Accent text, optional leading icon, underline on hover, focus ring. Disabled: `textMuted`. |
| `WpExampleBox` | `lib/widgets/wp_example_box.dart` | `surfaceMutedFill`, 10 px radius, overline, amber (`highlight`) marker on the leading edge. |
| `WpKeycap` | `lib/widgets/wp_keycap.dart` | Page variant: `surface` with `borderDefault` rim, 10 px radius. `WpKeycap.onFilled(ink:)`: the only cap inside a filled button (dock and tray panel Diktieren): glyph in the button's ink (`onCta` / `onPrimaryRecord`), face that ink at 18 % over the fill, rim at 50 %, `dimmed` at half strength while the hotkey is off. Never a light cap on a filled button; ink on that face stays ≥ 5.6:1 on amber and cyan fills, hover and pressed included (#1498). |
| Dock popup (Mehr, output, Smart Mode, language and speech-recognition dropdowns) | `lib/widgets/recording_dock_controls.dart` (`showWpDockMenu`) | One shared popup: navy `card` one step above the dock surface, `borderDefault` outline, `WpRadius.sm` corners, elevation 8, 280 px wide. It opens above the dock with a 8 px gap, aligned to its trigger. Overline group headers; status rows are non-interactive info rows. Focus starts on the checked or first entry; Escape closes. Each dropdown is a `WpDockChoiceSet` (options, current value, `onChanged`) that writes the same settings as Settings; picking an option closes the popup. The microphone is chosen only in Mehr, as a submenu labelled with the current device. In Mehr the dropdowns are submenus that expand in place with the same entries; a footer link opens the matching Settings row. A locked set (speech recognition) is disabled while a dictation records or transcribes. |
| `WpStatusDot` | `lib/widgets/wp_status_dot.dart` | 8 px circle; tones ready (accent), success (green, dock ready state only), busy (warning), error, idle (`textMuted`). Decorative unless `semanticsLabel` is set. |
| `WpBanner` | `lib/widgets/wp_banner.dart` | Tones info (accent), warning (amber soft fill, `highlightText` icon, 4.5:1), error (red); each a tinted fill with a rim from the roles, optional action. No success tone: green is earned, see open items. |
| `showWpDictationMessage` / `DictationNotice` | `lib/widgets/dictation_message.dart`, `lib/services/floating_overlay/dictation_notice.dart` | Dictation pipeline messages (paste, recording, model, GPU, recovery) on the overlay card; banner in the main window when the overlay is off. Replaces the classic toast for these cases. |
| `showOverlayPillHint` | `lib/services/floating_overlay/pill_hint.dart` | Short confirmation at the overlay pill for hotkey and tray actions (language, profile); a newer hint replaces the shown or waiting one. Banner in the main window when the overlay is off (#454). |
| `WpErrorNotice` | `lib/widgets/wp_error_notice.dart` | Error notice with a cause line and a next-step line (separate texts), optional trailing action. Error red, same tokens as `WpBanner` error tone. Its cause and next step now reach the user as headline and text of the overlay card (`showWpDictationMessage`, #453). |
| `WpPageNotice` | `lib/widgets/wp_page_notice.dart` | The one page-level notice instead of a toast (recordings, notes, statistics, settings, dictionary, replacements, snippets): `showWpPageNotice(context, page: 'x', notice: WpPageNotice(id, message, nextStep?, tone, area?, action?, autoDismiss?))` plus `WpPageNoticeSlot(page: 'x', area?, openArea?)`. Without `area` below the page head; with `area` only in that entry/section. Errors stay until closed or replaced (the state outlives its slot); short self-closing confirmations do not go here but to the notice bar via `showWpConfirmation` (#1903); announced once via `announce`; testIDs `page-notice-<id>`, `page-notice-dismiss-<page>`. Renders as `WpBanner`. `showWpAppError(context, id:, message:, actionLabel?, onAction?)` puts an error without a page of its own (setting not saved, backup failed, link not opened) in `WpAppErrorSlot` below the head of any page (list of at most 3, same id replaces only itself, testIDs `page-notice-<id>`, `page-notice-dismiss-<id>`); during onboarding the held toast takes it. |
| `WpTabs` | `lib/widgets/wp_tabs.dart` | Text tabs, selected accent with a 2 px underline over a 1 px `borderSubtle` rule. Left/Right move focus (mirrored under RTL, wrapping), Home/End jump to the ends; Enter/Space select. Selected state in semantics. |
| `WpPageHeader` | `lib/widgets/wp_page_header.dart` | Bricolage page title (28 px, bold) as a heading, optional trailing action slot (the 44 px outlined `WpIconButton`). |
| `WpRowDivider` | `lib/widgets/wp_row_divider.dart` | The 1 px subtle line between two rows of a card or list; `inset` starts it under the row text. Replaces the private dividers of the first steps and the Übersicht, and every `Divider(height: 1)` between rows. |
| `WpDividedColumn` | `lib/widgets/wp_row_divider.dart` | The one owner of row rules: one `WpRowDivider` between two rows that have height, none at the edges, none next to a row that builds nothing (#2050). `WpSettingsGroup`, Übersicht rows, first steps, permissions step and the learning log use it; rows never draw their own rule. |
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
  Opt-in `answersInRow` (first-run close question, #1688): the main action
  and its one alternative sit side by side like the pair, cancel and exits
  beneath as quiet labels; the same fit rule stacks them. The row gap is
  `WpSpacing.buttonGap`.
- **Keyboard.** No footer button is focused when the dialog opens, so no
  focus ring greets a mouse user. Enter triggers a `primary` main action while
  no control in the dialog holds focus; it never triggers `deliberate` or
  `destructive`. Esc
  and a tap outside cancel (the caller's dismiss value). Tab walks the footer
  in visual order.
- **Colour.** The main action is cyan everywhere, except over the first-run
  setup, whose own main action is the amber hero button: dialogs raised there
  pass `cta: WpDialogCta.hero` and continue that colour. Their card wears the
  setup's navy as well (`WpFloatingSurface.stageDecoration`), not the indigo
  floating material (#1688).
- **Ids.** Every action carries a `testId` (`<screen>-<element>`), which is
  also its key. Confirm dialogs use `confirm-dialog-confirm` and
  `confirm-dialog-cancel`.

## Deviations from the spec

- **Panel rows rest flat (spec §3).** Only the selected row is a card. Card
  rows (snippets, replacements) still rest as cards; flattening them is a
  separate decision.
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
  review, not by a test), error `errorActiveFill`.
- **Learned replacements badge is amber** (`highlight` tone): it marks an
  app suggestion to check, not an action.
- **Loud-action rule retired for list toolbars.** The outlined add icon is
  never primary. Populated lists carry no loud action; every empty state
  offers exactly one first action as its primary button.
- **Neighbour buttons beside the search field are 44 px icon buttons** in
  notes, replacements, snippets and history. Judged by visual review, not by a test.

