# Aerial Perspective

A native iOS app for assessing team health across six domains, built with SwiftUI and Supabase.

The app is both a thesis project and a tool in daily use. It was built to answer a practical question: when you lead several teams at once, which one needs attention first, and why?

## How it works

A project represents a team. For each team you run a versioned assessment: 18 questions across six domains (Team, Process, Product, Tech, Stakeholders, Culture), four calibrated answer options each.

Answers produce a score per domain on a 10 to 90 scale. Scores are rendered as a hexagonal radar chart with three colour bands: 66 and above is strong, 34 to 65 is watch, below 34 is risk.

From there the app calls two Claude-backed edge functions. One generates insights from the answers, the other turns those insights into a 30/60/90 day plan. Plan items become trackable tasks, ordered by the score of the domain they belong to, so the weakest area surfaces first.

A cross-project overview shows every team at once: total score in a ring, weakest domain, and the trend since the previous assessment.

## Stack

- SwiftUI, Swift 5, iOS 26.5 or later
- iPhone and iPad
- Supabase for auth, Postgres and edge functions
- [supabase-swift](https://github.com/supabase/supabase-swift) 2.46.0, the only direct dependency
- 35 Swift files, roughly 8,200 lines

Scoring lives in a single service so that every consumer, the radar chart, the task ordering and the overview, derives its numbers from the same place. All twelve tables are protected by row level security, scoped to the owning user through the project.

## Running it

This is not a product. There is no demo mode and no bundled backend. To run it you need your own Supabase instance with a matching schema.

1. Create a Supabase project
2. Create the twelve tables: `projects`, `assessments`, `questions`, `answer_options`, `answers`, `insights`, `actions`, `plans`, `plan_actions`, `notes`, `links`, `contacts`
3. Enable row level security on all of them, with policies scoping rows to `auth.uid()` through the owning project
4. Seed `questions` and `answer_options` with your own question bank
5. Deploy the two edge functions, `generate-insights` and `generate-plan`
6. Replace the URL and anon key in `AerealPerspective/SupabaseConfig.swift`

The edge function source is not included in this repository. Without it the app runs, but insights and plans will not generate.

The anon key committed here is a public client key. It grants nothing on its own: row level security decides what any given session can read or write.

## A note on the name

The repository is `AerialPerspective-iOS`, the Xcode target is `AerealPerspective` and the bundle identifier is `Axiotis.AerealPerspective`. The misspelling in the target name dates back to the first commit and was kept rather than migrating the bundle identifier.

## Web version

A web client covering the same data lives in a separate repository. It shares this Supabase instance, reimplements the scoring logic against the same question bank, and adds one thing the iOS app does not have: a public form link that lets a team lead answer an assessment without an account.

## Status

In active use. Insight and plan generation runs on iOS only.

## Licence

No licence is granted. All rights reserved.
