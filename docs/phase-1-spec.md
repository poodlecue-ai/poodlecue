# Phase 1 specification

## Objective

Prove that PoodleCue can begin rendering a precomputed cue immediately after an intentional user trigger while maintaining a live Bluetooth audio session.

## Success criteria

- At least 100 consecutive cue trials on a physical iPhone and AirPods combination.
- Estimated trigger-to-render-start latency below 200 ms at the 95th percentile.
- No missed triggers during the test run.
- The session remains usable when the screen locks and when the app is backgrounded.
- The app clearly indicates when its audio session is active.

## Included

- Native SwiftUI application.
- Bluetooth-capable play-and-record audio session.
- Prewarmed audio engine.
- Cached local cue tone.
- Per-trial, median, and 95th-percentile measurements.
- Active audio-route display.

## Excluded

- Speech recognition.
- AI-generated cues.
- Conversation recording or storage.
- Relationship memory.
- Cloud services.
- Android support.

## Privacy behavior

Phase 1 requests microphone permission because the final product needs a duplex audio session, but it does not record, save, transmit, or analyze microphone samples.

