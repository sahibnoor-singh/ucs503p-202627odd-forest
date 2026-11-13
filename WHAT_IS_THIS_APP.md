# FOREST 🌲 — Comprehensive Application Overview & System Architecture

> **Acronym:** **F**act-**O**riented **R**easoning & **E**vidence-backed **S**tance **T**ree  
> **Tagline:** A video-first, evidence-backed debate platform engineered to dismantle algorithmic echo chambers.  
> **Founders:** Sahibnoor Singh (Backend Architecture & Infra) & Yaksh (Product, Mobile Engineering & Domain Architecture) — 50/50 Equity.  
> **Status:** Active development — live prototype (`forestapp.in`), native Flutter multi-platform client (`Android & iOS`), Node.js/Express API backend, and planned enterprise Neo4j/Spring Boot scaling.

---

## 1. Executive Summary: What is FOREST?

**FOREST** is a social discourse and debate application built around short-form video and multimedia arguments. Instead of trapping users in polarized algorithmic loops (like Instagram Reels, TikTok, or YouTube Shorts) or burying constructive discourse in messy walls of text (like Reddit or Twitter/X), FOREST restructures public debates into **verifiable, multi-perspective argument graphs**.

When a user posts a 30-to-60 second video stating an opinion or makes a video/text reply to someone else:
1. **AI automatically extracts and transcribes the speech** using Google Gemini.
2. **AI segments core claims and classifies the stance** relative to the parent topic as **FOR (PRO)**, **AGAINST (CON)**, or **UNRESOLVED / NEUTRAL**.
3. **Claims are fact-checked against external verifiable sources** using a Retrieval-Augmented Generation (RAG) framework, generating a mathematical **Credibility Score ($S_{C_i}$)**.
4. **Discourse is mapped as an interactive branching tree**, allowing users to swipe vertically through chronological reels or swipe horizontally to immediately hear opposing counter-arguments.

---

## 2. The Core Problem FOREST Solves

Modern social media platforms monetize engagement through emotional outrage:
- **Algorithmic Echo Chambers:** Recommendation engines feed users content that confirms their existing biases, isolating groups into ideologically closed silos.
- **The "Wall of Text" Barrier:** Thoughtful debate on platforms like Reddit requires reading endless, unverified walls of text that average users skim past.
- **Unverifiable Assertions:** Video platforms (TikTok, Instagram Reels) allow creators to make baseless factual assertions with zero accountability or context.
- **Fragmented Comment Sections:** Flat, linear comment threads devolve into insults, bad-faith trolling, and off-topic arguments rather than structured point-counterpoint discussions.

### FOREST's Value Proposition:
| Traditional Social Media (Instagram / X / Reddit) | FOREST 🌲 |
|---|---|
| Algorithmic feed optimizes for anger and outrage | Recommendation engine prioritizes perspective diversity & credibility |
| Baseless claims go viral without fact checks | Automated claim extraction & evidence-backed credibility score ($S_{C_i}$) |
| Linear, toxic comment threads | Interactive debate trees branching into FOR, AGAINST, and NEUTRAL |
| Engagement volume rewards spam & sensationalism | Creator status, streaks, and payouts gate on credibility and argument quality |

---

## 3. How the App Works (End-to-End Pipeline)

```
       [ 1. User Ingestion ]
  User records or uploads a 60s video, 
  photo slideshow, or animated text post
                 │
                 ▼
     [ 2. Audio & Media Prep ]
  FFmpeg strips audio / renders composition
  (ASS subtitle animations, audio mixing)
                 │
                 ▼
       [ 3. AI Analysis ]
  Google Gemini speech-to-text transcription
  & argument boundary segmentation
                 │
                 ▼
    [ 4. Stance Classification ]
  Claims analyzed & stance labeled:
  • FOR (Green)  • AGAINST (Red)  • UNRESOLVED (Gray)
                 │
                 ▼
    [ 5. Evidence & Credibility ]
  LangChain RAG verification against external sources:
         S_Cᵢ = w(Vᵢ) × Eᵢ
                 │
                 ▼
    [ 6. Graph & Feed Ingestion ]
  Video nodes & debate edges saved to SQLite / Neo4j;
  Instant navigation via tree viewer & horizontal reels swipe
```

### The Credibility Scoring Model
Every factual claim $C_i$ extracted from an opinion video is assigned a credibility score:
$$S_{C_i} = w(V_i) \times E_i$$
- $w(V_i) \in [0.0, 1.0]$: Verdict weight based on truth status (e.g., Verified True, Mostly True, Inconclusive, Misleading, False).
- $E_i \in [0.0, 1.0]$: Evidence confidence score calculated from retrieved external citations.

