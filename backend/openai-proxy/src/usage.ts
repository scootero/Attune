import type { GatewayEnv } from "./env";

export const USAGE_PATH = "/v2/usage";
export const INSTALLATION_ID_HEADER = "X-Attune-Installation-Id";

const DEFAULT_MONTHLY_UNIT_LIMIT = 10_000_000;
const DEFAULT_WARNING_FRACTION = 0.8;

export type UsageSnapshot = {
  usedUnits: number;
  limitUnits: number;
  warningAtUnits: number;
  warning: boolean;
  limited: boolean;
  resetsAt: string;
  period: string;
};

export type UsageReservation = {
  installationHash: string;
  period: string;
  reservedUnits: number;
  snapshot: UsageSnapshot;
};

export class UsageRequestError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code: string,
    readonly snapshot?: UsageSnapshot,
  ) {
    super(message);
  }
}

export function usageMode(env: GatewayEnv): "off" | "shadow" | "enforced" {
  const value = env.USAGE_LIMIT_MODE?.trim().toLowerCase();
  if (value === "shadow" || value === "enforced") return value;
  return "off";
}

export async function usageSnapshotForRequest(
  request: Request,
  env: GatewayEnv,
  now = new Date(),
): Promise<UsageSnapshot | null> {
  const mode = usageMode(env);
  if (mode === "off") return null;
  const installationHash = await installationHashForRequest(request, mode === "enforced");
  if (!installationHash) return null;
  const snapshot = await loadSnapshot(env, installationHash, now);
  return mode === "enforced" ? snapshot : { ...snapshot, limited: false };
}

export async function reserveUsage(
  request: Request,
  env: GatewayEnv,
  estimatedUnits: number,
  now = new Date(),
): Promise<UsageReservation | null> {
  const mode = usageMode(env);
  if (mode === "off") return null;

  const installationHash = await installationHashForRequest(request, mode === "enforced");
  if (!installationHash) return null;
  const db = requireDatabase(env);
  const limitUnits = monthlyLimit(env);
  const warningAtUnits = warningAt(env, limitUnits);
  const period = periodKey(now);
  const resetsAt = nextPeriodStart(now).toISOString();
  const reservation = Math.max(1, Math.ceil(estimatedUnits));

  if (mode === "enforced" && reservation > limitUnits) {
    const snapshot = await loadSnapshot(env, installationHash, now);
    throw limitError({ ...snapshot, limited: true });
  }

  const enforceClause = mode === "enforced"
    ? "WHERE ai_monthly_usage.units + excluded.units <= ?5"
    : "";
  const statement = db.prepare(`
    INSERT INTO ai_monthly_usage (
      installation_hash, period_key, units, request_count, updated_at
    ) VALUES (?1, ?2, ?3, 1, ?4)
    ON CONFLICT (installation_hash, period_key) DO UPDATE SET
      units = ai_monthly_usage.units + excluded.units,
      request_count = ai_monthly_usage.request_count + 1,
      updated_at = excluded.updated_at
    ${enforceClause}
  `);
  const result = mode === "enforced"
    ? await statement.bind(
        installationHash,
        period,
        reservation,
        now.toISOString(),
        limitUnits,
      ).run()
    : await statement.bind(
        installationHash,
        period,
        reservation,
        now.toISOString(),
      ).run();

  if (mode === "enforced" && result.meta.changes === 0) {
    throw limitError(await loadSnapshot(env, installationHash, now));
  }

  const snapshot = snapshotFromUnits(
    await currentUnits(db, installationHash, period),
    limitUnits,
    warningAtUnits,
    resetsAt,
    period,
  );
  return { installationHash, period, reservedUnits: reservation, snapshot };
}

export async function reconcileUsage(
  env: GatewayEnv,
  reservation: UsageReservation | null,
  actualUnits: number | null,
  succeeded: boolean,
  now = new Date(),
): Promise<UsageSnapshot | null> {
  if (!reservation) return null;
  const db = requireDatabase(env);
  const targetUnits = succeeded && actualUnits !== null
    ? Math.max(1, Math.ceil(actualUnits))
    : 0;
  const delta = targetUnits - reservation.reservedUnits;
  if (delta !== 0) {
    await db.prepare(`
      UPDATE ai_monthly_usage
      SET units = MAX(0, units + ?1), updated_at = ?2
      WHERE installation_hash = ?3 AND period_key = ?4
    `).bind(delta, now.toISOString(), reservation.installationHash, reservation.period).run();
  }
  return loadSnapshot(env, reservation.installationHash, now);
}

