# Sahibnoor Singh's Journal

I am the team leader. I worked on the main server connection and the database logic.
In the first few weeks, I figured out how to connect our project to the Gemini API so we can process transcripts easily.
I also set up the graph database so we can store opinions properly without losing data.

I make sure the team stays on track and I combine everyone's code into the main project at the end of the week.

Below is a dated log of what I actually did, taken from our commit history.

## August 2026: the first website prototype

**11 to 19 August.** I started the repository and built the first version of the FOREST website: an admin dashboard where content can be added, edited and deleted, a custom favicon, and a roadmap page showing the ten phases of the project. The part that took longest was the presentations page. Our plan was to show slide decks inside the site, so I tried an Office embed, then Google's viewer, then a browser PowerPoint renderer, and found each one either looked wrong or showed someone else's branding. I settled on converting each deck to PDF on the server and showing it with pdf.js, then fixed the layout so the controls never cover the slides. I also restricted the viewer to logged-in admins. I marked **Prototype 1.0 complete on 19 August**.

**25 August.** I added the debate graph screen, moved the graph pipeline onto its own testing page, set up a Neo4j Aura graph database, and added a Spring Boot backend to the repository for deployment. This is the graph database mentioned above. It holds the debate tree: which video is a reply to which, and on which side.

## September 2026: AI pipeline, proposal and deployment

**13 to 15 September.** This was our busiest stretch as a team.
- Merged the Gemini Flash transcription work through three pull requests, and fixed a Spring Boot address setting that had been overwritten when branches were combined.
- Wrote the project Gantt chart, and added the proposal and the feasibility report.
- Set up automatic deployment with GitHub Actions to our Oracle cloud server, so a push to `main` updates the live site.
- Built the "AI Lab" page: a live view of the pipeline as it runs, with a log panel and a transcript viewer, and a layout the user can resize.
- Gemini's free limits kept running out, so I made the backend try several Gemini models in order and fall back to a second API key when one is exhausted.
- Protected our data: removed the database and uploaded media from version control, added two rolling snapshots of the SQLite database with automatic recovery, and fixed a bug where re-uploading could clash on an existing ID.
- Fixed smaller problems: the admin publish button failing silently because of a missing database column, and expired logins leaving the page stuck.

**22 September.** First commits of the Flutter mobile app. From here the project moves from a website to an Android app.

## October 2026: the mobile app

**10 to 15 October.** I built the app's Home screen against our API contract: the feed of opinion cards, replying by recording, choosing from the gallery or typing, a thread view with nested replies, likes, and report and block from a menu. I also built the colour theme (light and dark), a video cache and player pool so scrolling stays smooth, and handling for when the server is busy. On 12 October I merged Yaksh's Discover reels page into the app. By 13 October there was login and sign-up, and I added seed scripts and a shared snapshot so that any teammate sees the same demo data. On 14 October I added subtitles: Gemini returns timed caption lines with the transcript, the language is detected, English captions are made, and the viewer has a language picker (Off, Original, English, Hindi, Punjabi and others).

**17 October.** The post editor, on both the server and the app. A person can make a video, photo slideshow or text post, trim and crop, add music from the phone, put text over the picture, and choose a colour look. The server renders the result with FFmpeg. I also made text in Hindi and Punjabi draw correctly.

**19 to 22 October.** A large week of features:
- Discover: a grid ranked for each person, search over posts and accounts, sending a video to a friend, and a feed that learns a little from what friends send.
- Messages inbox, report with a reason, block, and a list of blocked accounts.
- Sign-up by an e-mailed code, instead of paid SMS, and Continue with Google, with the server checking Google's token itself.
- Onboarding for new users, and a redesigned login and sign-up.
- The question of the day, a "waiting for an answer" strip for opinions nobody has replied to, debate rooms where a society argues one motion, and invite codes.
- Product events and a private numbers page for the team.

**27 October.** Merged Yaksh's profile page into the main app (pull request 7) and joined it with the Account tab.

## November 2026: polish, review and hosting

- A polish pass on the video screen and Home, a notifications list with a badge, and clearer wording when something fails, so users never see a raw error.
- Wrote the files to host the server on a cloud machine: a Docker setup with automatic HTTPS, nightly backups, an update script, a settings check, and a cost estimate. These are written and checked but not yet run on a real machine.
- Reviewed the new server code for bugs and fixed ten of them: a limit on rooms that counted finished rooms, wrong dates for a different time zone, suspended accounts still visible, blocked people appearing in lists, counts that did not match what was shown, and a slow profile page. Each fix has its own automated test.
- The project now has about 365 automated tests on the server and about 540 in the app, and they all pass.

## Working with the team

I keep the main branch up to date and merge each person's branch into it, and when a merge touched someone else's files I wrote them a short note on what changed. Yaksh's Discover and profile work and Ridhima's audio clean-up script both went in through this process. The next step on my side is hosting the server so the team can test the app on real phones.
