# FORREST - Prototype Roadmap & Task Allocation (Final Architecture)

## Team Roster & Roles
The workload is split to perfectly align with existing skills. The backend and AI prompting are centralized in Spring Boot, while the graph structure and UI are handled separately.

### 1. Sahibnoor Singh (Lead Backend & AI Engineer)
**Role:** Spring Boot Server & Gemini AI Master.
*Why:* You already have extensive experience integrating the Gemini API via Spring Boot from your StratGo project. This plays exactly to your strengths.
**Tasks:**
- Set up the **Spring Boot backend** for core operations (User Auth, Video Upload handling).
- Integrate the **Gemini API** directly into Spring Boot. You write the prompts, send the transcripts, and extract the JSON metadata (Stance: FOR/AGAINST).
- Create the REST APIs to serve the data to Yaksh's frontend.

### 2. Yaksh (Graph Architect & Frontend Developer)
**Role:** Neo4j Database & Frontend UI.
*Why:* If he is the logic guy, he should focus entirely on how the debate tree visually and physically connects.
**Tasks:**
- **Neo4j Graph Database:** He learns Neo4j and Cypher queries. He takes your clean JSON data and figures out how to link the nodes together in the database.
- **Frontend App:** He builds the React/Flutter UI for recording videos and viewing the feed.
- **Graph Visualization:** He integrates D3.js or React Flow on the frontend so users can visually navigate the debate tree.

### 3. Ridhima (Python Data Scripter)
**Role:** Raw Data Extraction.
*Why:* Perfect for a beginner. She writes isolated scripts that don't touch your core server.
**Tasks:**
- Write a Python script to strip audio from an uploaded video and send it to the **OpenAI Whisper API** for the transcript.
- Pass this text data to Sahibnoor's Spring Boot server.

### 4. Jasmine (Data Operations & QA)
**Role:** Ground Truth Engineering & Documentation.
*Why:* Keeps her off the codebase entirely while securing your grades.
**Tasks:**
- **Dataset Collection:** Scrape and manually record 20-30 short political opinion videos for the feasibility study.
- **Manual Annotation:** Watch all videos and manually classify them (FOR/AGAINST/UNRESOLVED) to create the Ground Truth dataset.
- **Documentation:** Write the final project report, format the presentations, and do the math for the Fleiss' Kappa scoring.

---

## Prototype 1: The Manual Feasibility Spike (Days 1-4)
*Goal: Prove the graph works without building a full app.*
1. **Jasmine** downloads 20 videos on one topic.
2. **Ridhima** runs a basic Python script to turn those 20 videos into 20 text transcripts.
3. **Sahibnoor** pushes those 20 transcripts through his Gemini prompts to get the stances.
4. **Yaksh** takes that data and manually maps the 20 nodes into Neo4j to generate a visual graph for the professor.

## Prototype 2: Full Automation (Weeks 2-3)
*Goal: Connect the UI and automate the pipeline.*
- **Yaksh** finishes the upload UI.
- Video upload triggers **Ridhima's** script automatically.
- Text goes to **Sahibnoor's** Spring Boot server.
- Server pings Gemini, gets the stance, and pushes it to **Yaksh's** Neo4j database automatically.
- **Yaksh's** frontend displays the updated graph.
