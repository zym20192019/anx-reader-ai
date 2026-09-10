# TXT to EPUB Paragraph Reconstruction Plan

> **For Hermes:** Implement this plan task-by-task with test-first verification.

**Goal:** Prevent hard-wrapped TXT lines from becoming separate EPUB paragraphs while preserving real paragraph and chapter boundaries, and keep original TXT sources available after import.

**Architecture:** Keep chapter detection and book metadata/database behavior unchanged. Add a pure TXT paragraph reconstruction helper that normalizes line endings, detects only strong fixed-width export patterns, merges soft-wrapped lines inside those documents, and emits stable paragraph separators. Make EPUB XHTML rendering consume paragraph boundaries rather than every physical line. Treat converted EPUB files as temporary import artifacts; never delete the user-selected TXT source.

**Scope:** `lib/service/convert_to_epub/`, `lib/service/prepare_imported_file.dart`, focused import integration in `lib/service/book.dart`, and focused tests only. Do not modify providers, DAO, models, platform directories, or UI behavior.

---

### Task 1: Add failing paragraph reconstruction tests

**Files:**
- Create: `test/service/convert_to_epub/txt/txt_paragraphs_test.dart`
- Create: `lib/service/convert_to_epub/txt/txt_paragraphs.dart`

Cover:
- physical hard wraps within a strong fixed-width export are joined;
- genuine blank-line paragraph boundaries remain separate;
- ordinary one-line paragraphs are not merged;
- chapter headings, dialogue, metadata and divider-like lines are not merged into body text;
- CJK joins do not insert unwanted spaces, while Latin joins remain readable;
- repeated blank lines do not create empty EPUB paragraphs.

### Task 2: Implement the minimal pure paragraph helper

**Files:**
- Modify: `lib/service/convert_to_epub/txt/txt_paragraphs.dart`

Use a stable-width plus repeated-single-blank heuristic. Do not treat indentation alone as proof of hard wrapping: many normal TXT files indent already-separated paragraphs. When the heuristic is not met, preserve ordinary line and blank-line boundaries.

### Task 3: Integrate paragraph boundaries into TXT conversion

**Files:**
- Modify: `lib/service/convert_to_epub/create_epub.dart`

Use the helper on section content and render one `<p>` per reconstructed paragraph, not one `<p>` per physical line. Preserve chapter headings, XML escaping, TOC, metadata, and fallback chunking behavior. Link generated XHTML to the generated stylesheet.

### Task 4: Preserve original TXT imports

**Files:**
- Create: `lib/service/prepare_imported_file.dart`
- Modify: `lib/service/book.dart`
- Create: `test/service/prepare_imported_file_test.dart`

Compute the source MD5 before conversion, convert TXT to a temporary EPUB, await metadata persistence, and only clean up the temporary EPUB after it has been copied into application storage. Never delete the original TXT. Keep existing non-TXT temporary-file cleanup behavior.

### Task 5: Verify scope and regressions

Run focused tests, available static checks, `git diff --check`, and a forbidden-path diff audit. If Flutter/Dart is unavailable locally, report that limitation and use GitHub Actions for real Dart/Flutter verification before calling the change verified.