---

## 4. Key Mobile App Features & User Experience

The mobile client is built with **Flutter** (Android + iOS) using a clean design system (`ForestTokens` / `ForestTheme` supporting system dark and light modes).

### 📱 1. Core Navigation Tabs (`RootShell`)
1. **Home Feed (`HomeFeedScreen`):**
   - Shows posts and debate threads from followed creators.
   - Expandable thread viewers and bottom sheets for replies.
   - Stories row and "Suggested People" to prevent empty-feed states.
2. **Discover & Search (`DiscoveryFeedScreen`):**
   - **Quilted Grid View:** Dynamic staggered visual grid of trending argument openers with thumbnail previews and FOR/AGAINST stance counters.
   - **Full-Screen Video Reels:** Immersive vertical swipe for video discovery, with **horizontal swipe** to switch instantly between FOR and AGAINST responses to that specific claim.
   - **Full Unified Search:** Debounced search across Accounts, Posts, Topics, and Transcripts powered by indexed triggers.
   - **Friend's Taste Feed:** Collaborative recommendation filter based on what friends are debating.
3. **Creator Studio & Editor (`UploadScreen` / `features/editor`):**
   - **Video Mode:** Camera recording, gallery picker, video trimming, original sound muting, local music addition.
   - **Text Post Mode:** Dynamic backgrounds (solid colors & gradients) with animated kinetic typography (fade-in, slide-up, typewriter, word-by-word) rendered with libass subtitles.
   - **Photo Carousel Mode:** 1 to 10 photos with reordering, cropping, slideshow timings, and background audio.
   - **Server-Side Render Engine:** Compiles client recipes into clean MP4s via FFmpeg, ensuring zero on-device encoder fragmentation.
4. **Account & Safety (`AccountScreen`):**
   - Profile information, user debate history, and follower/following stats.
   - Active blocked accounts manager and privacy controls.
   - Indian IT Rules compliance hub: Grievance Officer details and content complaint filing.

### 🛡️ 2. Safety, Onboarding & Messaging
- **First-Minute Onboarding Flow (`features/onboarding`):**
  - Selects 3 to 8 initial topic interests (Politics, AI, Economy, Farming, etc.) to jump-start personalization without locking users into ideological bubbles.
  - Follows recommended thought leaders and debate accounts.
- **Direct Messaging (`features/messages`):**
  - Real-time slide-in 1-on-1 conversations with unread indicators and rate-limited initiation to curb spam.
- **Safety & Moderation (`features/safety`):**
  - Universal "Report" and "Block" options on every video, reply, and account.
  - Automatic moderation blocklists and administrative review queues.

---

## 5. Technical Architecture & Tech Stack

```
┌──────────────────────────────────────────────────────────────┐
│                      FLUTTER CLIENT                          │
│               (Android / iOS / Tablets)                      │
│   • MultiProvider State Management                           │
│   • VideoPool & Disk-backed VideoCache                       │
│   • Forest Design System (Tokens, Themes, Haptics)           │
└──────────────────────────────┬───────────────────────────────┘
                               │ HTTPS / JSON (REST API)
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                    NODE.JS / EXPRESS API                     │
│                     (app/backend/src)                        │
│   • Auth Subsystem: Scrypt hashes, HS256 JWT, SMS/Email OTP  │
│   • Rate Limiting & DoS Protection                           │
│   • PIPS Recommendation Engine (Personalized Diversity)      │
│   • Asynchronous Job Queue (Serialized Worker)               │
└──────────────┬───────────────────────────────┬───────────────┘
               │                               │
               ▼                               ▼
┌────────────────────────────┐  ┌──────────────────────────────┐
│     MEDIA & AI WORKER      │  │        STORAGE & DATA        │
│ • FFmpeg (Compose & Trim)  │  │ • SQLite (In-memory + atomic │
│ • libass (Text Overlays)   │  │   file snapshot via sql.js)  │
│ • Google Gemini LLM API    │  │ • Local Uploads / AWS S3     │
│ • Demucs Audio Extraction  │  │ • Neo4j + Postgres (Target)  │
└────────────────────────────┘  └──────────────────────────────┘
```

