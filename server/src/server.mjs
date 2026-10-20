import http from "node:http";
import { buildOpenAIRequest, extractOutputText, normalizeCue, sanitizePayload } from "./cue.mjs";

const port = Number(process.env.PORT || 3000);
const model = process.env.OPENAI_MODEL || "gpt-6-luna";
const apiKey = process.env.OPENAI_API_KEY;
const appToken = process.env.POODLECUE_APP_TOKEN;

function send(response, status, body) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(JSON.stringify(body));
}

async function readJSON(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 16_384) throw new Error("request is too large");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

const server = http.createServer(async (request, response) => {
  if (request.method === "GET" && request.url === "/health") {
    return send(response, 200, { ok: true });
  }

  if (request.method !== "POST" || request.url !== "/v1/cue-shadow") {
    return send(response, 404, { error: "not found" });
  }

  if (!apiKey || !appToken) return send(response, 503, { error: "service is not configured" });
  if (request.headers.authorization !== `Bearer ${appToken}`) {
    return send(response, 401, { error: "unauthorized" });
  }

  try {
    const payload = sanitizePayload(await readJSON(request));
    const startedAt = performance.now();
    const upstream = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(buildOpenAIRequest(payload, model)),
      signal: AbortSignal.timeout(8000),
    });

    if (!upstream.ok) {
      const requestId = upstream.headers.get("x-request-id") ?? undefined;
      console.error("OpenAI request failed", { status: upstream.status, requestId });
      return send(response, 502, { error: "cue generation failed" });
    }

    const raw = await upstream.json();
    const parsed = JSON.parse(extractOutputText(raw));
    return send(response, 200, normalizeCue(parsed, performance.now() - startedAt));
  } catch (error) {
    const isInputError = error instanceof SyntaxError || error?.message === "them is required";
    console.error("Cue request failed", { name: error?.name, message: error?.message });
    return send(response, isInputError ? 400 : 504, {
      error: isInputError ? "invalid request" : "cue generation timed out",
    });
  }
});

server.listen(port, () => {
  console.log(`PoodleCue shadow service listening on ${port}`);
});
