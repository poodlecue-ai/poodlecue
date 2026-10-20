# Phase 7 — Local cue policy

Phase 7 changes cue selection from a flat topic lookup into a deterministic conversation policy.

## Context

The policy considers:

- the latest speech labeled **Them**;
- the most recent speech labeled **Me**;
- the selected person's approved memory;
- the last five cues delivered.

Only the last twelve role-labeled turns are held in memory for the active session. They are not persisted.

## Decisions

The engine classifies a useful response as **Empathy**, **Answer**, **Celebrate**, **Recall**, or **Follow-up**. It deliberately emits no cue for short acknowledgements, low-signal statements, a topic the user just asked about, and recently repeated wording.

Examples:

- “My kids didn't sleep well last night.” → empathy → “Ask if everyone is doing okay today.”
- A direct question → answer → “Answer simply, then ask them back.”
- A topic shared with saved memory → recall → “Ask what's changed since last time.”

## Feedback

Each visible cue can be marked **Useful**, **Not useful**, **Too late**, or **Repeated**. Only aggregate counts are stored in `UserDefaults`; conversation text is not attached to the feedback or persisted.

The implementation remains entirely local and deterministic. This produces an auditable baseline for comparison with a future AI policy.
