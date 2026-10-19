# PoodleCue

PoodleCue is an iOS experiment for delivering a short, private conversational cue through earbuds with a target trigger-to-audio latency below 200 ms.

## Phase 1

This repository currently contains the cue-latency prototype only. It deliberately has no transcription, AI model, backend, or conversation storage.

The prototype:

- configures a simultaneous Bluetooth input/output audio session;
- keeps the audio engine warm;
- plays a locally generated cached cue tone;
- records estimated software render-start latency;
- reports the median and 95th-percentile latency.

## Run

1. Open `PoodleCue.xcodeproj` in Xcode.
2. Select a physical iPhone as the destination.
3. Choose a development team for the `PoodleCue` target.
4. Connect AirPods.
5. Build and run.
6. Tap **Start session**, confirm the active audio route, then run at least 100 cue trials.

The simulator is useful for compilation checks, but latency results are meaningful only on physical hardware.

## Measurement limitation

The current measurement estimates the interval from the UI trigger to the audio engine beginning to render the cached cue. It does not measure the final acoustic arrival at the AirPods speaker. Hardware end-to-end validation requires an external loopback or acoustic measurement setup.

See [`docs/latency-test-plan.md`](docs/latency-test-plan.md) for the test procedure.

