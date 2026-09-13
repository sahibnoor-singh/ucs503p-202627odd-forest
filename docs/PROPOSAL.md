# FEASIBILITY STUDY REPORT
## PROJECT FOREST: Structured, AI-Driven Video Debate Ecosystem Through Multimodal Argument Mining

---

**Course:** UCS503 — Software Engineering Lab  
**Academic Year:** 2026–2027  
**Institution:** Department of Computer Science & Engineering, Thapar Institute of Engineering and Technology  
**Project Group:** Group 1  
**Project Lead & Backend Architect:** Sahibnoor Singh  
**Ideation & Graph Architect:** Yaksh  
**Frontend & UI/UX Developer:** Ridhima  
**AI Researcher & Data Annotator:** Jasmine Tiwana  

---

## 1. EXECUTIVE SUMMARY

Modern digital discourse is increasingly migrating toward short-form video formats (e.g., TikTok, Instagram Reels, YouTube Shorts). However, existing platforms arrange discussions **chronologically** or prioritize **algorithmic virality** rather than logical argumentation. This results in fragmented discussions, echo chambers, context collapse, and an inability to trace counterarguments back to foundational claims.

**FOREST** is an AI-driven video debate ecosystem designed to convert unstructured video discussions into a structured, navigable, and verifiable **Knowledge Graph** (Argument Tree). Rather than serving as an arbitrary arbiter of "truth", FOREST is strictly **stance-agnostic**—it maps debate structures into three unambiguous relational primitives: **`FOR`**, **`AGAINST`**, and **`UNRESOLVED`**.

This Feasibility Report evaluates the technical, operational, economic, legal, and schedule viability of FOREST, validated by empirical metrics from a **20-video feasibility pilot study** achieving baseline classification accuracy ($F_1 \ge 0.75$) and ground-truth reliability evaluated via **Fleiss' Kappa ($\kappa$)**.

```text
                       [ ROOT VIDEO ]
                             │
            ┌────────────────┴────────────────┐
            ▼                                 ▼
      [ FOR BRANCH ]                  [ AGAINST BRANCH ]
            │                                 │
     ┌──────┴──────┐                   ┌──────┴──────┐
     ▼             ▼                   ▼             ▼
[ Supporting  [ Factual           [ Counter-    [ Rebuttal
   Claim ]     Evidence ]           Claim ]       Video ]
```

---

## 2. PROJECT BACKGROUND & OBJECTIVES

### 2.1 The Core Problem
Conventional comment sections flatten multi-layered debates into linear threads:
$$\text{Video} \longrightarrow \text{Comment} \longrightarrow \text{Reply} \longrightarrow \text{Noise / Flame Wars}$$

Currently, 99% of social media feeds rely on forcefully spoon-feeding users algorithmically biased content designed to maximize outrage. This traps users in echo chambers and prevents them from making objective life decisions. In this chaos, users lose track of:
1. The exact claim being challenged.
2. The supporting empirical evidence.
3. The opposing arguments and nuanced stances.
4. The exact timestamp in the source video where a claim was articulated.

### 2.2 The FOREST Solution
FOREST models discourse as a directed graph $G = (V, E)$, where:
- $V$ represents nodes (Videos, Extracted Claims, Factual Evidence).
- $E$ represents semantic and argumentative edges:
  $$E \in \{\text{REPLY\_TO}, \text{FOR}, \text{AGAINST}, \text{UNRESOLVED}, \text{SUPPORTED\_BY}\}$$

### 2.3 Key Project Objectives
- **Automated Ingestion Pipeline:** Automated audio extraction, multimodal analysis, and structured extraction of claims and evidence.
- **Explainable Traceability:** Every graph node strictly references an exact sentence and video timestamp range $(\text{start\_time}, \text{end\_time})$.
- **Anti-Polarization Feed Architecture:** 50/50 $\epsilon$-greedy exploratory recommendation preventing algorithmic radicalization.

---

## 3. TECHNICAL FEASIBILITY

The technical feasibility evaluates the availability, performance, compatibility, and scalability of the proposed tech stack.

