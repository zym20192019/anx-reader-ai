# Anx Reader AI UI-only Redesign Implementation Plan

> **For Hermes:** Implement this plan task-by-task. Keep all business logic and state flows unchanged.

**Goal:** Refresh Anx Reader AI's visual language and responsive presentation without changing reading, library, sync, AI, database, navigation behavior, or platform logic.

**Architecture:** Preserve the current page/state architecture and existing callback APIs. Add a small, reusable visual token layer and refactor shared presentation widgets first, then update the bookshelf, reading overlays, and settings surfaces. Page files may be edited only where widget composition or visual properties change; provider/DAO/service/model behavior remains frozen.

**Tech Stack:** Flutter 3.35.3, Material 3, FlexColorScheme, existing `FilledContainer`/settings widgets, existing `Prefs` theme settings, Source Han Serif for reading-oriented typography.

---

## Non-negotiable scope boundary

### Allowed

- Theme tokens, `ThemeData` component themes, colors, typography, spacing, radii, elevation, borders, hover/focus states.
- Widget composition and layout constraints that do not change data flow.
- Visual treatment of existing navigation rail/bottom bar while preserving the current destinations and callbacks.
- Visual treatment of existing bookshelf filters, search affordance, sort/import/sync actions, book cards, folder cards, empty/loading/error states, and drag overlay.
- Visual treatment of reading toolbars, dialogs, sheets, TOC, notes, style controls, and AI panel chrome while preserving their current actions and state ownership.
- Accessibility labels, tooltips, semantic ordering, and hit-target sizing where no behavior changes.

### Forbidden unless separately approved

- Changes to `lib/providers/`, `lib/dao/`, `lib/service/`, `lib/models/`, `lib/enums/`.
- Changes to EPUB/WebView rendering, CFI/progress calculations, page-turn behavior, annotations, sync, AI tools, TTS, database schema, file import, or platform channels.
- Changes to route destinations, navigation identifiers, `Prefs` keys/default semantics, localization keys, generated files, or platform runner code.
- New runtime dependencies or replacement of existing business widgets with a different state-management approach.
- Copying a third-party product's exact layout, branding, or proprietary interaction model.

### Change-control rule

For mixed UI/logic files, keep callback bodies, provider reads/writes, navigation calls, and asynchronous operations byte-for-byte unchanged where possible. A visual refactor must be reviewable as a presentation diff, not a behavioral rewrite. If a layout change appears to require changing behavior, stop and report it instead of widening scope.

---

## Design direction

### Primary concept: paper editorial library

An original reading-focused visual language combining a calm paper-like canvas with a compact, metadata-rich library. It should feel more like a well-organized reading desk than a generic dashboard.

- Light-first, warm-neutral surfaces; retain the user's existing light/dark/e-ink choices.
- Keep `Prefs().themeColor` as the user-controlled accent source; do not hard-code a competing brand palette.
- Use Source Han Serif selectively for book titles, reading context, and editorial emphasis; use the existing system/UI font for controls and dense metadata.
- Replace arbitrary decoration with hierarchy: surface contrast, type weight, spacing, and progress indicators should carry meaning.
- Prefer compact information density in the library and generous line length/readability in the reader.
- Use restrained motion only for existing state transitions; do not add animations that delay actions.

### Reference principles, not clones

- Flutter adaptive guidance: layout adapts to available space and interaction mode, not only to device names.
- Material 3: keep one primary navigation component per breakpoint; preserve the current compact bottom navigation and medium/large rail transformation.
- Apple typography guidance: use a coherent text hierarchy, maintain legibility at larger text sizes, and minimize destructive truncation.
- Readwise Reader: separate library triage/filtering from long-form reading controls; make appearance controls easy to reach while reading.
- KOReader: keep reading controls task-focused and make e-ink/reading adjustments explicit.
- Kavita: expose useful metadata and filtering without turning every surface into a decorative card grid.

Sources:

- https://docs.flutter.dev/ui/adaptive-responsive
- https://m3.material.io/foundations/layout/breakpoints/overview
- https://m3.material.io/components/navigation-rail/guidelines
- https://developer.apple.com/design/human-interface-guidelines/typography
- https://docs.readwise.io/reader/docs/faqs/appearance
- https://koreader.rocks/user_guide/
- https://github.com/Kareadita/Kavita/releases/tag/v0.8.3

