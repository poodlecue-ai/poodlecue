import assert from "node:assert/strict";
import test from "node:test";
import { buildOpenAIRequest, extractOutputText, normalizeCue, sanitizePayload } from "../src/cue.mjs";

test("sanitizes a compact conversation payload", () => {
  const value = sanitizePayload({
    them: "  I got some great news  ",
    me: "Really?",
    recent_cues: ["Old", "Celebrate that"],
  });
  assert.equal(value.them, "I got some great news");
  assert.deepEqual(value.recentCues, ["Old", "Celebrate that"]);
});

test("builds a stateless structured OpenAI request", () => {
  const body = buildOpenAIRequest(
    sanitizePayload({ them: "I started a new role", local_cue: "Celebrate that" }),
    "gpt-6-luna",
  );
  assert.equal(body.store, false);
  assert.equal(body.text.format.strict, true);
  assert.equal(body.model, "gpt-6-luna");
  assert.equal(body.input[1].content[0].text.includes("local_candidate"), false);
  assert.equal(body.input[1].content[0].text.includes("Celebrate that"), false);
});

test("extracts and normalizes the structured cue", () => {
  const text = extractOutputText({
    output: [{ content: [{ type: "output_text", text: '{"should_speak":true,"cue":"That’s exciting—what comes next?","intent":"celebrate","reason":"Positive news","confidence":0.9}' }] }],
  });
  const cue = normalizeCue(JSON.parse(text), 321.4);
  assert.equal(cue.should_speak, true);
  assert.equal(cue.latency_ms, 321);
});

test("clears a cue when the model chooses silence", () => {
  const cue = normalizeCue({ should_speak: false, cue: "Do not show", confidence: 0.8 }, 10);
  assert.equal(cue.cue, "");
  assert.equal(cue.should_speak, false);
});
