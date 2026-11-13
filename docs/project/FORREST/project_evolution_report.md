# FORREST - Project Evolution & Prototype Report

*This living document tracks the versions, experiments, and technical evolution of the FORREST AI pipeline. It serves as the official project log for academic reporting.*

---

## Prototype v1.0 - The Isolated Extraction Spike
**Date:** August 2026
**Objective:** Test if the Gemini API can extract claims and stance from raw audio transcripts (via Whisper) without building a frontend UI.

### Methodology
- Collected 9 random short-form opinion videos.
- Used an automated Python script (`process_transcripts.py`) to feed raw transcripts into the Gemini 3.6 Flash model.
- Prompt instructed the AI to extract: `core_topic`, `stance` (FOR/AGAINST), `primary_claim`, and `evidence_used`.

### Results & Critical Findings
- **Success:** The AI successfully parsed unstructured text and outputted perfectly formatted, database-ready JSON. It extracted the `primary_claim` and `evidence_used` with high accuracy.
- **Failure (The Context Problem):** The AI failed to accurately assign the relative `stance` (FOR/AGAINST) because no **Root/Parent Video** was provided. 
- **Scientific Conclusion:** A machine learning model cannot classify an argument as a "rebuttal" if it doesn't know what it is rebutting. Analyzing child nodes in absolute isolation leads to high hallucination in relative stance classification.

### Action Items for v1.5
- The team must formally designate **1 Parent Video** (Root Node).
- The Prompt Engineering must be updated to inject the `[Parent Transcript]` as the anchor context alongside every `[Reply Transcript]` processed.

---

## Prototype v1.5 - Context-Aware Extraction (Completed)
**Date:** August 2026
**Objective:** Solve the "Context Problem" discovered in v1.0 by feeding the Parent Video to the LLM.

### Methodology
- The team officially designated `FOR11` (renamed to `PARENT_VIDEO`) as the Root Node.
- Built a multi-model auto-switching Python pipeline (`process_transcripts.py`) that falls back to Gemini Flash Lite when hitting rate limits.
- The pipeline securely reads the Parent transcript into memory and dynamically injects it into every Reply prompt for comparative analysis.

### Results & CEO Insight: Semantic Granularity vs Broad Tagging
- **Success:** The pipeline successfully parsed all 25 transcripts, generating strictly formatted JSON Knowledge Entities and rendering a highly accurate Debate Graph.
- **Critical Discovery:** During testing, we discovered a massive flaw in human categorization that our AI successfully solves. The human data team manually placed videos into broad "FOR" folders based on general sentiment (e.g., "this person supports the Jantar Mantar protest"). 
- **The AI Correction:** Our AI mathematically proved this human tagging is dangerously inaccurate for a graph database. The AI strictly compared the claims of the reply videos against the *specific, granular claims* of the Parent Video (Police Brutality). It correctly identified that many "FOR" videos were actually talking about entirely different sub-topics (e.g., NEET Paper Leaks, Education Costs) and flagged them as UNRESOLVED. Furthermore, it correctly flagged a pro-protest video (`FOR12`) as AGAINST the parent because their factual claims contradicted each other regarding lathi charges.
- **Conclusion:** Human tagging evaluates "Vibe." The FORREST AI evaluates "Semantic Facts." This proves the absolute necessity of our AI-driven Debate Graph.
