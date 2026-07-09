# Pixel Art Gallery

A macOS/iOS SwiftUI app that imports images, pixelates them into variants at custom target dimensions, organizes them in a persistent gallery (SwiftData), and exports or sends variants to Flaschen Taschen (FT) network displays discovered via mDNS. The app target is `PixelArtGallery`; nearly all logic lives in the local Swift package `PixelArtGalleryKit`. Issues here track the work needed to bring the build up to the MVP defined in `PRD.md`, plus any bugs found along the way.

This file is the local guide for managing issues in this project. The companion Mac app (Issues.app) watches the `issues/` folder and renders the current state. Markdown files (and `project.json`) are the source of truth — there is no generated artifact or index to keep in sync.

The `# Pixel Art Gallery` heading above matches the `name` field in `issues/project.json`, which is the canonical source for the project's identity (name + repo URL).

## Status values

| File value | Display name | Meaning |
|---|---|---|
| `open` | Open | Filed but not yet started |
| `in-progress` | In Progress | Actively being worked on |
| `resolved` | Resolved | Work is done and independently verified; awaiting user confirmation |
| `closed` | Closed | User has confirmed the fix |
| `wontfix` | Won't Fix | Acknowledged but won't be addressed |

Use the **file value** (lowercase, hyphenated) in the issue's metadata table.

## Critical rule: never close without explicit confirmation

An issue must **never** be marked `resolved`, `closed`, or `wontfix` based on inference — only when the user says so in plain language. When in doubt, leave it `open`/`in-progress` and ask.

The one deliberate exception: the **review subagent** (Opus, phase 3 of the standard workflow) may set `resolved` after it independently re-verifies the fix. The implementation subagent never sets `resolved` — it leaves the issue `in-progress` for review. No subagent ever sets `closed`; that's the user's transition after they confirm the fix in the Mac app. This separation is the entire reason `resolved` and `closed` are different states.

## The standard workflow (plan → implement → review)

Issues move from filed to resolved through a **three-phase pipeline**. Each phase runs in a **fresh subagent** dispatched by the orchestrator (the main session), on the model that fits the work. The orchestrator picks the issue, dispatches, and records usage — it never does the plan/fix/review work in its own context.

| Phase | When | Model | The subagent does | Status after |
|---|---|---|---|---|
| **1. Planning** | at issue creation | **Fable** (top model) | reads conventions + issue + code, writes `## Plan`; no code | `open` |
| **2. Implementation** | when the issue is worked | **Sonnet** | follows the plan, fixes, builds + verifies, code commit, drafts resolution sections | `in-progress` |
| **3. Review** | after implementation returns | **Opus** | independently re-verifies the diff, then approves or bounces | `resolved` or `open` |

Fresh context per phase is deliberate: each subagent reloads this guide and `CLAUDE.md` cleanly, so edits to those files take effect on the next dispatch. The top model runs *only* in a subagent, never in the orchestrator's own context, to keep its large context isolated. Issues are worked one at a time, in ascending order.

### Phase 1 — Planning (Fable), at issue creation

Planning runs as part of filing a new issue, not when work later starts. Once `issues/NNNN.md` exists with the user's report, dispatch a fresh Fable subagent that reads this guide, `CLAUDE.md`, the new issue, and the relevant code, then writes a `## Plan` section into `issues/NNNN.md` (after `## Description`). A good plan states the suspected root cause, the files/functions likely involved, the approach in a few steps, and how the fix should be verified. It writes no code and leaves status at `open` — a planned issue is a normal open issue with a head start. Record the planner's usage in `## Work log`. (Skip planning if the user is just jotting a quick note.)

### Phase 2 — Implementation (Sonnet): claim → fix → build → commit

A subagent starts with fresh context, so its first job is loading the project's conventions.

