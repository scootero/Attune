import { handleRequest } from "./handler";
import type { GatewayEnv } from "./env";

export default {
  async fetch(request, env): Promise<Response> {
    return handleRequest(request, env, fetch);
  },
} satisfies ExportedHandler<GatewayEnv>;
