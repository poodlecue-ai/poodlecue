# Phase 6 — Everyday conversation mode

Phase 6 turns the technical prototype into a usable conversation loop while retaining the diagnostics screen.

## Main flow

1. Choose a saved person or type a new name.
2. Review the last approved memory before starting.
3. Start with the validated **Phone mic** route by default.
4. Receive a private opening cue based on saved context.
5. Label the current speaker **Them** or **Me** while automatic speaker identification remains experimental.
6. Review a short memory draft and explicitly save it for next time.

## Memory-aware rules

Saved topics produce concise deterministic opening cues for fitness, family, work/study, and travel. When a new utterance shares one of those topics with the saved memory, the live cue invites a follow-up about what changed since the previous conversation.

No generative model or backend is used. Audio and full transcripts remain ephemeral, and only an approved note is protected in the app sandbox.

## Navigation

The app opens to the simplified **Conversation** tab. The existing latency, speech detection, transcription, route, and tone tests remain available under **Diagnostics**.