### Detailed Tech Stack Breakdown
| Domain | Current Implementation | Planned Production Target |
|---|---|---|
| **Mobile Client** | **Flutter (Dart)** — single codebase for Android & iOS | Flutter with `flutter_secure_storage` & App Store release |
| **Primary Backend** | **Node.js / Express** (`app/backend`) | Migration to **Java / Spring Boot** (`forest/forest_backend`) |
| **Relational Database** | **SQLite** (via `sql.js` in-memory with file persistence) | **PostgreSQL** (Managed AWS RDS) |
| **Graph Database** | SQLite graph tables (`nodes`, `edges`) | **Neo4j** (AuraDB graph cluster for complex traversals) |
| **AI Transcription & NLP**| **Google Gemini API** (transcription, stance classification) | Whisper STT + Gemini 1.5 Pro / Flash |
| **Audio Processing** | **FFmpeg Static** + Python Demucs stem separator | Cloud Run / Spot GPU audio processing workers |
| **Storage & CDN** | Local storage / sandboxed disk uploads | **AWS S3** with CloudFront CDN distribution |
| **Hosting & Infra** | Oracle Cloud Infrastructure (OCI Always Free VM) | AWS (t3.medium $\rightarrow$ t3.large auto-scaling group) |

---

## 6. Regulatory & Legal Readiness (Indian IT Rules 2021/2026)

Because FOREST hosts user-generated political and social commentary, it is architected with strict compliance with Indian intermediary regulations under **Section 79 of the Information Technology Act**:
- **Designated Grievance Officer:** Dedicated endpoint (`GET /api/legal/contact`) publishing the contact details of a real, reachable human officer.
- **Expedited Takedown Mechanisms:** Ready for statutory emergency response windows (3-hour court/government orders, 2-hour sensitive content removal, 36-hour general grievances).
- **Audit Logs:** Tamper-evident `moderation_log` storing all administrative actions and report histories.
- **Repeat Infringer Policy:** Automated 3-strike suspension rule for intellectual property/copyright violations.
- **DPDP Act (Digital Personal Data Protection):** 18+ age verification gate during sign-up, strict consent flows, and full account deletion cascades.

---

## 7. Project Evolution & History

1. **Phase 0 — Academic Roots:**
   - Originated as a capstone project for **UCS-503 (Software Engineering)** at Thapar Institute of Engineering and Technology (Group 1 / Group 3).
   - Early prototype consisted of a vanilla JS website and Spring Boot/Neo4j backend.
2. **Phase 1 — Live Prototype & Startup Pivot:**
   - Deployed live at `forestapp.in` on Oracle Cloud.
   - Formed a 50/50 co-founder partnership between Sahibnoor Singh and Yaksh to turn FOREST into a full-scale startup.
3. **Phase 2 — Mobile First & Production Rewrite:**
   - Full rewrite of the client into **Flutter** for Android and iOS.
   - Node.js backend enhanced with a full creator suite (video, audio, text animations), PIPS recommendation algorithms, real-time messaging, and safety suites.
   - 100+ comprehensive automated tests across both backend and mobile suites.

---

## 8. Directory Structure Guide

```text
software-engineering-project-grp1/
├── app/                           # PRODUCTION FLUTTER & NODE BACKEND
│   ├── lib/                       # Flutter Application (Dart)
│   │   ├── features/              # Feature slices (auth, discover, editor, home, 
│   │   │                          #                  messages, onboarding, reels, safety)
│   │   ├── screens/               # Main tab screens (Home, Discover, Upload, Account)
│   │   ├── services/              # API Client, Session, VideoPool, VideoCache
│   │   └── theme/ & ui/           # Forest design tokens, components, icons
│   └── backend/                   # Node.js/Express API Server
│       ├── src/                   # Routes, DB layer, PIPS recommender, video compose
│       └── scripts/               # Seed scripts, benchmarks, backups
├── docs/                          # Comprehensive Documentation
│   ├── api.md                     # REST API specification & contract
│   ├── DEVELOPER_GUIDE.md         # Onboarding & developer runbook
│   ├── PHASE1_HOME_PLAN.md        # Home feed architectural spec
│   ├── DISCOVER_PLAN.md           # Reels, Grid, Search, and Recommendations
│   ├── EDITOR_PLAN.md             # Creator studio & FFmpeg compose engine
│   └── PRODUCT_REPORT.html        # Exhaustive product report & user research
├── forest/forest_backend/         # Reference Spring Boot + Neo4j enterprise backend
├── Website/                       # Legacy Web prototype (forestapp.in)
└── services/audio-preprocessing/  # Flask + Demucs audio stem separation worker
```

---

## 9. Summary: In One Sentence

> **FOREST is a short-form video social network that uses artificial intelligence to organize opinions into source-backed, multi-sided debate trees—giving users the full truth rather than an algorithmic echo chamber.**
