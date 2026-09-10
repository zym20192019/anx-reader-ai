# AI Workspace Agent MVP Implementation Plan

> **For Hermes:** Execute on `feature/workspace-agent`; keep Chat Completions + client-side tool loop.

**Goal:** Turn the existing Agent-capable AI page into a clearly scoped central “AI Workspace / AI 问书吧” with a read-only workspace overview tool and explicit confirmation metadata for mutating plan tools.

**Architecture:** Reuse the existing LangChain Chat Completions agent loop. Add one aggregate, read-only tool that summarizes local books, recent reading history, and notes by calling existing repositories. Mark plan-producing tools as confirmation-required in the registry metadata, and expose workspace mode only from the home AI entry so in-reading chat remains unchanged.

**Tech Stack:** Flutter/Dart, LangChain Chat Completions tools, existing SQLite DAOs/repositories, Flutter ARB localization.

---

### Task 1: Add a pure workspace overview model/formatter

**Files:**
- Create: `lib/service/ai/tools/models/workspace_overview.dart`
- Test: `test/service/ai/workspace_overview_test.dart`

Implement JSON-safe value objects and bounded input normalization without touching the database. Test default limits, clamping, and serialization shape.

### Task 2: Add the aggregate read-only workspace tool

**Files:**
- Create: `lib/service/ai/tools/workspace_overview_tool.dart`
- Modify: `lib/service/ai/tools/ai_tool_registry.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh-CN.arb`

Use existing `BooksRepository`, `NotesRepository`, and `ReadingHistoryRepository`; return explicit scope, counts available from local data, recent books, recent reading records, and recent notes. Register it as `workspace_overview`, and keep it read-only.

### Task 3: Make confirmation requirements explicit in Agent metadata

**Files:**
- Modify: `lib/service/ai/tools/ai_tool_registry.dart`
- Modify: `lib/service/ai/langchain_registry.dart`

Add `requiresUserConfirmation` metadata to tool definitions. Mark `bookshelf_organize` and `apply_book_tags` as confirmation-required, and include the rule in the generated system prompt. Do not change the existing plan/apply behavior.

### Task 4: Give the central AI entry a workspace identity

**Files:**
- Modify: `lib/widgets/ai/ai_chat_stream.dart`
- Modify: `lib/page/home_page/ai_page.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh-CN.arb`

Add an opt-in `workspaceMode` to `AiChatStream`; use it only from `AiPage` to show a workspace title and workspace-oriented starter prompts. Existing reading-page chat keeps its current behavior.

### Task 5: Verify and document

Run Flutter formatting, `flutter analyze`, targeted tests, and the full test suite if a Flutter SDK is available. If the environment lacks Flutter/Dart, report that blocker honestly and still run repository-safe checks (`git diff --check`, source inspection). Commit only the feature implementation after verification; do not push without an explicit request.
