# FORREST - Logic, Vision & Roadmap

## Vision
To transform online conversations from endless scrolling into structured, credible, trackable trees.
Unlike traditional social media apps, where discussions are driven by random algorithms or disorganized comment sections, FORREST organizes all conversations in a living tree where the AI performs the following tasks:
1. Categorizes data
2. Verifies information
3. Filters junk and spam
4. Discovers valuable information and perspectives

## The Core Mission
We are building a research-focused argument analysis system and video platform designed to ensure truth and facts prevail. It is designed to combat echo chambers and political IT Cell propaganda.

- **The Concept:** Users post short face-camera opinion videos on trending topics (specifically political opinions and current affairs). Other users reply, creating a branching debate tree.
- **Target Audience:** The Top 20% of internet users (knowledge workers, students, professionals) who want high-signal, low-noise content. We are not competing with TikTok for cheap dopamine.

## Problem & Solution
**Problem in normal social media:**
- Discussions become chaotic.
- Valuable perspectives get buried.
- Fake information spreads quickly.
- Spam and junk content dominate.
- Group discussions feel impossible to follow.

**Solution (The Graph Structure):**
- Every conversation begins as a root video.
- Every response becomes a branch (Child node).
- AI continuously organizes, verifies, summarizes, and ranks the discussion.
- A knowledge tree is formed, allowing users to track all perspectives (whether desired or undesired).
- By swiping left or right, users can explore opposing sides of an argument.

## Platform Comparison

| Feature | Instagram | X (Twitter) | Reddit | FORREST |
|---------|-----------|-------------|--------|---------|
| **Primary Content** | Photo and Video (Short form) | Text and Threads | Text Discussions | Video Discussions |
| **Reply Type** | Comments - Texts | Text Replies | Text | Video Replies |
| **Structure to Track** | Plain Comments | Plain Reply Threads | Nested Threads | Visual Tree Structure |
| **Organization of Data** | Not Organized | Not Organized | Community Based | AI Clusters Similar Arguments & Topics |
| **Ease to Follow** | ❌ | ❌ | Partially | Visual Navigation |
| **Categorisation** | ❌ | ❌ | Through Flairs (Manually) | Automatic |
| **Best For** | Sharing moments and entertainment | Real-time opinions | Community discussions | Structured debates and conversation |

## Roadmap Phases

### Phase 1 - Foundation
**Creating a video discussion platform**
A platform where users express ideas via video. Instead of a standard comment section, users have visual discussions.
- User profiles, login, registration
- Video upload & video replies
- Root video assignment
- Interactive tree interface
- Basic moderation (likes, notifications, interests, trending)

### Phase 2 - AI Transcript Engine & Search Engine
**Videos and discussions become searchable**
- **Pipeline:** Video -> Speech Recognition -> Transcript -> Language Detection -> Keyword Extraction
- **Features:** Speech-to-text, Language Detection, Transcript Generation, Caption Generation.

### Phase 3 - AI Classification Engine
**Structural Reply Classification**
AI analyzes transcripts and classifies them structurally instead of randomly.
- *Example:* A Root video discusses Monuments. AI groups child nodes into "Indian" and "Roman". Under "Indian", sub-nodes branch into "Taj Mahal" and "Qutub Minar".
- *Example 2:* A debate on "Is CJP Protest Constitutional?" is split into "FOR" and "AGAINST" branches.

### Phase 4 - Credibility Engine
**Verification & Scoring**
Every upload passes through an AI pipeline:
- Video -> Transcript -> Claim Detection -> Fact Verification -> Evidence Searching -> Credibility Score.
- Videos are flagged with scores (0-100) or labels like: Verified, Mostly Accurate, Opinion, Misleading, Unverified.

### Phase 5 - Anti-Spam Engine
**Content Quality Ranking**
- High-quality replies are kept closer to the trunk (root); low-quality replies sink.
- Removal of spam, bots, duplicate videos/transcripts, hate speech, NSFW, AI-generated views, and misinformation.
- Users receive a Reputation Score based on: Content Quality, Credibility History, Community Feedback, Spam Violations, and Constructive Participation.

### Phase 6 - Shared Collaborative Trees (Private Trees)
**For Personal & Group Use**
- Users can create private trees to share and discuss topics with specific groups (college projects, company meetings, event planning).
- Offers privacy modes: Public, Private, Invite Only, Organization.
- Far more efficient and trackable than random WhatsApp or Slack discussions.

## Community-Driven Moderation
- **Unresolved Queue:** If AI cannot classify a stance, the community votes (e.g., 20 votes with >70% agreement reclassifies it).
- **Community Reporting:** Users can flag videos (Factless, Misleading, Off-Topic, Hate Speech, Deepfake).
- **AI-Assisted Report Verification:** If flagged multiple times, AI re-analyzes the transcript. If Fact/Truth scores fall below a threshold, the video is demoted or removed.
