const MAX_FIELD_LENGTH = 1200;

export const REALTIME_INSTRUCTIONS = [
  "Create a private cue that helps the user continue a real conversation.",
  "Use only facts in the supplied turn and do not change the subject.",
  "Prefer a curious follow-up about the exact experience, feeling, reason, or obstacle—not advice or a solution.",
  "Do not recommend an app, tracker, product, schedule, habit, task, or solution unless explicitly mentioned or requested.",
  "A spoken cue must be the exact words the user can say next: one crisp clause of 2-8 words.",
  "Never begin with Ask, Acknowledge, Celebrate, Answer, Recall, Say, or Tell.",
  "Use plain spoken wording with no filler or repeated idea.",
  "Prefer silence for low-signal remarks, repetition, or when no directly grounded action exists.",
  "Return only the exact short cue, or the single word SILENCE. No JSON, label, explanation, or markdown.",
].join(" ");

export function sanitizePayload(body) {
  const clean = (value) =>
    typeof value === "string" ? value.trim().slice(0, MAX_FIELD_LENGTH) : "";

  const them = clean(body?.them);
  if (!them) throw new Error("them is required");

  return {
    them,
    me: clean(body?.me),
    memory: clean(body?.memory),
    recentCues: Array.isArray(body?.recent_cues)
      ? body.recent_cues.slice(-5).map(clean).filter(Boolean)
      : [],
  };
}

export function buildOpenAIRequest(payload, model) {
  return {
    model,
    store: false,
    reasoning: { effort: "low" },
    max_output_tokens: 180,
    input: [
      {
        role: "developer",
        content: [
          {
            type: "input_text",
            text: [
              "You are the silent comparison policy for PoodleCue, an in-ear social coach.",
              "Decide whether a cue would add real value after the other person finishes a thought.",
              "Prefer silence for acknowledgements, low-signal remarks, repetition, or when the user already asked the obvious question.",
              "When speaking, write the exact words the user can say next: one crisp clause of 2-8 words, warm, specific, and never robotic.",
              "Never begin with Ask, Acknowledge, Celebrate, Answer, Recall, Say, or Tell. Use plain spoken wording with no filler or repeated idea.",
              "Do not mention being an AI. Do not provide therapy, diagnosis, manipulation, or covert persuasion.",
            ].join(" "),
          },
        ],
      },
      {
        role: "user",
        content: [
          {
            type: "input_text",
            text: JSON.stringify({
              other_person: payload.them,
              users_previous_turn: payload.me || null,
              reviewed_memory: payload.memory || null,
              recent_cues: payload.recentCues,
            }),
          },
        ],
      },
    ],
    text: {
      format: {
        type: "json_schema",
        name: "poodlecue_shadow_cue",
        strict: true,
        schema: {
          type: "object",
          additionalProperties: false,
          properties: {
            should_speak: { type: "boolean" },
            cue: { type: "string" },
            intent: {
              type: "string",
              enum: ["empathy", "answer", "follow_up", "recall", "celebrate", "silence"],
            },
            reason: { type: "string" },
            confidence: { type: "number", minimum: 0, maximum: 1 },
          },
          required: ["should_speak", "cue", "intent", "reason", "confidence"],
        },
      },
    },
  };
}

export function buildRealtimeClientSecretRequest(model) {
  return {
    expires_after: {
      anchor: "created_at",
      seconds: 600,
    },
    session: {
      type: "realtime",
      model,
      output_modalities: ["text"],
      max_output_tokens: 20,
      instructions: REALTIME_INSTRUCTIONS,
    },
  };
}

export function extractOutputText(response) {
  for (const item of response?.output ?? []) {
    for (const content of item?.content ?? []) {
      if (content?.type === "output_text" && typeof content.text === "string") {
        return content.text;
      }
    }
  }
  throw new Error("OpenAI response did not contain output text");
}

export function normalizeCue(value, latencyMilliseconds) {
  const shouldSpeak = Boolean(value?.should_speak);
  const cue = shouldSpeak ? String(value?.cue ?? "").trim().slice(0, 160) : "";
  return {
    should_speak: shouldSpeak && cue.length > 0,
    cue,
    intent: String(value?.intent ?? "silence"),
    reason: String(value?.reason ?? "").trim().slice(0, 240),
    confidence: Math.max(0, Math.min(1, Number(value?.confidence) || 0)),
    latency_ms: Math.round(latencyMilliseconds),
  };
}
