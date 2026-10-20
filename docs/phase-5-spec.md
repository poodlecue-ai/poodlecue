# Phase 5 — Private conversation memory

Phase 5 adds an intentionally small, local-first memory loop:

1. The user identifies whether the current speaker is **Them** or **Me**.
2. PoodleCue only offers conversation cues while **Them** is selected.
3. After a conversation, the user can create a short draft from the live transcript.
4. The user must review the person name and note before tapping **Save**.
5. A future session can load that person and display the previously approved context.

Raw audio and full transcripts are not persisted. Approved memories are stored with iOS complete file protection in the app sandbox. There is no backend or account sync in this phase.

Automatic speaker identification is deliberately out of scope. A single Bluetooth microphone does not provide reliable diarization, so the UI states clearly that speaker choice is manual.
