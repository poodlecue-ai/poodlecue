# PoodleCue

PoodleCue is an iOS experiment for delivering a short, private conversational cue through earbuds with a target trigger-to-audio latency below 200 ms.

## Current prototype

This repository contains the cue-latency prototype, local speech-activity detection, on-device partial transcription, a deterministic cue engine, and reviewed on-device conversation memories. It deliberately has no AI cue model or backend.

The prototype:

- configures a simultaneous Bluetooth input/output audio session;
- keeps the audio engine warm;
- plays a locally generated cached cue tone;
- estimates trigger-to-output onset from render timing and the audio engine's reported presentation latency;
- reports the median and 95th-percentile latency.
- analyzes short microphone buffers locally for speech activity;
- reports speech-onset detection timing without saving or transmitting audio.
- displays partial on-device transcription and time-to-first-text metrics;
- discards transcript text when the session ends.
- selects short conversational cues from curated local rules;
- can speak a cue through the active audio route while suppressing transcription feedback.

## Run

1. Open `PoodleCue.xcodeproj` in Xcode.
2. Select a physical iPhone as the destination.
3. Choose a development team for the `PoodleCue` target.
4. Connect AirPods.
5. Build and run.
6. Tap **Start session**, confirm the active audio route, then run at least 100 cue trials.

The simulator is useful for compilation checks, but latency results are meaningful only on physical hardware.

## Measurement limitation

The measurement combines estimated render-start delay with AVAudioEngine's reported downstream presentation latency. It does not directly measure the final acoustic arrival at the listener's ear. Hardware end-to-end validation requires an external loopback or acoustic measurement setup.

See [`docs/latency-test-plan.md`](docs/latency-test-plan.md) for the test procedure.

See [`docs/phase-2-spec.md`](docs/phase-2-spec.md) for the live microphone test.

See [`docs/phase-3-spec.md`](docs/phase-3-spec.md) for the on-device transcription test.

See [`docs/phase-4-spec.md`](docs/phase-4-spec.md) for the local cue-engine test.

See [`docs/phase-5-spec.md`](docs/phase-5-spec.md) for private conversation memory and speaker control.

See [`docs/phase-6-spec.md`](docs/phase-6-spec.md) for the everyday conversation screen and memory-aware cues.

See [`docs/phase-7-spec.md`](docs/phase-7-spec.md) for the contextual local cue policy and usefulness feedback.

