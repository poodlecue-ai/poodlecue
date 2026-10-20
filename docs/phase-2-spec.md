# Phase 2 specification

## Objective

Prove that PoodleCue can monitor a consented live microphone session, detect speech activity locally, and surface detection timing without retaining conversation audio.

## Included

- Ten-millisecond live microphone buffers.
- Local RMS level analysis and speech/quiet classification.
- Speech-onset event count and timestamp-based latest, median, and p95 timing.
- Restart-safe timing that rejects stale audio-clock epochs and falls back to the active route's modeled input latency.
- A newly constructed audio engine graph for every session, preventing stale voice-processing I/O state after restart.
- Visible microphone level and listening state.
- In-memory processing only; buffers are discarded after analysis.

## Test procedure

1. Run on a physical iPhone and start the session.
2. Confirm that the microphone meter responds.
3. Speak for one to two seconds, pause for at least half a second, and repeat 20 times.
4. Confirm that each utterance creates one speech event.
5. Record the latest, median, and p95 detection estimates.

## Limitations

The current detector uses an intentionally simple fixed energy threshold. It is a pipeline and latency probe, not production-grade voice activity detection. It does not identify speakers, transcribe speech, understand meaning, save audio, or contact a backend.
