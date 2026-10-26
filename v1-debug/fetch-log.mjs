// Logs each request's method, host, path and status, never headers, query strings or bodies.
// For a skill upload and any 4xx, it adds the response's top-level field names and types, not their values.
import { appendFileSync } from "node:fs";

const out = process.env.E2E_FETCH_LOG;
const original = globalThis.fetch;
globalThis.fetch = async (input, init) => {
  const request = new Request(input, init);
  const url = new URL(request.url);
  const response = await original(input, init);
  let shape = "";
  const upload = request.method === "POST" && url.pathname === "/registry/v1/artifacts/skill";
  if (upload || response.status >= 400) {
    try {
      const body = await response.clone().json();
      shape = ` fields=${Object.entries(body ?? {}).map(([key, value]) => `${key}:${Array.isArray(value) ? "array" : typeof value}`).join(",")}`;
      const said = body?.detail ?? body?.message ?? body?.error?.message;
      if (response.status >= 400 && typeof said === "string") shape += ` said=${JSON.stringify(said.slice(0, 200))}`;
    } catch {}
  }
  if (out) appendFileSync(out, `${request.method} ${url.host}${url.pathname} ${response.status}${shape}\n`);
  return response;
};