---

## Phase 0: Establish a UI-only baseline

**Files:**

- Modify only UI files after this baseline is recorded.
- Do not modify `lib/providers/`, `lib/dao/`, `lib/service/`, `lib/models/`, or platform directories.

**Checks:**

```bash
git status --short --branch
git diff --check
git diff --name-only main...HEAD
```

Expected: branch is `ui/redesign`, clean before implementation, and based on the released `1.0.4` commit.

Create a scope check for every implementation batch:

```bash
git diff --name-only main...HEAD
```

Review any file outside the approved UI allowlist before committing. Do not silently widen the allowlist.

---

## Phase 1: Add reusable visual tokens without changing behavior

**Files:**

- Create: `lib/theme/anx_ui_tokens.dart`
- Modify: `lib/utils/color_scheme.dart`
- Test/verify: existing static checks and cloud Flutter build

**Objective:** Centralize presentation values so later widget refactors do not repeat ad-hoc radii, padding, shadows, and text styles.

**Rules:**

- Tokens must derive from the existing `ColorScheme` and `Prefs` values where applicable.
- Keep light, dark, and e-ink modes functional exactly as before.
- Do not change theme mode persistence or preference names.
- Add component themes only for visual defaults: cards, chips, inputs, dialogs, sheets, navigation, tooltips, and progress indicators.
- Keep contrast readable and avoid large gradients, excessive blur, or decorative icon containers.

**Verification:**

- Parse/format changed Dart files.
- Run the independent identity check and existing repository static gates.
- Confirm the diff contains no provider/service/DAO/model changes.

**Commit:** `style: establish reader ui tokens`

---

## Phase 2: Refactor shared presentation widgets

**Files:**

- Modify: `lib/widgets/common/container/base_rounded_container.dart`
- Modify: `lib/widgets/common/container/filled_container.dart`
- Modify: `lib/widgets/common/container/outlined_container.dart`
- Modify: `lib/widgets/bookshelf/book_cover.dart`
- Modify: `lib/widgets/bookshelf/book_item.dart`
- Modify: `lib/widgets/settings/settings_tile.dart`
- Modify: `lib/widgets/settings/settings_section.dart`

**Objective:** Make shared surfaces visually coherent so every page improves without changing callers.

**Preserve exactly:**

- `BookItem` tap, long-press, secondary-click, sync-status provider read, and `pushToReadingPage` call.
- `BookCover` file/default-cover selection and existing preference-controlled title/author display.
- Settings tile constructors, switch values, navigation callbacks, and descriptions.
- E-ink fallback from filled to outlined containers.

**Visual changes:**

- Consistent radius and surface hierarchy.
- Better book-cover edge treatment and progress/metadata alignment.
- Compact but readable settings rows with clear hover/focus/pressed states.
- Minimum 44dp touch targets where practical without changing row semantics.
- Remove unnecessary shadows and replace them with restrained elevation/border contrast.

**Verification:**

- Compile/analyze through the cloud workflow because Flutter/Dart are unavailable locally.
- Manually inspect Android/Web/Windows artifacts if the build is available.
- Confirm only presentation code changed in these files.

**Commit:** `style: refine shared reader surfaces`

---

## Phase 3: Redesign the home shell and bookshelf presentation

**Files:**

- Modify: `lib/page/home_page.dart` only for visual styling of existing rail/bar.
- Modify: `lib/page/home_page/bookshelf_page.dart` only for widget presentation.
- Modify: `lib/widgets/bookshelf/book_folder.dart`
- Modify: `lib/widgets/bookshelf/book_opened_folder.dart`
- Modify: `lib/widgets/bookshelf/sync_button.dart`
- Modify: `lib/widgets/common/tag_chip.dart`
- Modify: `lib/widgets/hint/hint_banner.dart`

**Objective:** Turn the bookshelf into the primary library surface: clear search, compact filters, strong cover rhythm, useful metadata, and obvious reading progress.

**Preserve exactly:**

- Existing `_currentTab`, page list, `onBottomTap`, navigation identifiers, and AI sheet behavior.
- Existing `bookListProvider`, tag/status filters, sorting, importing, sync, drag-and-drop folder creation, and empty/loading/error states.
- Existing breakpoint behavior: compact uses the bottom bar; medium/large uses the rail. Do not show both as primary navigation at once.
- Existing `Prefs` values for cover width, folder style, auto-hide bar, and theme mode.

