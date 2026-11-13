# FORREST - Presentation Outline (Planning & Features)

*Use this outline to build your PowerPoint/Google Slides presentation. Each section represents a distinct slide.*

---

## Slide 1: Title Slide
**Title:** Project FORREST
**Subtitle:** A Structured, AI-Driven Video Debate Ecosystem
**Presenters:** [Your Names]

---

## Slide 2: Core Vision & The Graph Structure
**Header:** Transforming Chaos into Structured Debate
*(Note: Briefly breeze through this since the professor already knows the core concept)*
- **The Vision:** Moving away from endless, dopamine-driven scrolling and toxic comment sections into a structured, trackable video knowledge tree.
- **The Graph:** 
  - **Root Node:** A conversation starts with a single video opinion.
  - **Branches (Replies):** Users reply with face-camera videos.
  - **AI Classification:** The AI automatically groups replies into **FOR**, **AGAINST**, or **UNRESOLVED**.

---

## Slide 3: Key Features & Solutions
**Header:** Addressing the Hard Questions
- **Stance-Agnostic System:** The AI doesn't judge who is "right"; it neutrally maps the structure of the debate.
- **Semantic Clustering:** Grouping similar topics together using embeddings (e.g., grouping "Vanilla" and "Chocolate" under "Classic Ice Cream").
- **Standalone Reach:** A reply video isn't hidden in a comment section; it can go viral independently on the main feed and act as a new Root Node.

---

## Slide 4: The Workflow Pipeline (Visual Graph)
**Header:** The AI Processing Pipeline
*(Visual Note: Display this slide as a flowchart/graph)*
1. **Video Upload:** User uploads a face-camera video.
2. **Audio Extraction:** Audio is sent to **OpenAI Whisper API** to generate a highly accurate text transcript.
3. **Frame Sampling:** Video frames are extracted and sent to **Google Gemini API** (Multimodal).
4. **NLP & Vision Processing:** Gemini analyzes the transcript and frames to detect Claims, Stance, On-Screen Subtitles, and Visual Context.
5. **Graph Storage:** Data is stored in our **Neo4j Graph Database** to build the tree.

---

## Slide 5: Child Mode, NSFW & Abuse Prevention
**Header:** Ensuring a Safe, Toxicity-Free Environment
- **Multimodal AI Safety:** Gemini API scans both the extracted video frames and the transcript simultaneously.
- **NSFW & Abuse Detection:** AI automatically detects nudity, violence, or inappropriate visual content before the video goes live. Preventing abuse is fundamentally built into the pipeline.
- **Child Mode Integration:** 
  - AI flags explicit language or adult-themed keywords in the transcript.
  - When "Child Mode" is enabled, the algorithm automatically prunes those flagged branches, making FORREST the #1 safest platform for kids and students.

---

## Slide 6: The "IT Cell" & Spam Prevention Strategy
**Header:** Redefining Anti-Spam (Breaking the Echo Chamber)
- **What is an "IT Cell" to us?** We define it not as a specific political group, but as *any coordinated attempt to overload the algorithm* from any side of an argument.
- **We Don't Silence; We Balance:** We don't stop people from posting. Instead, we prevent algorithmic manipulation.
- **The 50/50 Epsilon-Greedy Feed:** 
  - **50% User Interests:** Shows content the user actively follows and engages with.
  - **50% Diverse/New Feed:** Actively injects opposing stances and new topics.
- **The Result:** Even if bots spam one side of an argument, the 50/50 algorithm guarantees that the user still sees the opposing side, completely shattering the echo chamber.

---

## Slide 7: Addressing AI Bias & Infrastructure Scaling
**Header:** Why AI Bias Doesn't Matter Here
- **The Frozen Inference Model:** We use enterprise LLMs via API (Whisper/Gemini). The model's weights are locked. It does not "learn" or absorb bad habits from biased user uploads.
- **Stance, Not Truth:** The AI's job is not to decide the ultimate truth; its job is to accurately classify the *stance* (FOR/AGAINST) and map the argument.
- **Scaling & Funding:** With initial funding, we will scale our API limits and cloud infrastructure (AWS/GCP) to handle concurrent video processing, ensuring real-time graph updates without latency.

---

## Slide 8: Scaling Phases
**Header:** Technical Execution Timeline
- **Phase 1:** Core Video Platform Foundation (Uploads, Replies, Profiles).
- **Phase 2:** Transcription & Search Engine Integration.
- **Phase 3:** Stance Classification & Graph Database Implementation.
- **Phase 4:** Credibility Scoring & Community Moderation Queues.

---

## Slide 9: Future Roadmap, Monetization & User Acquisition
**Header:** Taking on Instagram & Shorts
- **The Goal:** Build an interesting, knowledge-and-fact-based environment without the toxicity of current short-form platforms.
- **User Acquisition (The Instagram Bridge):** To seamlessly transition users, we will implement a feature allowing users to import/link reels directly from Instagram. These imported reels will act as Root Nodes to kickstart FORREST debates.
- **Monetization Pattern:**
  - **Premium Verified Accounts:** For creators and journalists wanting deeper analytics and verified badges.
  - **B2B API Licensing:** Selling our argument-mapping NLP pipeline to news organizations or educational institutions.
  - **High-Signal Ads:** Because our audience is engaged in deep, structured thought (Top 20% knowledge workers), we can serve high-CPM, targeted educational and tech advertisements without interrupting the debate tree.
