/** Runtime bindings plus secrets configured outside version control. */
export type GatewayEnv = Omit<
  Env,
  "USAGE_DB" | "USAGE_LIMIT_MODE" | "MONTHLY_AI_UNIT_LIMIT" | "MONTHLY_AI_WARNING_FRACTION"
> & {
  USAGE_DB?: D1Database;
  APP_PROXY_TOKEN?: string;
  OPENAI_API_KEY?: string;
  /** Set to the literal string "false" to stop AI requests without an app update. */
  AI_ENABLED?: string;
  /** off = no tracking, shadow = track without blocking, enforced = block at the cap. */
  USAGE_LIMIT_MODE?: string;
  /** Weighted token units; one input token = 1 and one output token = 4. */
  MONTHLY_AI_UNIT_LIMIT?: string;
  /** Decimal fraction from 0 to 1. Defaults to 0.8. */
  MONTHLY_AI_WARNING_FRACTION?: string;
};