**Visual changes:**

- Make the search affordance read as a page-level command without changing its route.
- Treat filters as a compact control strip with selected-state clarity.
- Improve grid rhythm, cover framing, title/author hierarchy, and progress visibility.
- Give folders a clear visual distinction without inventing new folder behavior.
- Improve drag-over feedback while keeping the current `DropTarget` callbacks untouched.
- Style the desktop rail as a quiet persistent library spine; style compact navigation as a stable bottom action bar.

**Commit:** `style: redesign bookshelf presentation`

---

## Phase 4: Refine reading chrome only

**Files:**

- Modify: `lib/widgets/reading_page/style_widget.dart`
- Modify: `lib/widgets/reading_page/toc_widget.dart`
- Modify: `lib/widgets/reading_page/notes_widget.dart`
- Modify: `lib/widgets/reading_page/progress_widget.dart`
- Modify: `lib/widgets/reading_page/tts_widget.dart`
- Modify: `lib/widgets/reading_page/tts_fab.dart`
- Modify: `lib/widgets/reading_page/more_settings/more_settings.dart`
- Modify: `lib/widgets/reading_page/more_settings/reading_settings.dart`
- Modify: `lib/widgets/reading_page/more_settings/style_settings.dart`
- Modify: `lib/widgets/reading_page/more_settings/other_settings.dart`
- Modify: `lib/widgets/reading_page/widgets/book_toc.dart`
- Modify: `lib/widgets/reading_page/widgets/bookmark.dart`

**Objective:** Make the reader chrome disappear when reading and become precise when summoned.

**Preserve exactly:**

- Page-turn, CFI, reading-progress, note, bookmark, TTS, AI, and sync calls.
- Existing `ReadingPageState`, `EpubPlayer`, WebView, and reading lifecycle behavior.
- Existing preference keys and settings values.

**Visual changes:**

- Use a calm reading canvas with a restrained toolbar hierarchy.
- Group appearance controls by task: reading, style, other; preserve current tab structure.
- Improve sheet/dialog width, spacing, section headers, sliders, segmented buttons, and selected states.
- Make progress and TOC navigation glanceable without competing with book text.
- Keep long-form reading controls reachable but unobtrusive.

**Commit:** `style: refine reading controls`

---

## Phase 5: Consolidate settings and dialogs

**Files:**

- Modify: `lib/page/home_page/settings_page.dart` only for presentation.
- Modify: `lib/page/settings_page/appearance.dart`
- Modify: `lib/widgets/settings/settings_app_bar.dart`
- Modify: `lib/widgets/settings/settings_title.dart`
- Modify: `lib/widgets/settings/theme_mode.dart`
- Modify: `lib/widgets/settings/about.dart`
- Modify: `lib/widgets/settings/webdav_switch.dart`
- Modify: relevant settings subpage widgets only for visual presentation.

**Objective:** Make settings scannable and consistent while keeping every preference and navigation action intact.

**Visual changes:**

- Use clear section hierarchy and consistent setting-row density.
- Make switches, navigation rows, current values, and destructive/advanced actions visually distinct.
- Keep the current user preference controls, including light/dark/e-ink/theme color/language/cover settings.
- Avoid introducing a new settings navigation architecture in this pass.

**Commit:** `style: polish settings surfaces`

---

## Verification gates for every phase

1. `git diff --check` passes.
2. Changed-file list stays inside the UI allowlist.
3. No provider, DAO, service, model, enum, generated localization, WebView, or platform files changed.
4. Existing callback bodies and state ownership remain unchanged.
5. Dart formatting/static checks pass in GitHub Actions; local Flutter/Dart absence is reported honestly.
6. For desktop-facing batches, run the existing targeted Windows workflow rather than the full release matrix.
7. After the first integrated UI batch, manually test on the generated Windows artifact:
   - open/close window;
   - navigate all existing home destinations;
   - search/import/sort/filter books;
   - open a book and verify reading controls;
   - open settings and toggle representative appearance options.
8. Only after visual review and behavior verification should the UI branch be merged or tagged for release.

## Rollback strategy

Each phase is a separate commit. Revert the latest style commit if a visual regression appears; do not reset or delete the branch, the released `1.0.4` tag, or the original `/root/anx-reader` repository.
