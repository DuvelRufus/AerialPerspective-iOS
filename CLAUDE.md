# Sessionskontext

Vid start av varje ny session: orientera dig i vad som hänt sedan sist genom att läsa den senaste git-historiken innan du börjar arbeta.

```bash
git log --oneline -15
git status
```

Detta ger den faktiska, alltid aktuella bilden av:
- Vilka funktioner och fixar som nyligen landat (commit-meddelandena beskriver vad + varför)
- Om det finns ocommittad kod i arbetsträdet som behöver hanteras innan nytt arbete påbörjas

Git-historiken är den enda källan till sanning för vad som ändrats. Det finns medvetet ingen separat NOTES.md eller changelog att hålla synkad, eftersom en sådan blir inaktuell. Commit-meddelandena ÄR loggen.

Om arbetsträdet har ocommittad kod vid sessionsstart: påtala det och fråga om den ska committas innan nytt arbete börjar (se Commit-disciplin nedan).

## Commit-disciplin

- Committa per verifierad feature, inte per session. En commit = en logisk, byggd och verifierad ändring.
- Pusha aldrig på eget initiativ — endast på Dannys uttryckliga begäran (se Push policy nedan).
- Verifiera alltid med `xcodebuild` -> BUILD SUCCEEDED innan commit.
- Commit-meddelanden beskriver vad + varför, inte bara vad.
- Stapla inte orelaterade ändringar i samma commit. Om arbetsträdet har ocommittade ändringar från ett tidigare pass, committa dem separat innan nytt arbete läggs ovanpå.

## Git workflow
- After each change that builds cleanly (BUILD SUCCEEDED), commit it immediately as its own unit before moving to the next change.
- Immediately after committing, run `git log --oneline -1` and show the output to confirm the commit actually landed. Never report a commit as done without this confirmation.
- One logical change per commit. Never combine unrelated changes in a single commit. If the working tree already holds unrelated edits, stop and flag it instead of committing them together.
- Stage explicit file paths (e.g. `git add path/to/File.swift`), never `git add .`, so unrelated changes aren't pulled in.
- Never push proactively — see Push policy below.

## Push policy
- Claude never pushes automatically or proactively: not after a green build,
  not as part of any workflow, not to be helpful. Default is commit-only.
- Claude pushes ONLY when Danny explicitly asks in that instruction
  (e.g. "push", "pusha", "git push"). An explicit request is the sole trigger.
- Danny device-tests on iPhone 14 before asking for a push. Claude does not
  verify testing; Danny's explicit request is his confirmation it is ready.

## Aktuella kända, ej åtgärdade punkter

Håll denna korta lista uppdaterad när vi medvetet skjuter upp något. Ta bort poster när de åtgärdas.

- **OpenActionsStore + HealthOverviewStore kör var sin AssessmentScoresLoader.load på Översikt.** Koden är delad (väg B:s kod-dubblering är stängd via AssessmentScoresLoader), men båda stores anropar loadern separat — projects+assessments+answers hämtas fortfarande två gånger per Översikt-besök. Kvarvarande rest: dela resultatet (en laddning, två konsumenter), inte bara koden.

---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AerealPerspective is a native iOS app (SwiftUI, no UIKit views except haptics/`UIImpactFeedbackGenerator`) for assessing engineering/leadership "projects" across six domains, generating AI insights and a 30/60/90-day plan, and tracking follow-up actions. The UI language is **Swedish** — keep user-facing strings in Swedish.

There is no package manager manifest. This is an Xcode project (`AerealPerspective.xcodeproj`) with dependencies managed by Swift Package Manager (resolved in `project.xcworkspace/.../Package.resolved`). The only third-party dependency is **supabase-swift** (2.46.0).

- Bundle id: `Axiotis.AerealPerspective` · Swift 5.0 · iOS deployment target 26.5
- Scheme/target: `AerealPerspective`

## Build & run

There is no test target. Build/run from Xcode normally, or from the CLI:

```bash
# Build for simulator (generic destination avoids "simulator not installed" errors)
xcodebuild -project AerealPerspective.xcodeproj -scheme AerealPerspective \
  -destination 'generic/platform=iOS Simulator' build

# Open in Xcode
open AerealPerspective.xcodeproj
```

## Backend (Supabase) — important

The app talks directly to a hosted Supabase project via a global client in `SupabaseConfig.swift` (`let supabase = SupabaseClient(...)`, anon key inlined). Tables accessed: `projects`, `assessments`, `questions`, `answer_options`, `answers`, `insights`, `actions`, `plans`/`plan_actions`, plus the `documents` table used by `NoteStore` (`OvrigtView`).

The two AI **edge functions live only in the Supabase dashboard, not in this repo** (there is no `supabase/` directory):
- `generate-insights` → returns `{"insights": [{title, body, risk_level, domain, suggested_action}]}`
- `generate-plan` → returns `{"plan": {summary, day1_30, day31_60, day61_90}}`

They call Claude (Swedish prompts). When backend changes are needed, **print the complete updated function source for the user to paste into the dashboard** — you cannot deploy it from here. Edge functions only *generate and return JSON*; **persistence is client-side** — the Swift app inserts the rows (e.g. `InsightStore.save` writes the returned insights; `EdgeFunctionService` mints fresh UUIDs/`assessmentId` on returned objects which are placeholders until saved).

## Architecture