1. **Orient**, every time, in order: **`issues/Issues.md`** (this file — authoritative for issue-tracking workflow), **`CLAUDE.md`** at the repo root if present (binding code/repo conventions), then **`issues/NNNN.md`** in full, **including its `## Plan`** and any attachments in `issues/NNNN/`. If the two guides disagree, prefer `CLAUDE.md` for code conventions and this file for issue-tracking specifics.
2. **Set status to `in-progress`** in the markdown — working copy only, no commit.
3. **Make the code changes** required to fix the bug, following the `## Plan`. If you deviate, note why in `## Fix` so the reviewer understands.
4. **Build *and* run the project's verification command, and confirm tests actually executed and passed.** Mandatory; cannot be shortcutted. Compilation is not verification — a green build with zero tests run is a failure of this step. If you wrote or modified tests, execute those specific tests and observe them pass. Read the output, not just the exit code ("0 tests run" / "no tests found" are red flags at exit code 0; `xcodebuild` reports success when no tests ran). If verification can't run in your environment, you have not verified the fix — bail per "When the subagent can't finish", naming the step you couldn't run. If the build was already failing before you started, note it and bail — don't fix unrelated breakage.
5. **Make the code commit.** Stage *only the code changes* (not the issue markdown yet). Message: `#NNNN <verb> <title>` (the verb that fits — `Fix`, `Add`, `Refactor`, `Update`, `Remove`, …), a blank line, then a paragraph of detail.
6. **Capture the commit hash** with `git rev-parse --short HEAD`.
7. **Draft the resolution sections in the markdown — but do NOT set `resolved`.** Leave **Status** at `in-progress`; add a `**Commit**` row with the short hash; add these sections, all *after* `## Description`: `## Root cause` (what was actually wrong), `## Fix` (approach taken; call out plan divergences), `## Verification` (exact command(s) run and what you observed — name new tests and confirm they ran), `## Files changed` (one bullet per file), and optionally `## Gotchas`.
8. **Do not commit the markdown draft.** Return to the orchestrator with a one-line summary. The reviewer makes the single resolution commit in phase 3.

### Phase 3 — Review (Opus): verify → resolve or bounce

An independent Opus reviewer is the gate between "code landed" and "issue resolved". It owns the `resolved` transition.

1. **Orient** the same way (this file, `CLAUDE.md`, `issues/NNNN.md` including the `## Plan` and drafted resolution sections).
2. **Inspect the code commit** — read its diff (`git show <hash>`). Does it address the reported bug? Right scope? Any correctness, security, or regression risk?
3. **Re-run the verification command yourself** and read the output — don't trust the drafted `## Verification`. Confirm tests actually executed and passed. This independent run is the core of the review.
4. **Decide:**
   - **Approve** (fix correct, verification passed): set **Status** to `resolved`; add a `**Closed**` row with today's date; ensure the `**Commit**` row is present; add a `## Resolution notes` blockquote at the top of the resolution sections (`> 🟢 Resolved YYYY-MM-DD — <one sentence>.`). Make the resolution commit: stage `issues/NNNN.md`, message `#NNNN Resolve: <title>`, body noting the code commit hash.
   - **Bounce** (verification failed, fix wrong, scope off): revert **Status** to `open`; add a `## Review notes` section stating exactly what failed and what the next implementation pass must fix. Leave the code commit in place unless you say otherwise. Commit the markdown with `#NNNN Review: <reason>`. The orchestrator re-dispatches phase 2.

**Never set `closed`** — the user does that after verifying the fix. Bails from any phase land back at `open`.

### When the subagent can't finish

If the bug is unreproducible, out of scope, or the build won't pass after reasonable effort: discard/stash any partial code changes, revert status to `open`, add a `## Notes` section describing what was tried and what you'd try next, and commit the markdown with `#NNNN Notes: <one-line bail summary>`. Never use `wontfix` or `closed` to escape a stuck issue — those are the user's decisions.

## Git tracking

`issues/` is **tracked** in this repo, so each lifecycle event produces its own commit:

