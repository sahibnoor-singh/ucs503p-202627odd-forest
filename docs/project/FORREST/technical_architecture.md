# FORREST - Technical Architecture, APIs, & NLP Pipeline

## The AI / NLP Paradigm
We are building an **Agentic NLP Pipeline** using frozen LLMs (like the Gemini API or GPT-4o). We are **not** training a foundational model from scratch.
- **Frozen Inference Model:** Because the neural weights of the LLM are frozen, it cannot suffer from real-time model drift or learn bad habits from user inputs. It is mathematically impossible for coordinated spam attacks (e.g., IT cells) to "poison" the core model over time.

## Core Extraction Pipeline (Per Video)

1. **Transcription (Speech-to-Text):** 
   - Extract the script from the video.
   - **Tool:** OpenAI Whisper (open-source, runs locally, 90+ languages).

2. **Stance & Entity Classification (NLP Extraction):** 
   - A structured prompt containing the *parent video's transcript* is fed alongside the reply transcript to an LLM.
   - **Tool:** Google Gemini API or OpenAI GPT-4o API.
   - **Outputs:**
     - **Entities:** Who or what is the video about?
     - **Claims:** What factual assertions are made?
     - **Stance:** FOR, AGAINST, or UNRESOLVED.
     - **Timestamp:** The exact time range (e.g., `0:12-0:28`) that justifies the classification.

3. **Scoring:** 
   - **Fact Score (0-100):** Factual claims vs. unsubstantiated opinions.
   - **Truth Rating (0-100):** Cross-referenced claims via Retrieval-Augmented Generation (RAG) using LangChain.
   - **Emotional Appeal (0-100):** Emotional persuasion vs. logical reasoning.
   - **Comedy/Satire (0-100):** Helps contextualize confidence in stance.

4. **Metadata Extraction:** 
   - Topic Tags & Hashtags (for interest-based recommendations).

## The Graph Database (Structure & Storage)
- **Tool:** Neo4j (Industry Standard Graph Database)
- **Architecture:** `[Root Video] -> makes claim -> [Claim X] <- attacks/supports <- [Child Video]`
- The Neo4j database visually maps the debate tree. This provides full traceability, allowing the UI to display branches and enabling backend scripts to detect anomalies.

## Solving the Spam vs. Rebuttal Problem (Stance Detection)
Using **Stance Detection**, we prevent suppression of legitimate counter-arguments while filtering spam.
- **Scenario:** 10,000 bots post "Anti-Student" videos (same script, same stance). One student posts a "Pro-Student" video.
- **Resolution:** The AI extracts the *Stance* along with the Topic. The 10,000 identical "Anti-Student" videos are mathematically flagged as an anomaly/bot attack in the Graph DB. The student's video shares the topic but has a **Counter-Stance** ("Pro-Student"). The system recognizes it as a legitimate *Rebuttal* and promotes it, displaying the other side of the argument.

## Tech Stack Overview
- **Speech-to-Text:** OpenAI Whisper (Proven, Open Source)
- **Stance Classification LLM:** Google Gemini API or OpenAI GPT-4o API (Proven, API-based)
- **Fact-Checking (RAG):** LangChain (Feasible)
- **Graph Database:** Neo4j (Proven, Industry Standard)
- **Deepfake / AI Face Detection:** Pre-trained models like Microsoft FaceForensics++ (Open Source)
- **Backend:** Spring Boot (Java)
- **Frontend (Web):** React.js with D3.js or React Flow for graph visualization
- **Frontend (App):** Flutter (Dart)

## Feasibility & Evaluation Plan
- **Ground Truth:** Team members manually annotate a pilot dataset of 20 videos (Stance, Timestamps, Fact Scores). Agreement measured via Fleiss' Kappa.
- **Baselines:** 
  - *Baseline 1:* Zero-Shot LLM (Prompt: "Is this video FOR or AGAINST [topic]?").
  - *Baseline 2:* Summary Classification (Summarize transcript -> Classify summary).
- **Our Method (FORREST Pipeline):** Contextual Chain-of-Thought prompting (passing parent transcript + reply transcript for simultaneous extraction of stance, timestamps, and scores).
- **Quantitative Metrics:** Precision, Recall, F1-Score, Stance Accuracy, and Timestamp Overlap (IoU).
