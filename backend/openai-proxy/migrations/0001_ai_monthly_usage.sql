CREATE TABLE IF NOT EXISTS ai_monthly_usage (
  installation_hash TEXT NOT NULL,
  period_key TEXT NOT NULL,
  units INTEGER NOT NULL DEFAULT 0 CHECK (units >= 0),
  request_count INTEGER NOT NULL DEFAULT 0 CHECK (request_count >= 0),
  updated_at TEXT NOT NULL,
  PRIMARY KEY (installation_hash, period_key)
) WITHOUT ROWID;
