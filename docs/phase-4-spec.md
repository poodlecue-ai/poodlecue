# Phase 4 specification

## Objective

Turn live on-device transcript changes into a small set of short, natural conversational cues without calling a language model or backend.

## Behavior

- Wait for a detected utterance to return to quiet.
- Inspect only the newly transcribed portion of the conversation.
- Select a curated cue for common topics such as fitness, work, travel, plans, relationships, and questions.
- Throttle cues so the assistant does not interrupt constantly.
- Optionally speak the cue through the active audio route.
- Suppress microphone analysis while the cue voice is playing to prevent a transcription feedback loop.

## Privacy

Cue selection is deterministic and runs entirely in memory on the iPhone. No transcript, cue, or audio is saved or transmitted.

## Test procedure

1. Start a session with **Speak cues** enabled.
2. Say: “I started training at this gym last month.”
3. Pause until the activity state returns to **Quiet**.
4. Confirm the cue is “Ask what they’re training for.”
5. Verify rule-generation and voice-start timing appear.
6. Continue with work, travel, and weekend sentences.
7. Stop and restart the session and confirm the cue count resets and the microphone remains responsive.

## Limitations

- There is no speaker identification yet, so the detector cannot distinguish the wearer from another person.
- The spoken system voice is a delivery prototype, not the final voice design.
- Rules cover only a small initial set of conversational topics.
