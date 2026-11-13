# Onboarding: the first minute of a new account

Status: **building** (2026-10-21). Why: a new account lands on an empty Home and an unpersonalised Discover, and the first session decides
whether anyone comes back (`docs/PRODUCT_REPORT.html`, "the empty-room problem").

## What a new person sees (after sign-up, by e-mail code or Google)

1. **"What should we show you?"** A grid of topic chips (Politics, Economy, Jobs and careers, Education, Campus life, Technology and AI,
   Environment, Health, Law and rights, Society and culture, Sports, Entertainment, Ethics and religion, Startups, Foreign affairs,
   Farming). Pick **3 to 8**. **Skip for now** is always there. Nothing is pre-selected.
2. **"Follow a few people."** The people from `GET /api/users/suggested`, each with a Follow button, bots labelled BOT as everywhere.
   Following three or more fills Home. **Done** or **Skip**.
3. **"How it works"**: three short pages, one idea each (share an opinion, reply with a video, swipe sideways to see FOR and AGAINST).
   Next / Start, and Skip is always there. Plain words, no pointing at buttons, no game-style tour. Text lives in `OnboardingController.guideSlides`.
4. The app opens on Home. No permissions, no profile photo.

## Rules

- It is shown **once**, right after sign-up. If the app is closed in the middle, it comes back next launch (a local "pending" flag).
  People who already had accounts are never asked (the migration marks every existing account as done).
- Topics are a **starting guess, not a box**. They seed the taste profile (each topic is a handful of words at affinity 0.7, a little above the
  neutral 0.5), and real watching moves them from the first video on. Discover still keeps its 10% exploration and its other-side slot, so the
  topics never become a wall (the echo-chamber rule).
- Nothing is required: skipping both steps still gives a working app. A person who skips is marked done too and is not asked again.
- The same call is used later by a "Your topics" setting (not built yet), so choosing again never re-triggers onboarding.
- No dark patterns: no "follow 5 to continue", no pre-ticked follows.

## Server

- `users.onboarded_at` (NULL = never finished). Migration: all existing accounts get their `created_at`.
- `GET /api/onboarding/topics` -> `{ topics: [{ id, label }], min: 3, max: 8 }` (the list and each topic's words live in `src/topics.js`).
- `POST /api/me/onboarding { topics: ["politics", "tech"] }` seeds the profile and sets `onboarded_at` the first time. 0 to 8 known ids; unknown
  ids are a 400. Replies `{ topics }`.
- `GET /api/me` -> `account.onboarded`.

## App

- `Session.needsOnboarding` is set when a sign-up completes (e-mail, phone or Google) and kept across launches until finished.
  `AuthGate` shows `OnboardingFlow` instead of the app while it is set.
- `lib/features/onboarding/`: controller (no widgets, tested alone), the two-step screen, and the repository calls.

## Measured later (analytics step)

Finished vs skipped, topics chosen, people followed, and whether the first session reaches five videos. `onboarded_at` already gives the first one.

## Not in this step

- Ranking suggested people by the chosen topics (the pool is small; do it when it is not).
- The "answer one prompt" step (comes with the daily prompt).
- Editing topics later.