| Event | What's committed | Commit message |
|---|---|---|
| File a new issue | the new `NNNN.md` | `#NNNN <issue title>` |
| Planning adds `## Plan` | markdown (the `## Plan` section) | folded into `#NNNN <issue title>` if it lands first, else `#NNNN Plan` |
| Implementation — code commit | code changes only | `#NNNN <verb> <title>` |
| Review — resolution commit | markdown (status `resolved` + Closed + Commit + summary), made by the Opus reviewer | `#NNNN Resolve: <title>` |
| Review — bounce to open | markdown (status back to `open` + `## Review notes`) | `#NNNN Review: <reason>` |
| Bail with notes | markdown only | `#NNNN Notes: <brief>` |
| Work-log row appended | markdown only | `#NNNN Work log: <model>, <total tokens>, $<cost>` |
| Daily pricing refresh | `model-pricing.json` only | `Update model pricing` |
| User-confirmed close | markdown only | `#NNNN Close` |
| Won't fix | markdown only | `#NNNN Won't fix` |

**Working-copy-only (no commit):** setting status to `in-progress` at the start of work — transient; the resolve commits supersede it. Committing every status flip would create noise.

**Why two commits to resolve, not one:** the `**Commit**` metadata row records the hash of the code-fix commit, which isn't known until *after* that commit lands. Splitting resolution into a code commit and a resolution commit keeps each single-purpose ("fix the code", "document the fix") and lets the resolution commit reference the hash cleanly.

## Token usage and cost tracking

Every subagent dispatch gets a usage record on the issue it worked, written by the **orchestrator** after the subagent returns (a subagent can't measure its own totals). Each issue accumulates a row per phase — **planning (Fable) at filing time, implementation (Sonnet), review (Opus)** — plus a row for every bounce or bail.

- **Pricing cache** — `issues/model-pricing.json` caches Anthropic's per-MTok prices (`fetched` date, `models` map). Refresh once per day: if `fetched` isn't today, fetch current prices and rewrite it, committing as `Update model pricing`. If the fetch fails, use the stale cache and note the staleness; with no cache, record tokens with `—` for cost.
- **Exact token counts** — Claude Code writes each subagent's transcript to `~/.claude/projects/<project-slug>/<session-id>/subagents/agent-<id>.jsonl`. Assistant lines carry `message.usage` and `message.model`. **Dedupe by `requestId`** (one response can span several lines) and sum. Cost = `(input×in + output×out + cache_read×read + cache_write×write_5m) / 1,000,000`.
- **The `## Work log` section** — conventionally the last section of the issue file (always after `## Description`), one row per session with an optional **Phase** column (`plan` / `implement` / `review`):

  ```markdown
  ## Work log

  | Date | Phase | Model | Input | Output | Cache read | Cache write | Cost |
  |---|---|---|---|---|---|---|---|
  | 2026-07-08 | plan | claude-fable-5 | 84 | 6,102 | 512,400 | 41,200 | $0.58 |
  | 2026-07-08 | implement | claude-sonnet-5 | 120 | 18,530 | 2,904,110 | 98,400 | $1.12 |
  | 2026-07-08 | review | claude-opus-4-8 | 96 | 9,240 | 1,331,200 | 44,800 | $1.05 |

  **Total: $2.75**
  ```

  Update the `**Total**` line whenever a row is appended. Don't reformat existing rows.

## Build / verify command for this project

- **Package (unit tests):** `cd PixelArtGalleryKit && swift test`
- **App, macOS:** `xcodebuild -project PixelArtGallery.xcodeproj -scheme PixelArtGallery -destination 'platform=macOS' build`
- **App, iOS Simulator:** `xcodebuild -project PixelArtGallery.xcodeproj -scheme PixelArtGallery -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

A fix is only verified when the relevant command actually runs and tests/build pass — compilation alone is not verification. The app is multiplatform (iOS 18 / macOS 15); verify both platforms when a change touches platform-conditional code.

**Release:** the end-to-end release checklist is `scripts/RELEASE.md` (Sparkle key/appcast details in `scripts/SPARKLE.md`); the v1.0.0 go/no-go gate is `Ship-v1.md` at the repo root. Preflight everything with `scripts/preflight.sh`. Notarization submissions and website deploys are user-run steps.

## Module conventions for this project

Use these canonical area names in the **Module** row:

- `App` — the `PixelArtGallery` app target (entry point, `ContentView`, `ModelContainer` setup)
- `Models` — SwiftData `@Model` types (`GalleryItem`, `Variant`, `FlaschenTaschenDisplay`)
- `Persistence` — `FileStorageManager` and SwiftData container/context wiring
- `ImageProcessing` — `PixelationEngine`, `PixelGrid`, `PixelColor`
- `ViewModels` — `GalleryCoordinator`, `PixelGridViewModel`
- `UI` — SwiftUI views in `PixelArtGalleryKit/Sources/PixelArtGalleryKit/UI`
- `Networking` — FT display mDNS discovery and the send client
- `Export` — variant exporters (PNG / HEIC / PPM / JSON) and Photos integration
- `Build` — project/build configuration, release pipeline scripts, signing/notarization
- `Website` — the static site (`website/`): landing page, changelog, appcast, downloads
- `Docs` — release documentation, checklists, project docs

## Issue format

Each issue is `NNNN.md` (4-digit zero-padded). Title separator is an em-dash (`—`). Metadata field names stay `**bold**`. Dates are `YYYY-MM-DD`. `Module` may list several separated by ` / `. `Platform` is `iOS`, `macOS`, or `All`. For feature-gap / task issues, a Description (plus Notes pointing at the relevant code) is enough — Steps/Expected/Actual are optional. Under the standard workflow a planned issue also carries a `## Plan` section (after `## Description`); resolution adds `## Root cause` / `## Fix` / `## Verification` / `## Files changed`, and a `## Work log` as the last section.
