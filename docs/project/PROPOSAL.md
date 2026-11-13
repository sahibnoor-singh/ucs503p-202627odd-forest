# Project FOREST: Proposal & Feasibility Report

## 1. Problem Statement
The modern social media landscape is broken. Current statistics suggest that a massive majority of users are exhausted by echo chambers and algorithmic bias. Platforms spoon-feed users highly polarized content designed to maximize engagement through outrage, rather than providing objective facts. This forceful algorithmic feeding prevents users from applying critical thinking and making well-rounded life decisions. People want to see the full picture, but they don't have the tools to map out arguments clearly.

## 2. Proposed Solution (Project FOREST)
FOREST is an AI-powered debate graph platform. Instead of a linear, echo-chamber feed, FOREST visualizes political and social opinions as an interactive map. 
When a user uploads an opinion video (reel), our system:
1. Automatically transcribes the audio.
2. Uses LLMs to classify the core claims.
3. Determines if the video is **FOR**, **AGAINST**, or **UNRESOLVED** compared to the parent topic.

This builds a live, visual web of arguments where viewers can click on any node to see opposing viewpoints, empowering them to reorganize their perspectives and escape algorithmic bias.

## 3. Feasibility Analysis

### A. Technical Feasibility
The project is highly technically feasible and the core pipeline is already operational.
* **Backend:** Spring Boot provides a robust REST API, backed by Neo4j (Graph Database) which is natively designed to handle complex relational nodes (arguments).
* **AI Integration:** We have successfully integrated the Gemini API for fast, affordable, and highly accurate video transcription and stance classification.
* **Frontend:** We use modern web technologies (React/Node.js) and `vis-network` to render the massive argument graphs dynamically in the browser without lag.

### B. Economic & Resource Feasibility
* **Cost:** We are leveraging open-source tools (Whisper/Demucs) and generous free tiers for cloud databases (Neo4j Aura) and LLMs (Gemini). The infrastructure cost remains near zero during the academic development cycle.
* **Time:** The core team has already completed the primary technical hurdles (API linkage, auth, graph rendering) ahead of schedule.

### C. Social & Market Feasibility
Market trends show users are shifting toward platforms that offer transparency. By targeting debate culture and political analysis, FOREST taps into a high-engagement niche. If users can finally see a mapped-out debate rather than just scrolling endlessly, the platform has a strong chance of widespread adoption.

## 4. Conclusion
Project FOREST is not just a standard web app; it is a necessary evolution of social media. The technical stack is proven, the prototype is functional, and the social demand for transparent, anti-algorithmic platforms makes this project highly viable for success.
