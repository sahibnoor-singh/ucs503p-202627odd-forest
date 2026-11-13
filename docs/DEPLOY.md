# Putting the FOREST server on the internet (AWS or Oracle)

Written 2026-11-03. For the closed alpha and a small campus pilot: **one machine, one container for the API, Caddy in front for HTTPS.**
Everything here works the same on AWS (EC2 or Lightsail) and on Oracle Cloud, on x86 or ARM.

**What was and was not tested.** The server was run in production mode here (`NODE_ENV=production`, the files in `deploy/` checked: scripts
parse, `docker compose config` accepts the compose file, `npm run preflight` passes on a complete setting, `/api/health`, `/privacy`,
`/terms` answer, the dev-user header and the review page are refused without a token, a stop signal ends it cleanly). **The Docker image was not
built and Caddy was not started** (the machine this was written on has no Docker daemon). The first `docker compose up --build` on the real
machine is the first real test; the steps below say what to look at if it fails.

## 1. Which cloud? (short answer: Oracle for running it, AWS for the backup copy)

| | Oracle Always Free (ARM) | AWS Lightsail 2 GB | AWS EC2 t3.small |
|---|---|---|---|
| Price | $0 (while the free allowance holds) | about $12 a month | about $24 a month with disk, IP and some traffic |
| Videos sent out per month | 10 TB free | about 3 TB in the plan (check) | first 100 GB free, then about $0.11 per GB |
| Memory | up to 24 GB (the free ARM pool; one report says it was cut to 12 GB in 2026, check) | 2 GB | 2 GB |
| Catch | free machines can be reclaimed if idle for a long time; the ARM pool is sometimes "out of capacity" in a region; Oracle's console is slower to learn | credits end (see 8) | traffic is where the bill grows |

Honest advice: **run the API on Oracle's free ARM machine** (you already use Oracle), and use the **AWS credits for the safe copy** of your data (S3 is
about $0.25 a month for 10 GB) and for the e-mail sender (Amazon SES is about $0.10 per 1,000 mails). If you would rather have one cloud only, use
Lightsail 2 GB. Do **not** use the small Oracle "AMD micro" machine (1 GB): ffmpeg runs out of memory on it.

The current Oracle VM serves the old website through `.github/workflows/deploy.yml` (it replaces `/home/ubuntu/frontend` on every push to `main`).
Put the API on a **separate** machine so that deploy cannot touch it and so two programs do not fight for ports 80 and 443.

## 2. What you need before starting
- A machine: Ubuntu 22.04 or 24.04, at least **2 GB RAM** and **30 GB disk** (videos are about 12 MB each). Ports 22, 80, 443 open
  (Oracle: also in the VCN security list; AWS: in the security group).
- A name for the server, for example `api.forestapp.in`, and the right to add a DNS record for it. Point its **A record** at the machine's public
  IP (use a reserved or elastic IP so it does not change on a restart).
- A mail service for sign-up codes (Brevo free is about 300 a day), its SMTP login, and a sender address on a domain you control.
- A Gemini API key. **Use a paid-tier key for real users:** on the free tier Google may use what is sent to improve its products, and the daily
  limits are small (the code already falls back through several models).

## 3. Set up the machine (once)
```bash
ssh ubuntu@<the machine's ip>
git clone <this repository's address> forest && cd forest      # or copy the folder
bash deploy/setup_server.sh                                    # Docker, 2 GB swap, firewall, automatic updates, the data folder
# log out and in once, so `docker` works without sudo
```

## 4. Settings
```bash
cd ~/forest/deploy
cp .env.example .env              # DOMAIN=api.forestapp.in
cp api.env.example api.env        # fill in every line; secrets: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
docker compose run --rm api node scripts/preflight.js
```
`preflight` prints what is wrong in plain words and stops (exit 1) on anything that would make the server unsafe or unusable: dev mode, a weak
`JWT_SECRET`, no review token, console e-mail codes, a non-https address, a missing proxy setting, an unwritable data folder, no ffmpeg.
Fix every ERROR. WARNINGs are things you probably want (the Gemini key, the word list, the complaints contact, Google sign-in).

## 5. Start
```bash
docker compose up -d --build        # the first build takes a few minutes (it downloads ffmpeg for this machine's processor)
docker compose ps                   # api: healthy, caddy: running
curl https://api.forestapp.in/api/health     # {"ok":true,...}
```
If it does not come up:
- `docker compose logs --tail 100 api` (a refused setting is printed in the first lines);
- `docker compose logs --tail 100 caddy` (a certificate that cannot be issued almost always means the DNS record does not point here yet, or port 80/443 is closed);
- the image fails at `npm ci` on ffmpeg: the machine could not download it (no internet from the build), try again or set `FFMPEG_PATH`.

