# FOREST — Fact-Oriented Reasoning & Evidence-backed Stance Tree 🌲

**UCS-503 Software Engineering — Prototype Project**

![Status](https://img.shields.io/badge/Status-Active-brightgreen)
![Course](https://img.shields.io/badge/Course-Software%20Engineering-blue)
![Platform](https://img.shields.io/badge/Platform-Web%20%26%20Android-orange)

> Live prototype: [forestapp.in](https://forestapp.in)
> This repository is private and shared only between the current co-founders. A rename is on the table once this moves past prototype — "FOREST" is a working name.

## 📖 About the Project

FOREST transforms unstructured video/voice opinions into navigable, verifiable argument graphs. It started as a UCS-503 college submission, but the actual goal is bigger: break the echo chambers that algorithmic feeds create on apps like Instagram and Facebook, by making every stance traceable back to evidence instead of just engagement. Modern debate on Twitter, Reddit, and short-form video is linear, fragmented, highly polarizing, and impossible to audit — users make claims, but there's no structured way to map claims, evidence, and counter-arguments to each other.

Users submit a video or voice opinion. The pipeline transcribes it, classifies its stance as **FOR**, **AGAINST**, or **UNRESOLVED**, fact-checks the claims inside it against external evidence, and links every classification to an exact transcript excerpt. The result is a branching, source-backed debate tree instead of a flat comment thread.

**Intended users:**
- Students & researchers — structured, source-backed debate analysis
- Political analysts — argument mapping and opinion analysis
- Everyday users — a quick read on FOR / AGAINST / UNRESOLVED across a topic

## 👥 Origin

Built as a UCS-503 Software Engineering prototype:
- **Sahibnoor Singh** — Team Lead & Backend Architect. REST API design, database, deployment.
- **Yaksh** — Ideation & Domain Specialist. Defined the core concept and the political-opinion/argument-tree domain.

Active development beyond the coursework prototype is now maintained privately between two co-founders on a 50/50 equity basis.

## ⚙️ How It Works — the 5-step pipeline

```
[ User Ingestion ]      Submit video URL or voice recording via forestapp.in
        │
        ▼
[ Audio Extraction ]    FFmpeg strips and normalises the audio track
        │
        ▼
[ AI Analysis ]         Gemini transcribes speech and identifies argument segments
        │
        ▼
[ Stance Classification ]  Each segment labelled PRO / CON / NEUTRAL with a topic tag
        │
        ▼
[ Graph Ingestion ]     VideoNodes and DebateEdges written to the discourse graph
```

Zero manual tagging is required — stance and topic mining are fully automated.

## ✅ Credibility / Fact-Checking Pipeline

Every claim extracted from a video is independently scored:

```
[ Spoken Video Audio ]
        │
        ▼
[ 1. Claim Extraction ]      Isolates verifiable assertions from subjective opinion
        │
        ▼
[ 2. RAG Evidence Search ]   Retrieves external facts & official data via LangChain
        │
        ▼
[ 3. Verdict Assignment ]    Maps each claim to a discrete truth status
        │
        ▼
[ 4. Mathematical Aggregation ]  Computes overall Video & User credibility scores
```

Each claim `Cᵢ` gets a score `S_Cᵢ ∈ [0.0, 1.0]` from its verdict weight `w(Vᵢ)` and evidence confidence `Eᵢ ∈ [0, 1]`:

```
S_Cᵢ = w(Vᵢ) × Eᵢ
```

## 🏗️ System Architecture

**Current layered stack (live prototype):**
1. **Frontend:** Vanilla JavaScript — forestapp.in UI layer
2. **Backend:** Node.js / Express REST API server
3. **AI Engine:** Gemini, multi-key & multi-model pipeline
4. **Database:** SQLite (nodes, edges, transcripts)
5. **Deployment:** Oracle Cloud (Always Free tier) · PM2 process manager · API key rotation

**Target architecture (3-package UML domain model):**
- **Package 1 — Auth & User Subsystem:** `User`, `UserProfile`, `AuthToken`, role/status enums, backed by PostgreSQL.
- **Package 2 — Core Debate Graph Subsystem (Neo4j domain model):** `Topic`, `ArgumentNode`, `StanceEdge`, `Bookmark`, with `StanceType` (FOR / AGAINST / UNRESOLVED).
- **Package 3 — AI & NLP Pipeline Subsystem:** `ITranscriber` (Whisper STT), `IStanceClassifier` (Gemini classifier service), `RAGFactChecker` (vector DB–backed claim verification).

Four use-case subsystems drive the product surface: User Authentication & Account Management, Video Ingestion & NLP Pipeline, Interactive Debate Graph Exploration, and Content Moderation & Anti-Bias Administration (bot/deepfake detection via FaceForensics++).

## 🛠️ Tech Stack

| Layer | Current | Target as it scales |
|---|---|---|
| Web frontend | Vanilla JS | React / Next.js |
| Mobile | — (in progress) | **Flutter** (single codebase → Android + iOS), built in Android Studio |
| Backend | Node.js / Express | Migrating to Spring Boot (team already has the Java/Spring background), still fronted by a queue — Redis / SQS — for async video jobs |
| Relational DB | — | PostgreSQL (auth, users) |
| Graph DB | SQLite (interim) | Neo4j (debate graph) |
| Transcription | Gemini | Whisper STT + Gemini classifier |
| Fact-checking | — | RAG via LangChain + vector store |
| Video storage | Local disk | Object storage (S3 / Oracle Object Storage) + CDN |
| Deployment | Oracle Cloud, single VM, PM2 | Oracle (always-on API) + burst/Spot compute for FFmpeg workers |

## 📈 Growth & Content Strategy

**Cold-start plan:**
- Bot/seed accounts are explicitly labeled as bots in the UI — never presented as real users. They exist only to give the graph something to react to on day one.
- Seed content sources, in priority order: founder-recorded videos (Sahibnoor + Yaksh) → recruited creators via a **paid upload program** (creators upload videos *they already own*, in exchange for cash/goodies — a real license, not scraping) → friends & Thapar societies creating real accounts pre-launch.
- **No Instagram scraping / re-hosting.** Re-uploading someone else's Reel onto FOREST is copyright infringement even with credit and a link back — attribution isn't a license, and doing it separately breaches Meta's platform terms regardless of the copyright question. The paid creator-upload program reaches the same "500–1,000 videos" goal without that exposure, since the creator brings their own file and grants FOREST the right to host/process it.
- Once Thapar Innovate (or similar) funding lands: formalize the creator program with tiered payouts based on watch/engagement thresholds.
- As real users overtake seed content, rotate out the least-interacted seed videos first (250 real / 250 seed → 500 real / 0 seed).

**Launch phases:**
0. **Foundation** — finalize the Flutter client and S3; strip the old website frontend down to just the API layer. Keep the current Node/Express backend running as-is through Closed Alpha — don't start the Spring Boot rewrite against a 15-day deadline, migrate it once the concept's validated.
1. **Closed Alpha (10–15 users, ~15-day build)** — founders + trusted friends only, on t3.medium. Scope is 4 screens, swipe-navigated: Home (following feed) → Feed corner (discovery) → Upload (camera/record) → Manage Account. No chat yet. Goal: prove record → transcribe → stance → graph → reply works end to end.
2. **College Beta (~200–500 users)** — friends + Thapar societies, seed-content rotation live, on t3.large. Goal: organic return visits without founder prompting.
3. **Open Campus Launch (~2,000 users)** — promote app-wide at Thapar; use real traction to pitch Thapar Innovate; migrate to managed Postgres/Neo4j + autoscaling.
4. **Public Launch (10,000+ users)** — full monetization, multi-college expansion, and the point to ship the iOS build. Can launch initially under a co-founder's existing Apple Developer account and transfer later via Apple's official App Transfer — but the app needs at least one already-approved published version to be transfer-eligible, and shouldn't use Apple auto-renewing in-app subscriptions before the transfer, since those block it.

**Ranks, streaks & creator payouts:**
- Rank progression (Newbie → Creator → …) and streaks should gate on a post clearing some credibility-score floor, not just raw count — gating on count alone rewards low-effort daily posting, which recreates the exact engagement-over-quality problem this app exists to fix.
- Creator payouts weighted by rank + views should also factor in the credibility score (`S_Cᵢ`), not views alone, so high-view low-quality content isn't the most profitable thing to post.
- Streak freezes are a fine retention mechanic on their own — not in tension with the quality point above.

**Chat / DMs:**
- Correctly deferred — private messaging between strangers on a political-opinion app is a known abuse vector.
- Basic report/block on video replies should ship from Phase 1 regardless — public content alone can already draw harassment.
- When chat does ship (Phase 4+, once there's real moderation bandwidth): no unsolicited first messages from unconnected strangers, rate-limit new accounts.

## 🚀 Repository Structure

```text
/
├── Website/               # Current team/demo website code
│   ├── frontend/           # Static frontend (HTML/CSS/JS) — being phased out
│   ├── backend/            # Node.js API server
│   └── README.md           # Website-specific setup instructions
├── app/                      # Flutter client — Android + iOS (new)
└── README.md                # This file
```

> The website frontend is being stripped out as the product moves to a single Flutter client (Android + iOS); the backend and AI pipeline stay and become the shared API layer for both.

## How to Run the Backend Locally

```bash
cd Website/backend
npm install
npm start
```
The server starts on `http://localhost:3000`. Open `Website/frontend/index.html` directly in a browser — no build step required.

**Admin panel (local dev only):** login `admin` / `admin123` — change this before any shared or production deployment.

## 📌 Status

**✅ Completed (Phase 1–5):** Video ingestion pipeline, FFmpeg audio extraction, Gemini AI stance & topic mining, discourse graph construction, live deployment at forestapp.in

**⚠️ Current limitations:** No real-time streaming support; graph scale limited by SQLite; Gemini API rate constraints; no user authentication layer yet

**🗺️ Roadmap (Phase 6–7):** PostgreSQL migration, real-time collaborative graphs, user accounts & saved views, multi-language support

**🌳 Long-term vision:** Transform chaotic, fragmented video discussions into a structured, traceable knowledge tree — making public discourse navigable, verifiable, and meaningful.

---
*Originally developed for the UCS-503 Software Engineering Lab, Thapar Institute of Engineering and Technology.*
