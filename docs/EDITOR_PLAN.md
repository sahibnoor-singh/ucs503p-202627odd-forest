# Post editor plan (Upload tab)

Status: **E1 (backend) and E2-E7 (the app) are done** (see `docs/api.md` → "Editor posts" and "What the app side turned out to need" below). Cover frame and the crop screen are built too. Owner: Sahibnoor (+ Claude). Profile/Account is Yaksh's and does not touch this.

## What exists today
- Upload tab = `app/lib/screens/upload_screen.dart`: camera record, post. Nothing else.
- Replies already have a chooser (`features/reply/reply_sheet.dart`: record / gallery / text).
- Backend `POST /api/posts` accepts only `VIDEO` (file, 50 MB, audio extraction then Gemini) and `TEXT` (replies only).
- ffmpeg is already bundled on the server (`ffmpeg-static`), so the server can render videos.

## Post modes (modelled on Instagram: Reels editor, Story text mode, photo carousel)
1. **Video**: record or pick; trim; mute original sound; add music from a file on the phone (with volume/mute); caption.
2. **Text**: a background (solid colours and gradients, a few animated gradients) and big text on top. Text can be still
   or animated (fade in, typewriter, slide up, word by word). Font + colour + alignment. Can add photos on top as proof.
3. **Photos**: 1 to 10 photos (reorder, crop, delete), optional music, shown as a swipeable set or a slideshow.
4. Every mode: caption, debate title (roots), who it replies to (replies), preview before posting.

## Key decision: render on the server
The client sends a small JSON "recipe" (mode, background, text, animation preset, photo files, music file, mute flag,
trim points). The server renders it into a normal MP4 with ffmpeg, then it goes through the existing pipeline like any
video. Why:
- Feed, viewer, cache, report/block and the AI pipeline stay exactly as they are (everything is still a video).
- No on-device video encoder dependency (`ffmpeg_kit_flutter` is discontinued; the forks are risky).
- Same result on every phone.
- Cost: the live preview is drawn with Flutter widgets, the final file with ffmpeg, so animation presets must be kept few
  and simple enough to look identical in both. Test each preset side by side.
- Text and photo posts have no speech, so the post's own text/caption is used as the transcript for stance and
  fact-check instead of audio (the audio step is skipped when there is no audio track).

## Tasks, in order
- ✅ E1 Backend (done): `POST /api/posts/compose` (recipe + files), render worker (ffmpeg: gradient/solid bg, drawtext
  animations, photo overlays, music mix with amix, mute, trim), reuse the job queue and 180 s deadline, size limits,
  tests. Document in `docs/api.md`.
- ✅ E2 App: editor shell in `app/lib/features/editor/` (tool bar, preview, Post button), replacing the Upload tab; the
  reply sheet opens the same editor (Record, Gallery, Photos, Text card).
- ✅ E3 Text mode: backgrounds, text styles, animation presets, preview, render check.
- ✅ E4 Photo mode: multi-pick (image_picker), reorder/delete, slideshow with fade or cut, timing, optional music. (No crop screen yet.)
- ✅ E5 Video mode: full-screen recorder or gallery pick, trim, mute, text on the picture, colour look, caption.
- ✅ E6 Music: pick an audio file (file_picker), volume, start point, preview; server mixes it.
- E7 Polish and tests: widget tests per mode ✅ (app suite, run with `flutter test`); emulator check of every mode ✅; **real-device
  check still to do** (the emulator's speed numbers are not trustworthy).

## Rules and risks
- Music is the user's own file. Fine for the closed alpha; before public launch we need licensing or a library of
  cleared tracks (platform and copyright risk, same family as the "no re-hosting other platforms' videos" rule).
- Photos used as proof can contain faces/people: reuse the existing report/block flow, no new moderation yet.
- Keep the 50 MB / 60 s limits and the per-user queue limits, so renders cannot be used to overload the server.
- Rank/streak/payout still gate on the credibility score, not on how many posts the editor makes easy.

## Not in this plan
Stickers, filters, voice-over, drawing, templates, collaborative posts, scheduled posts (later, after the alpha).

## What E1 turned out to need (differences from the first plan)
- **Text is drawn with ASS subtitles, not ffmpeg `drawtext`.** The bundled ffmpeg has no `drawtext`, but it has libass, which also gives word wrapping,
  outlines and animation. The app's live preview and the server's render must still be compared side by side for each animation preset.
- **Animation presets:** `none`, `fade`, `slideUp`, `typewriter` (letter by letter), `wordByWord`.
- **Added beyond the plan:** crop, colour adjustments (brightness, contrast, saturation, hue, blur) and up to 5 timed text overlays, on every mode.
- **Gradients** are a still pixel formula (ffmpeg's own gradient source rotates over time and is random per run).
- **Voice-only track:** for videos the speech is also written as a separate file before music is mixed in, so music does not confuse the transcript.
- **Limits:** 60 s, 10 photos, 5 overlays, 50 MB video / 15 MB music / 10 MB per photo, same per-person queue limit as other posts.
- The client contract is the recipe JSON in `docs/api.md`; the app can build it with a small `Recipe` class and send it as the `recipe` form field.

## What the app side turned out to need
- **Where things are:** `lib/features/editor/` — `recipe.dart` (mirrors the server's recipe rules and limits), `editor_controller.dart`
  (state and rules, no widgets), `editor_screen.dart` (shell, tool bar), `editor_panels*.dart` (one panel per tool), three previews
  (`text_post_preview`, `photo_post_preview`, `video_post_preview`), `overlay_layer.dart` (text on the picture), `adjust_filter.dart`
  (colour look), `record_page.dart` (recorder), `editor_pickers.dart` (system pickers behind an interface so tests need no phone).
- **The preview is Flutter widgets, the post is an ffmpeg render, so they were matched by measuring real renders:** libass letter width
  (about 0.855 of the font size) and line height (1.14), the 600 px wrap column with 60/70 px margins, the animation timings from
  `compose/ass.js`, the colour look as a colour matrix, and **line breaking**: libass evens the lines out ("Exams should / be open-book")
  and never breaks after a hyphen, so the preview lays text out in the narrowest width that gives the same line count and puts a word
  joiner after hyphens (`serverWrap`, `balancedWidth` in `overlay_layer.dart`).
- **Text in other scripts.** The server draws Latin, Hindi, Punjabi and emoji (`compose/scripts.js` switches to the right font per letter with an ASS `n`
  tag; libass will not find a missing letter in the fonts folder by itself, and colour emoji cannot be drawn, so emoji are one colour). The Text and
  Add-text panels warn only about scripts with no font (`lib/features/editor/letters.dart`). Tested against the Linux ffmpeg the server uses.
- **Crop** (Video, Photos): the box is dragged over the picture; shapes Free / 1:1 / 4:5 / 9:16 / 16:9. A video keeps the cropped shape; photos are cropped
  (the same part of each) and then fitted inside 9:16 on black. Geometry is in `crop_math.dart`, the box in `crop_editor.dart`.
- **Cover** (Video): a slider over the kept part picks the moment (`coverSec`); the server writes `coverUrl`, which the app shows in the feed card until the
  video can play, and in the small quoted-parent strip. Text and photo posts get an automatic cover.
- **Bug found by running it on a phone:** `package:http` uploads files as `application/octet-stream`, which the server refuses for photos. Every file now
  carries its own type (`uploadTypeOf` in `api_client.dart`).
- **Tests:** `editor_recipe`, `editor_posting`, `editor_text`, `editor_photos`, `editor_video`, `editor_extras`, `editor_reply`,
  `editor_wrap`, `editor_slideshow`, `editor_hardening` in `app/test/`.