Then check it like a user: open `https://api.forestapp.in/privacy`, sign up in the app with your own e-mail (the code must arrive in the inbox, not
spam), post a video, watch it go Processing -> Ready, open `/admin` with your review token.

## 6. The phone app
The app must be built against this address (release builds refuse plain `http://` to a real host):
```bash
cd app
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.forestapp.in
```
Signing key, version number and the Play Console steps are in `docs/RELEASE.md`. For a friend's phone before the store: `flutter build apk --release
--dart-define=API_BASE_URL=https://api.forestapp.in` and send the file.

## 7. Day to day
- **Update:** `bash deploy/update.sh` (pulls, runs preflight, copies the database, rebuilds, restarts, waits for health). It prints the version it started.
- **Logs:** `docker compose logs -f api` (one line per request: method, path without query, status, milliseconds, short user id; never a body or token). They rotate by themselves.
- **Disk:** `df -h /` and `du -sh deploy/data`. Videos are never deleted automatically.
- **Is it up?** Add a free uptime monitor (UptimeRobot) on `https://api.forestapp.in/api/health`.
- **Backups:** make a private S3 bucket, an IAM user allowed only on it, `aws configure`, write `deploy/backup.env` with `BUCKET=...`, run
  `bash deploy/setup_server.sh` again (it installs the 02:30 nightly job). The script copies a consistent database snapshot (7 days kept on the
  machine) and sends new videos to S3 (they never change, so only new ones are sent).
- **Restoring** (do this once now, on purpose, before anyone depends on it):
  ```bash
  docker compose stop api
  aws s3 cp s3://BUCKET/db/forest-app-<stamp>.db data/forest-app.db
  aws s3 sync s3://BUCKET/uploads data/uploads
  sudo chown -R 1000:1000 data && docker compose start api
  ```
- **One process only.** The database is held in memory and written to one file, so never run two API containers on the same data folder.

## 8. What the AWS credits ($167) buy, and how long they last
Run `node deploy/cost_estimate.js` (change the numbers at the top, or `--users 40 --mbPerVideo 8`). Prices are Mumbai, read from third-party price lists in
November 2026: **check each on AWS's own pricing page.** The two things that decide the bill are not the computer, they are (a) how many MB of video
are sent to phones and (b) how long the credits last before they expire.

| Setup | Closed alpha, 15 people | 100 people |
|---|---|---|
| Oracle free machine + S3 backups on AWS | about $0.25 a month: the credits last as long as they are valid | same |
| AWS Lightsail 2 GB | about $12 a month: **about 13 months** if the credits last that long | same, if the 3 TB allowance is as I read it |
| AWS EC2 t3.small (+30 GB disk, IP, traffic) | about $24 a month: **about 7 months** | about $94 a month: **under 2 months** |
| AWS EC2 t3.medium | about $40 a month: **about 4 months** | about $111 a month: **under 2 months** |

Assumptions (all in the script, all changeable): each person watches 25 videos a day, a watched video is about 10 MB (a phone recording is not
shrunk: the server only takes the sound out for the AI), a person posts one video every two days. 15 people is about 110 GB of video a month, 100
people about 750 GB. Gemini's bill is separate (billed by Google, not from AWS credits): about half a cent per analysed video, so a few dollars a
month at pilot size.

Things that change the answer:
- **Credits expire.** AWS's own pages disagree on 6 or 12 months from the day the account was made, and a "Free plan" account is **closed after 6 months**
  unless you upgrade to a paid plan (you then keep the remaining credits). Look at Billing -> Credits for the real date. So $167 can never be spent
  slower than that date allows: a $12 plan wastes credits, a $40 plan uses them up in four months.
- **Shrinking videos to about 3 MB cuts the traffic bill by two thirds** (the 100-person t3.small bill falls from $94 to $36). That is the most
  valuable next engineering step (an ffmpeg compress step after upload); it is not built yet.
- **Set a budget alarm today:** Billing -> Budgets -> a monthly budget of $25 with an e-mail at 80%. A busy video day on EC2 can otherwise surprise you.
- Credits do not cover everything (domain registration, some marketplace items, support plans): the Credits page lists the exceptions.

## 9. Not done yet (so you are not surprised)
- Uploads sit on the machine's disk, not in S3 (fine for hundreds of people; the later move is in `CLAUDE.md`).
- No CDN and no video compression (see 8). No push notifications. No crash reporting. No staging copy.
- No automatic tests on push: run `cd app/backend && npm test` and `cd app && flutter test` yourself before `update.sh`.
- The ARM build of the image has not been run (the ffmpeg package ships ARM binaries; the first build on Oracle will show if anything is off).
- Alternative to Caddy: if you already run nginx on the machine, proxy to the API on `127.0.0.1:3000` with `client_max_body_size 60m;` and certbot, and
  publish the API's port in the compose file instead of using the `caddy` service.
