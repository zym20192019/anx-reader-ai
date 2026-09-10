# Independent Anx Reader AI Project Plan

**Goal:** Turn the verified beta.2 snapshot into a separately maintained, AI-first reading application without carrying upstream release and UI assumptions into future work.

## Phase 0 — Repository separation

- Keep `/root/anx-reader` and `zym20192019/anx-reader` unchanged as historical/reference sources.
- Maintain `/root/anx-reader-ai` as the new project.
- Create a new GitHub repository named `anx-reader-ai` when API/repository-creation authorization is available.
- Push the flattened initial commit only after the remote repository is verified.

## Phase 1 — Remove upstream operational coupling

- Replace upstream README links, release links, badges, and store metadata.
- Remove or disable workflows that require upstream signing, SignPath, Apple Match, Telegram notification, or store secrets.
- Create an independent release workflow for cloud artifacts and a separate local iOS signing handoff.
- Preserve license and required attribution.

## Phase 2 — Product identity and platform matrix

- Keep Android package id `com.zym20192019.anxreader`.
- Define independent iOS/macOS/Linux/Windows/Web identities.
- Keep iOS unsigned IPA as the cloud handoff for 全能签 unless the user later configures private Apple signing in CI.
- Verify platform metadata from built artifacts before release.

## Phase 3 — UI redesign foundation

- Establish a new app shell and navigation model.
- Define design tokens, typography, spacing, color roles, responsive breakpoints, and component rules.
- Keep reading engine, data model, sync, and AI tool contracts stable while replacing screens incrementally.
- Avoid broad rewrites until each replacement screen has a working route and regression check.

## Phase 4 — AI Workspace productization

- Make Workspace the primary home destination.
- Add citations/source cards for book, history, and note answers.
- Keep read-only tools default-first.
- Require explicit confirmation before any data mutation.
- Add cross-platform UI tests and tool contract tests.

## Phase 5 — Independent releases

- Publish Android, desktop, web, and iOS handoff artifacts from the new repository.
- Use a new tag namespace and release notes owned by this project.
- Verify every Release asset and platform identity before reporting success.