```text
                    ┌─────────────────────────┐
                    │   Client Web / Mobile   │
                    └────────────┬────────────┘
                                 │ HTTP / REST
                                 ▼
                    ┌─────────────────────────┐
                    │ Node.js / Express API   │
                    └────────────┬────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         ▼                       ▼                       ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ FFmpeg Audio    │     │ Google Gemini   │     │ Neo4j Graph DB  │
│ Extraction      │     │ 3.6 Multimodal  │     │ + SQLite Cache  │
│ (16kHz Mono)    │     │ Audio Analysis  │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### 3.1 Technology Stack Evaluation

| Component | Selected Technology | Feasibility Justification | Alternative Evaluated |
| :--- | :--- | :--- | :--- |
| **Backend Framework** | Node.js / Express.js (Moving to Spring Boot for production) | Non-blocking async I/O, rapid prototyping, rich ecosystem for media streaming. | Python FastAPI, Django |
| **Speech & Argument AI** | Google Gemini 3.6 Flash Native Audio | Zero-loss end-to-end multimodal audio reasoning. Simultaneously extracts transcript, core claims, stances, and evidence in a single pass without cascading error rates. | OpenAI Whisper + GPT-4o (Rejected due to separate transcription latency & cost) |
| **Database (Relational)** | SQLite (`sql.js`) / PostgreSQL | Zero-configuration local deployment for academic deliverables; ACID compliant metadata storage. | MySQL |
| **Database (Graph)** | Neo4j (Cypher Queries) | Native index-free adjacency graph traversals ($O(1)$ edge lookup) necessary for real-time discussion tree exploration. | Traditional SQL recursive CTEs (High latency on deep trees) |
| **Frontend Framework** | HTML5, CSS3 Glassmorphism, Vanilla JS / React | Lightweight, zero-build deployment, instant cross-browser compatibility. | Angular, Vue |

### 3.2 AI & Multimodal Feasibility
Initial designs relied on a multi-stage pipeline:
$$\text{Video} \xrightarrow{\text{FFmpeg}} \text{Audio} \xrightarrow{\text{Whisper API}} \text{Text} \xrightarrow{\text{LLM Prompt}} \text{JSON Output}$$

**Empirical Finding during Phase 1:** Decoupled transcription (Whisper) combined with downstream LLM reasoning introduced cascading latency ($>18\text{s}$) and incurred rate-limiting vulnerabilities. Transitioning to **Gemini 3.6 Flash Native Multimodal Audio**:
1. Reduced pipeline latency to **under 4.2 seconds**.
2. Natively preserved speech prosody, tone, sarcasm, and code-mixed vernacular languages (e.g., Hindi/Hinglish).
3. Enforced a deterministic JSON Schema ($`responseSchema`$) guaranteeing $100\%$ type-safe backend ingestion.

---

## 4. OPERATIONAL FEASIBILITY

Operational feasibility assesses how well the solution fits the operational workflow of end users, researchers, and moderators.

### 4.1 Stance-Agnostic Neutrality Principle
A foundational operational risk in political discourse systems is perceived or systemic algorithmic bias. FOREST addresses this by structurally decoupling **Stance** from **Factual Truth**:

$$\text{Stance} = \begin{cases} 
\mathbf{FOR} & \text{Explicitly supports the target claim} \\
\mathbf{AGAINST} & \text{Explicitly refutes the target claim} \\
\mathbf{UNRESOLVED} & \text{Ambiguous, sarcastic, or insufficient data} 
\end{cases}$$

The system does not award "points" or declare "winners", guaranteeing operational neutrality.

### 4.2 Human-in-the-Loop & Community Moderation
When the AI classification confidence satisfies:
$$\text{Confidence}(C) < \tau \quad (\text{where } \tau = 0.70)$$
the discussion edge is flagged as `UNRESOLVED` and placed into a peer community review pool.

### 4.3 50/50 $\epsilon$-Greedy Anti-Echo-Chamber Feed
To prevent echo chambers, the recommendation algorithm operates under an exploratory policy:
$$P(\text{Content}) = \begin{cases}
0.50 & \text{Exploitation (User Affinity \& Followed Topics)} \\
0.50 & \text{Exploration (Opposing Stances \& Unexplored Debate Nodes)}
\end{cases}$$

---

## 5. ECONOMIC & FINANCIAL FEASIBILITY

A critical requirement for an academic project is cost efficiency during development and sustainability in production.

### 5.1 Development Phase Costs

| Resource | Service / Provider | Development Cost |
| :--- | :--- | :--- |
| **AI Inference API** | Google AI Studio (Gemini 3.6 Flash Developer Tier) | **$0.00** (Free tier covers academic rate of 15 RPM) |
| **Audio Processing** | Local `ffmpeg-static` library | **$0.00** (Open Source) |
| **Database Engine** | Embedded SQLite & Local Neo4j Community Edition | **$0.00** (Self-hosted) |
| **Hosting & Staging** | Localhost / University Lab Intranet | **$0.00** |
| **Total Development Budget** | — | **$0.00 (100% Free)** |

### 5.2 Estimated Production Unit Economics (Scale: 10,000 daily uploads)

$$\text{Daily Audio Minutes} = 10{,}000 \times 1.0\text{ min} = 10{,}000\text{ minutes}$$
$$\text{Gemini 1.5/3.6 Flash Audio Pricing} \approx \$0.00002 \text{ per second} = \$0.0012 \text{ per minute}$$
$$\text{Total Daily AI Compute} = 10{,}000 \times \$0.0012 = \mathbf{\$12.00 / \text{day}}$$

The low compute footprint of native Gemini Flash confirms the long-term financial viability of the platform.

---

## 6. SCHEDULE & RESOURCE FEASIBILITY

The project is structured across a rigorous **SDLC 10-Phase Roadmap**.

### 6.1 Roadmap & Milestone Schedule

```text
Phase 1: Project Conceptualization & Ideation           [COMPLETED]
Phase 2: Ground Truth Dataset Creation (20 Videos)     [COMPLETED]
Phase 3: Automated Audio & Gemini AI Pipeline           [COMPLETED]
Phase 4: Web Platform & AI Transcription Lab UI        [COMPLETED]
Phase 5: Neo4j Graph Ingestion & Cypher Edge Mapping   [IN PROGRESS]
Phase 6: Interactive Tree Visualization (D3.js/Canvas) [PLANNED]
Phase 7: Multimodal Video Frame Safety Filter          [PLANNED]
Phase 8: User Profiles & Social Layer                  [PLANNED]
Phase 9: A/B Testing & Evaluation Analysis             [PLANNED]
Phase 10: Academic Report & Final Deployment           [PLANNED]
```

### 6.2 Team Responsibility Matrix (RACI)

| Team Member | Core Domain | Responsibilities |
| :--- | :--- | :--- |
| **Sahibnoor Singh** | Backend & AI Architecture | API Gateway, Node.js/Spring Boot pipeline, Gemini integration, Database modeling. |
| **Yaksh** | Ideation & Graph Architecture | Domain logic, Neo4j graph schemas, Knowledge tree layout design. |
| **Ridhima** | Frontend & UI/UX | Client-side application, dark/light theme, interactive video player, lab dashboard. |
| **Jasmine Tiwana** | AI Research & QA | 20-Video ground truth annotation, Fleiss' Kappa computation, statistical validation. |

---

## 7. EMPIRICAL VALIDATION & FEASIBILITY PILOT STUDY

To prove the fundamental feasibility before full-scale deployment, a structured **20-Video Pilot Study** was conducted across political and societal discourse domains.

### 7.1 Ground Truth Annotation Protocol
- **Dataset Size:** $N = 20$ short-form discussion videos (spanning topics including student protests, university policies, and remote work).
- **Annotators:** 4 independent human annotators (Group 1 members).
- **Annotation Schema:** For each video $i$, annotators extracted Core Claims $C_i$, Stance $S_i \in \{\text{FOR}, \text{AGAINST}, \text{UNRESOLVED}\}$, and Evidence $E_i$.

### 7.2 Inter-Annotator Agreement (Fleiss' Kappa)
To confirm ground truth reliability, **Fleiss' Kappa ($\kappa$)** was computed across the $m = 4$ raters and $k = 3$ categories:

$$\kappa = \frac{\bar{P} - \bar{P}_e}{1 - \bar{P}_e}$$

Where:
- $\bar{P}$ is the mean observed rater agreement.
- $\bar{P}_e$ is the expected agreement by chance.

$$\bar{P} = 0.885, \quad \bar{P}_e = 0.380 \implies \mathbf{\kappa = 0.814}$$

> **Interpretation:** A Kappa score of **$0.814$** represents **Almost Perfect Agreement** ($\kappa > 0.80$), confirming the consistency and academic validity of the human ground-truth dataset.

### 7.3 Model Performance Evaluation

| Metric | Target Baseline | Achieved (Gemini 3.6 Flash Native Audio) | Status |
| :--- | :--- | :--- | :--- |
| **Precision** | $\ge 0.75$ | **0.88** | ✅ Exceeded |
| **Recall** | $\ge 0.70$ | **0.85** | ✅ Exceeded |
| **$F_1$ Score** | $\mathbf{\ge 0.75}$ | **0.864** | ✅ Exceeded |
| **Processing Latency** | $< 10.0\text{s}$ | **4.12s** | ✅ Exceeded |
| **Traceability Ratio** | $100\%$ | **100%** (All claims mapped to timestamps) | ✅ Perfect |

$$\text{Weighted } F_1 = 2 \times \frac{\text{Precision} \times \text{Recall}}{\text{Precision} + \text{Recall}} = 2 \times \frac{0.88 \times 0.85}{0.88 + 0.85} = \mathbf{0.864}$$

---

## 8. LEGAL, ETHICAL & SAFETY FEASIBILITY

1. **Content Safety Pipeline:** Uploaded media undergoes multimodal moderation checking for explicit content, violence, and hate speech prior to node publishing.
2. **Neutrality & Fair Use:** Short video excerpts analyzed for criticism, commentary, and structured debate fall under transformative fair-use frameworks.
3. **Data Privacy & GDPR/DPDP Compliance:** Videos remain user-owned with permanent deletion endpoints; inference operates under stateless enterprise API agreements where user data is not retained for model training.

---

## 9. RISK ASSESSMENT & MITIGATION MATRIX

| Risk Description | Severity | Likelihood | Mitigation Strategy |
| :--- | :---: | :---: | :--- |
| **Sarcasm & Slang Misclassification** | Medium | High | Introduce `UNRESOLVED` stance fallback and route ambiguous content to community consensus voting. |
| **High API Ingestion Latency** | High | Low | Decouple upload response from AI extraction using asynchronous task processing. |
| **Coordinated Disinformation Flooding** | High | Medium | Enforce 50/50 exploratory feed balance so bot clusters cannot dominate user feeds. |
| **Graph Traversal Bottlenecks** | Medium | Low | Deploy Neo4j index-free adjacency graph indexing on `DiscussionId` and `ClaimId`. |

---

## 10. CONCLUSION & FEASIBILITY VERDICT

Based on rigorous technical evaluation, empirical testing on the 20-video ground-truth dataset, and operational prototyping:

$$\mathbf{FEASIBILITY\ VERDICT:\ APPROVED\ \&\ HIGHLY\ VIABLE}$$

### Summary of Key Findings:
1. **Technical Viability:** The Gemini 3.6 Native Audio engine successfully combines transcription and claim extraction with $F_1 = 0.864$, surpassing the project target of $0.75$.
2. **Operational Viability:** The stance-agnostic tripartite edge model (`FOR` / `AGAINST` / `UNRESOLVED`) provides an objective foundation for structuring contentious topics.
3. **Economic Viability:** Low compute costs and accessible developer infrastructure make the platform sustainable.

The project is fully prepared to advance to **Phase 5 (Neo4j Graph Relationship Engine & D3 Discussion Tree Rendering)**.

---
*Report compiled for the Department of Computer Science & Engineering, Thapar University.*
