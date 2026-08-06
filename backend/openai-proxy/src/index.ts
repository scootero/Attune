import { handleRequest } from "./handler";

interface Env {
  APP_PROXY_TOKEN?: string;
  OPENAI_API_KEY?: string;
  AI_ENABLED?: string;
}

export default {
  async fetch(request, env): Promise<Response> {
    return handleRequest(request, env, fetch);
  },
} satisfies ExportedHandler<Env>;
