# machine-eye — RUGGLI TPA Angle Calculator

A single-file, mobile-first field tool for the **RUGGLI TPA** tampon machine
(serial **8311**). A technician reads the machine's *ANGLE MACHINE* touch-screen
values, the app compares them against a per-line **reference** ("BASE") set,
computes the drift for all 15 angles, and saves an audited reading (who changed
which angle) to a Postgres (Neon) backend through n8n webhooks.

**Live:** https://machine-eye.net

---

## What it is (and isn't)

- **One self-contained file:** [`index.html`](index.html) — inline CSS + vanilla
  JS. No build step, no framework, no bundler. Works offline.
- **Mobile-first**, max-width ~720px.
- **Trilingual** EN / RU / HE, with full RTL for Hebrew.
- **Persistence:** `localStorage`. Every reading is cached locally even when a
  backend is configured, so the tool is usable with no signal.
- Google Fonts is loaded from CDN and **degrades gracefully offline** (system
  fonts take over).
- A **soft login gate** (username `root`) sits in front of the app. It is a
  deterrent only — a static site's source is public, so it is *not* real
  security. The password is stored as a SHA-256 hash, never plaintext.

## Tabs

| Tab | Purpose |
|-----|---------|
| **Capture** | Engineer name, line **L40–L45**, tampon type, the editable per-line **reference** set, manual ON/OFF entry for all 15 angles, **Read photos** (multi-file → vision webhook), **Attach logs**, live per-angle Δ with severity. |
| **Calculate** | Severity counts, overall verdict, per-angle Δ, and "changes since last save". |
| **History** | Saved readings for the selected line (backend if configured, else local cache). |
| **Setup** | Engineer identity, the endpoint URLs, JSON export/import, and the payload contract. |

## The 15 angles & factory BASE reference

Defined in `index.html` (`const ANGLES`). ON/OFF degrees; ● = critical.

`1` STRING BLOWING AT FORMING TOOL 80/360 · `2` STRING BLOW AT DRUM 70/190 ·
`3` CHECK CORD + TAMPON 280/320 ● · `4` CAMERA 130/150 ● · `5` STRING BLOW
PROCESS AT CAMERA 200/300 · `6` PRESSING TOOL OUTPUSHER / AIR-CYLINDER 315/340 ·
`7` START TRANSFER TO MACHINE 130/150 · `8` START TUBES CONVEYOR (MOTOR) 310/340 ·
`9` PACKAGING DRUM CLAW DOWN/UP 100/200 · `10` START TUBES TRANSFER 0/0 ·
`11` WINDING DRUM REJECT 10/60 ● · `12` STOP POSITION 200/240 ·
`13` ANGLE 13 (SPARE) 0/0 · `14` WINDING DRUM BLOWING CLEAR 0/0 ·
`15` CLEANING SENSOR 350/360 ●

Angle **names stay in machine English** (they match the physical screen);
everything else is translated.

## Severity

From `max(|Δon|, |Δoff|)`:

| Δ | Severity |
|---|----------|
| 0 | match |
| ≤ 15 | tiny |
| ≤ 60 | minor |
| > 60 | major |

## Backend endpoints

Configured in the **Setup** tab. Base: `https://bpaus.app.n8n.cloud/webhook/`

| Purpose | Method | URL |
|---------|--------|-----|
| Save reading | `POST` | `…/webhook/save-reading` |
| Get history | `GET`  | `…/webhook/get-history?line=Lxx` |
| Vision extract | `POST` | `…/webhook/extract-angles` |
| Save reference *(optional)* | `POST` | `…/webhook/save-reference` |
| Parse logs *(optional)* | `POST` | `…/webhook/parse-logs` |

CORS: the backend allows origin `https://machine-eye.net`.

**No secrets live in the frontend.** The vision model runs server-side in n8n;
the DB password and any API keys exist only in n8n.

The full request/response shapes are in
[`docs/backend-contract.md`](docs/backend-contract.md); the database schema is in
[`docs/neon_schema.sql`](docs/neon_schema.sql).

## Enhancements

- **Base-angle capture** — set a line's reference from the red *BASE ANGLE*
  screen: **📷 Set from photo** (reuses the vision webhook, writes into that
  line's reference set) or manual **Edit reference → Lock**. Each change records
  `set_by` + timestamp locally and, if the reference endpoint is configured,
  POSTs a version to `angle_references`.
- **Low-confidence flag** — a photo-extracted angle returned with
  `confidence < 0.6` gets an **amber** ON/OFF field so the technician
  double-checks it. Editing the field clears the flag.

## Hosting & deploy

Served by **GitHub Pages** from `main` (repo root). The `CNAME` file binds the
custom domain `machine-eye.net`; GitHub auto-provisions the Let's Encrypt
certificate and enforces HTTPS.

**To update:**

1. Edit `index.html` (or the `docs/` files).
2. Commit and push to `main`:
   ```bash
   git add index.html
   git commit -m "…"
   git push origin main
   ```
3. GitHub Pages redeploys automatically (usually under a minute).

There is **no build step** — the file you commit is the file that ships. You can
also edit `index.html` directly on GitHub and commit in the browser.

## Local development

Open `index.html` directly in a browser (`file://`) or serve the folder with any
static server. The backend calls need the webhook URLs set in **Setup**; without
them the app runs fully on the local cache.
