-- ============================================================================
--  machine-eye — RUGGLI TPA Angle Calculator
--  Neon / Postgres schema
--
--  Two tables:
--    angle_readings     — one row per saved technician reading (audit trail)
--    angle_references   — versioned BASE reference set per production line
--
--  The n8n webhooks (save-reading, get-history, save-reference) read/write
--  these. JSON sub-objects (reference_set, live, drift, …) are stored as JSONB.
--  Angle ids are strings "1".."15" inside the JSON to match the frontend.
-- ============================================================================

-- ---------------------------------------------------------------------------
--  Saved readings  (POST save-reading  →  INSERT here)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS angle_readings (
    id                      TEXT        PRIMARY KEY,           -- client id, e.g. "local-1737890000000"
    machine_type            TEXT        NOT NULL DEFAULT 'ruggli_tpa_angle',
    machine_serial          TEXT        NOT NULL DEFAULT '8311',
    line                    TEXT        NOT NULL,              -- 'L40'..'L45'
    engineer_id             TEXT,
    engineer_name           TEXT,
    reading_ts              TIMESTAMPTZ NOT NULL,              -- reading timestamp (ISO from client)
    tampon_type             TEXT,
    source                  TEXT        NOT NULL DEFAULT 'manual',   -- 'manual' | 'photo'

    reference_set           JSONB       NOT NULL,              -- { "3": {"on":280,"off":320}, ... }
    live                    JSONB       NOT NULL,              -- { "3": {"on":281,"off":null}, ... }
    drift                   JSONB       NOT NULL,              -- { "3": {"dOn":1,"dOff":0,"max":1,"sev":"tiny"}, ... }
    anomaly                 JSONB       NOT NULL,              -- { is_anomaly, major, minor, flags:[...] }
    changes_since_previous  JSONB       NOT NULL DEFAULT '[]', -- [ {angle, field, from, to}, ... ]
    logs                    JSONB       NOT NULL DEFAULT '{}', -- { text, attached }
    image_ref               TEXT,                             -- optional storage key/url

    -- convenience columns lifted out of anomaly for cheap filtering/sorting
    is_anomaly              BOOLEAN     GENERATED ALWAYS AS ((anomaly->>'is_anomaly')::boolean) STORED,
    major_count             INTEGER     GENERATED ALWAYS AS ((anomaly->>'major')::int) STORED,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- get-history is always "for one line, newest first".
CREATE INDEX IF NOT EXISTS idx_readings_line_ts   ON angle_readings (line, reading_ts DESC);
CREATE INDEX IF NOT EXISTS idx_readings_engineer  ON angle_readings (engineer_id);
CREATE INDEX IF NOT EXISTS idx_readings_anomaly   ON angle_readings (line, reading_ts DESC) WHERE is_anomaly;
CREATE INDEX IF NOT EXISTS idx_readings_created   ON angle_readings (created_at DESC);


-- ---------------------------------------------------------------------------
--  Versioned reference sets  (POST save-reference  →  INSERT here)
--  Append-only: each edit/photo-capture inserts a new version; the current
--  reference for a line is the row with the highest version (see view below).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS angle_references (
    id              BIGSERIAL   PRIMARY KEY,
    machine_type    TEXT        NOT NULL DEFAULT 'ruggli_tpa_angle',
    machine_serial  TEXT        NOT NULL DEFAULT '8311',
    line            TEXT        NOT NULL,                  -- 'L40'..'L45'
    version         INTEGER     NOT NULL,                  -- 1,2,3,… per line
    reference_set   JSONB       NOT NULL,                  -- { "3": {"on":280,"off":320}, ... }
    set_by          TEXT,                                  -- engineer who set it
    source          TEXT        NOT NULL DEFAULT 'manual-edit',  -- 'photo' | 'manual-edit'
    set_ts          TIMESTAMPTZ NOT NULL,                  -- when set (ISO from client)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (line, version)
);

CREATE INDEX IF NOT EXISTS idx_refs_line_version ON angle_references (line, version DESC);

-- Current reference per line (latest version).
CREATE OR REPLACE VIEW angle_references_current AS
SELECT DISTINCT ON (line) line, version, reference_set, set_by, source, set_ts
FROM   angle_references
ORDER  BY line, version DESC;

-- Helper for the save-reference webhook: next version number for a line.
--   INSERT ... version = (SELECT COALESCE(MAX(version),0)+1 FROM angle_references WHERE line = $1)