export function actualWeightedUnits(responseBody: ArrayBuffer): number | null {
  try {
    const value: unknown = JSON.parse(new TextDecoder().decode(responseBody));
    if (!isRecord(value) || !isRecord(value.usage)) return null;
    const promptTokens = value.usage.prompt_tokens;
    const completionTokens = value.usage.completion_tokens;
    if (!isNonnegativeNumber(promptTokens) || !isNonnegativeNumber(completionTokens)) return null;
    return Math.ceil(promptTokens + completionTokens * 4);
  } catch {
    return null;
  }
}

export function usageHeaders(snapshot: UsageSnapshot | null): HeadersInit {
  if (!snapshot) return {};
  return {
    "X-Attune-Usage-Used": String(snapshot.usedUnits),
    "X-Attune-Usage-Limit": String(snapshot.limitUnits),
    "X-Attune-Usage-Warning-At": String(snapshot.warningAtUnits),
    "X-Attune-Usage-Reset": snapshot.resetsAt,
    "X-Attune-Usage-Period": snapshot.period,
  };
}

export function usageModeHeader(env: GatewayEnv): HeadersInit {
  return { "X-Attune-Usage-Enforced": usageMode(env) === "enforced" ? "true" : "false" };
}

function requireDatabase(env: GatewayEnv): D1Database {
  if (env.USAGE_DB) return env.USAGE_DB;
  throw new UsageRequestError(
    "AI usage service is temporarily unavailable",
    503,
    "usage_service_unavailable",
  );
}

async function installationHashForRequest(
  request: Request,
  required: boolean,
): Promise<string | null> {
  const installationId = request.headers.get(INSTALLATION_ID_HEADER)?.trim() ?? "";
  if (!/^[A-Za-z0-9-]{16,128}$/.test(installationId)) {
    if (!required) return null;
    throw new UsageRequestError(
      "A valid installation identifier is required",
      400,
      "installation_id_required",
    );
  }
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(installationId));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function loadSnapshot(
  env: GatewayEnv,
  installationHash: string,
  now: Date,
): Promise<UsageSnapshot> {
  const db = requireDatabase(env);
  const limitUnits = monthlyLimit(env);
  const warningAtUnits = warningAt(env, limitUnits);
  const period = periodKey(now);
  const units = await currentUnits(db, installationHash, period);
  return snapshotFromUnits(
    units,
    limitUnits,
    warningAtUnits,
    nextPeriodStart(now).toISOString(),
    period,
  );
}

async function currentUnits(
  db: D1Database,
  installationHash: string,
  period: string,
): Promise<number> {
  const row = await db.prepare(`
    SELECT units FROM ai_monthly_usage
    WHERE installation_hash = ?1 AND period_key = ?2
  `).bind(installationHash, period).first<{ units: number }>();
  return row && isNonnegativeNumber(row.units) ? row.units : 0;
}

function snapshotFromUnits(
  usedUnits: number,
  limitUnits: number,
  warningAtUnits: number,
  resetsAt: string,
  period: string,
): UsageSnapshot {
  return {
    usedUnits,
    limitUnits,
    warningAtUnits,
    warning: usedUnits >= warningAtUnits,
    limited: usedUnits >= limitUnits,
    resetsAt,
    period,
  };
}

function limitError(snapshot: UsageSnapshot): UsageRequestError {
  return new UsageRequestError(
    "Monthly AI limit reached",
    429,
    "monthly_ai_limit_reached",
    { ...snapshot, limited: true },
  );
}

function monthlyLimit(env: GatewayEnv): number {
  return positiveInteger(env.MONTHLY_AI_UNIT_LIMIT) ?? DEFAULT_MONTHLY_UNIT_LIMIT;
}

function warningAt(env: GatewayEnv, limitUnits: number): number {
  const value = Number(env.MONTHLY_AI_WARNING_FRACTION);
  const fraction = Number.isFinite(value) && value > 0 && value < 1
    ? value
    : DEFAULT_WARNING_FRACTION;
  return Math.floor(limitUnits * fraction);
}

function positiveInteger(value: string | undefined): number | null {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

function periodKey(date: Date): string {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
}

function nextPeriodStart(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonnegativeNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}
