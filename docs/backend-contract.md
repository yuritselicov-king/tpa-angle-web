# Backend contract — machine-eye / RUGGLI TPA Angle Calculator

The frontend (`index.html`) talks to n8n webhooks, which read/write Postgres
(Neon). **These shapes are frozen** — the backend is built to them; do not
change field names without updating both sides.

- Base URL: `https://bpaus.app.n8n.cloud/webhook/`
- CORS allowed origin: `https://machine-eye.net`
- Content type: `application/json`
- Constants: `machine_type = "ruggli_tpa_angle"`, `machine_serial = "8311"`,
  lines `L40`–`L45`.
- Angle ids are the strings `"1"`…`"15"` inside every JSON object.
- **No secrets in the frontend.** The vision model, DB credentials and any API
  keys live only in n8n.

Severity (`sev`) is derived from `max(|Δon|, |Δoff|)`:
`0 = match`, `≤15 = tiny`, `≤60 = minor`, `>60 = major`.

---

## 1. `POST …/webhook/save-reading`

Persists one technician reading → `angle_readings`.

**Request body:**
```jsonc
{
  "id": "local-1737890000000",
  "machine_type": "ruggli_tpa_angle",
  "machine_serial": "8311",
  "line": "L40",
  "engineer_id": "yuri",
  "engineer_name": "yuri",
  "timestamp": "2026-07-26T12:00:00.000Z",   // ISO
  "tampon_type": "SUPER",
  "source": "manual",                         // "manual" | "photo"
  "reference_set": { "3": { "on": 280, "off": 320 }, "...": {} },
  "live":          { "3": { "on": 281, "off": null }, "...": {} },
  "drift":         { "3": { "dOn": 1, "dOff": 0, "max": 1, "sev": "tiny" }, "...": {} },
  "anomaly": {
    "is_anomaly": true,
    "major": 0,
    "minor": 1,
    "flags": [ { "angle": 4, "name": "CAMERA", "delta": 22 } ]
  },
  "changes_since_previous": [
    { "angle": 4, "field": "on", "from": 130, "to": 152 }   // field: "on" | "off"
  ],
  "logs": { "text": "", "attached": false },
  "image_ref": null
}
```

**Response:** `{ "ok": true, "id": "…" }`

Notes:
- `live[id].on` / `.off` are numbers or `null` (angle not read).
- The frontend always caches the reading in `localStorage` first, so a failed
  POST never loses data.

---

## 2. `GET …/webhook/get-history?line=Lxx`

Returns saved readings for one line, **newest first**.

**Response:** either a bare array or `{ "readings": [ … ] }`. Each element has:
```
id, line, engineer_id, engineer_name, timestamp, tampon_type, source,
reference_set, live, drift, anomaly, changes_since_previous, logs
```
The client dedupes backend rows against its local cache by `id`.

---

## 3. `POST …/webhook/extract-angles`  (vision)

One image → extracted angles. Called **once per photo**; the client merges
results across multiple photos (later photos win per angle).

**Request body:**
```jsonc
{
  "machine_type": "ruggli_tpa_angle",
  "line": "L40",
  "image_base64": "<base64 without data: prefix>",
  "mime": "image/jpeg"
}
```

**Response:**
```jsonc
{
  "angles": {
    "3": { "on": 280, "off": 320, "confidence": 0.94 },
    "4": { "on": 131, "off": 149, "confidence": 0.52 }
  },
  "screen": "base",        // "base" | "actual" | "unknown"
  "source": "photo"
}
```

Notes:
- `confidence < 0.6` on an angle makes the client flag that ON/OFF field amber
  (**low-confidence**) for the technician to double-check.
- `screen` distinguishes the red **BASE ANGLE** screen from the blue **ANGLE AT
  MACHINE** screen. "Set reference from photo" expects `base`; live capture
  expects `actual`.

---

## 4. `POST …/webhook/save-reference`  (optional — reference versioning)

Records a new **BASE reference** version for a line → `angle_references`
(append-only; newest `version` per line is current). Sent when a technician sets
a reference from a photo or locks a manual edit. If this endpoint is not
configured, the reference is still saved locally.

**Request body:**
```jsonc
{
  "machine_type": "ruggli_tpa_angle",
  "machine_serial": "8311",
  "line": "L40",
  "engineer_id": "yuri",
  "engineer_name": "yuri",
  "set_by": "yuri",
  "timestamp": "2026-07-26T12:00:00.000Z",
  "source": "photo",                        // "photo" | "manual-edit"
  "reference_set": { "3": { "on": 280, "off": 320 }, "...": {} }
}
```

**Response:** `{ "ok": true, "line": "L40", "version": 2 }`

---

## 5. `POST …/webhook/parse-logs`  (optional)

Free-form machine log text/image in → parsed structure out. Not required for
core operation.
