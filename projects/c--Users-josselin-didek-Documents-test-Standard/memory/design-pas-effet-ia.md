---
name: design-pas-effet-ia
description: "User rejects \"AI-looking\" UI patterns and text — no coloured side stripes on cards/alerts, no thick accent bands, plain wording"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 226ff42e-a83b-4e6c-bc41-a6568ceea09c
  modified: 2026-09-22T14:06:22.817Z
---

No coloured left stripe (border-left accent) on cards, alerts or messages, and no thick coloured top band on sections. Also rejects wording that "sounds like AI" (e.g. login error message).

**Why:** the user finds these patterns the most generic "AI-made" look ("y a rien qui fait plus IA dégueux que ça").

**How to apply:** for status/alerts use a light background tint plus a continuous 1px border of the same hue, state written as text (pill badge when needed); cards follow the sidebar card style (white, #e4e7e9 border, .85rem radius, soft shadow). Keep copy short, concrete, institutional French. See [[harmonisation-boutons]] if created later.
