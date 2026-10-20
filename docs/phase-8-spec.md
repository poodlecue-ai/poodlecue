# Phase 8 — AI shadow mode

Phase 8 compares the proven local cue policy with an AI candidate without allowing cloud latency or failure to affect the cue the user hears.

## Runtime policy

- The local policy remains the only source of spoken cues.
- After a complete **Them** turn, the app sends only the compact text turn, the previous **Me** turn, an optional user-reviewed memory, and recent cue text.
- The AI never sees the local candidate, keeping the comparison independent.
- Raw audio and the full transcript are never sent.
- The server uses the OpenAI Responses API with Structured Outputs and `store: false`.
- The silent AI comparison is cancelled after roughly 8 seconds. A failure never changes the local cue.
- The AI candidate is displayed silently for side-by-side evaluation.
- The phone stores only aggregate preference, latency, silence, and failure metrics; no transcript is attached to evaluation data.

## Privacy boundary

The OpenAI API key exists only in the Railway service. It must never be placed in the iOS application or committed to Git. The beta app may use a separate revocable app token to limit casual access to the endpoint; this is not a substitute for per-user authentication in production.

## Evaluation gate

Collect at least 15 representative turns across positive news, difficult news, questions, work, family, fitness, travel, repetition, acknowledgements, and low-signal comments. Record whether the local cue, AI cue, or neither was preferable. AI cannot become the spoken path until it wins clearly on usefulness and stays acceptably fast and reliable.

## Railway variables

- `OPENAI_API_KEY`
- `OPENAI_MODEL` (defaults to `gpt-6-luna`)
- `POODLECUE_APP_TOKEN` (a long random beta token)

After deployment, set the Xcode build settings `AI_SHADOW_ENDPOINT` to the full `/v1/cue-shadow` URL and `AI_SHADOW_APP_TOKEN` to the matching beta token.