**Pattern:** `@Observable` `@MainActor` store classes (one per table/concern) own all Supabase I/O; SwiftUI views are passed store instances and call `await store.fetch(...)`/mutators. There is no global app state container — stores are created at the view level where their lifetime belongs and passed down (e.g. `ActionStore` is created once in `ProjectTabView` and shared across the three segments so actions survive segment switches without refetching).

**App flow** (`AerealPerspectiveApp.swift`): privacy-policy gate (`@AppStorage`) → `AuthStore` loading → `AuthView` if signed out → `RootTabView`. `AuthStore` keeps `user` live via `supabase.auth.authStateChanges`. App is forced dark mode throughout.

**Navigation:**
- `RootTabView` — two tabs: Projekt (`ProjectListView`) and Översikt (`OversiktView`).
- `ProjectListView` → `ProjectTabView` (a project) → segmented control over three sections: `AssessmentListView` (Assessments), `PlanView` (Plan — the app's single task surface: plan-linked, insight-created and manual tasks), `OvrigtView` (Övrigt).

**Stores** (all in `AerealPerspective/`, `*Store.swift`): `AuthStore`, `ProjectStore`, `QuestionStore` (fetches `questions` + `answer_options` once at app start), `AssessmentStore` (versioned assessments per project), `AnswerStore` (`[questionId: answerOptionId]` map), `InsightStore`, `ActionStore`.

**Core types** (`Models.swift`): `Domain` (Team/Process/Product/Tech/Stakeholders/Culture — six fixed cases), `Project`, `Assessment` (has `version`; `plan` is JSONB `PlanResult?`), `Question`/`AnswerOption`, `Answer`, `Insight`, `PlanResult`/`PlanPhase`/`PlanAction`. `ProjectAction` lives in `ActionStore.swift`.

**Domain ↔ DB mapping:** All `Codable` structs use explicit `CodingKeys` mapping camelCase Swift to snake_case Postgres columns. Decode defensively — note the deliberate choices: `Insight.domain` is a `String` (not the `Domain` enum) so unexpected DB values don't fail decoding; `PlanAction.id` is optional and `PlanPhase` has a custom decoder to read legacy plans where `actions` was `[String]`. Preserve this tolerance when editing models.

**Scoring** (`ScoringService.swift`): per-domain score = rounded average of answered option scores in that domain (0–100). Levels: `>=66` strong, `>=34` note, else risk. `delta(current:previous:)` compares assessment versions.

**AI generation** (`EdgeFunctionService.swift`): static `generateInsights`/`generatePlan` build a payload of `{domain, question, answerLabel}` triples plus per-domain scores, invoke the edge function, and decode the wrapper. Both log the raw response and wrap `DecodingError` in `EdgeFunctionError`.

**Actions linkage:** A `ProjectAction` can carry `insightId` and/or `planActionId` to trace back to its source. `ActionStore.action(forPlanItem:)` derives a plan item's status from the loaded actions (nil = not started, present & open = in progress, done = done) — this is why stable `PlanAction.id`s matter.

## Conventions

- New store: `@MainActor @Observable class`, expose `var ... = []`, `isLoading`, optional `error`; do Supabase calls in `do/catch` (most stores currently just `print` errors).
- Use the shared global `supabase` client; never construct a new one.
- Styling goes through `DesignSystem.swift` (colors like `Color.apOrange`, `.apBackground`, `.apTextPrimary`, `.apSurface`, `.apHairline`). Don't hardcode colors.
- `ProjectTabView.swift` lives at the repo root (not under `AerealPerspective/`) but is part of the target — unlike the synced `AerealPerspective/` folder it is explicitly referenced in project.pbxproj, so keep it where it is unless re-grouping in Xcode.

## Gotchas / hard-won lessons

- **IDs are UUID throughout** (Insight.id, ProjectAction.id, projectId, assessmentId). Not String. A comparison like `$0.planActionId == item.id` must be UUID == UUID.
- **Edge function model string:** use `claude-sonnet-4-6` in generate-insights and generate-plan. The old `claude-sonnet-4-20250514` is retired and returns 404 (surfaces as a 500 to the app). If AI generation 500s, check this first via the function's Supabase logs.
- **SQL migrations are run manually** by the user in the Supabase SQL editor. Never attempt to apply them from here — print the SQL for the user to run.
- **Edge functions are not in this repo.** Print full updated source for dashboard paste; never assume you can deploy.
- **Verify builds with xcodebuild → BUILD SUCCEEDED before committing.** SourceKit "No such module" errors in the editor are index false-positives if xcodebuild succeeds — trust the build.
- **Never put a haptic/simultaneousGesture modifier on a NavigationLink inside a List** — it blocks navigation. Use Button + ButtonStyle, or put the gesture on the link after `.buttonStyle(.plain)`. This bug has recurred twice.
- **Generate-once rule:** insights and plans are generated once and never regenerated. Regeneration deletes+reinserts rows, breaking `insight_id` and `plan_action_id` links on already-created actions. The generate button only shows on an empty state.
- **Repo lives in `~/Developer`**, not `~/Desktop` (iCloud evacuation causes EPERM).
- **Supabase projects created after 2026-05-30** need explicit GRANT SQL for public schema tables to be reachable by the authenticated role.
- **`Color.` prefix is required in `.foregroundStyle()`** — SwiftUI can't infer custom Color extensions as ShapeStyle without it.
