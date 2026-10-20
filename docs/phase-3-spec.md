# Phase 3 specification

## Objective

Prove that PoodleCue can turn the existing live microphone stream into useful partial text on the iPhone and measure time from detected speech onset to the first new transcription result.

## Privacy boundary

- Recognition is configured with `requiresOnDeviceRecognition`.
- The session fails closed when an on-device recognizer is unavailable.
- Audio and transcript text are held only for the active session.
- Nothing is written to disk or sent to a PoodleCue backend.

## Included

- Live partial transcription from the Phase 2 audio stream.
- Automatic locale selection with on-device support required.
- Latest, median, and p95 time-to-first-text measurements.
- A visible on-device indicator and active language model.
- Clean transcription teardown and recreation when a session restarts.

## Test procedure

1. Start a session and allow speech recognition when iOS asks.
2. Confirm the card says **On device** and shows a language model.
3. Speak a short sentence, pause until the activity card says **Quiet**, and repeat ten times.
4. Confirm partial text updates and record the first-text latest, median, and p95.
5. Stop and restart the session, then confirm transcription starts cleanly.

## Excluded

- Speaker identification.
- Semantic cue generation.
- Conversation or transcript storage.
- Cloud transcription and backend services.
