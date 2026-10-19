# Latency test plan

## Test matrix

Record the exact:

- iPhone model;
- iOS version;
- AirPods model and firmware;
- battery level;
- active audio route;
- foreground, background, or locked-screen state.

## Procedure

1. Connect the AirPods before launching PoodleCue.
2. Start the session and verify that the displayed route names the expected Bluetooth device.
3. Allow the session to remain warm for ten seconds.
4. Trigger 100 cues at irregular intervals.
5. Capture the displayed median and p95 measurements.
6. Repeat after locking the phone and after returning from an interruption.

## Pass condition

The software render-start p95 must be below 200 ms with zero missed triggers.

This is an engineering gate, not proof of acoustic end-to-end latency. Before making a user-facing latency claim, repeat the test with an external microphone or electrical loopback that measures the sound arriving from the earbud.

