---
name: etablissements-data-driven
description: Establishments live in config/establishments.json (file store, hot-reloaded), editable via /administration; secrets AES-GCM encrypted with APP_ENCRYPTION_KEY
metadata:
  type: project
---

Establishment config moved from hardcoded (env.ts maps, shared.ts classify, login GROUPS map) to a **single JSON file** editable live from the app via `lib/establishments/` (types, crypto, store, defaults, repo, validation).

- **Source of truth**: `config/establishments.json` (path override `ESTABLISHMENTS_PATH`; test → tmpdir). `store.ts` does atomic write + mtime read. `repo.ts` keeps an in-memory snapshot, hot-reloaded when the file mtime changes (2s check) — edits apply with **no restart** (unlike `.env`). First boot **seeds** the file from the old `.env` vars, which then become seed-only (schema relaxed to `.default('')`, can be removed from `.env` after first boot). Redis is NOT used for establishments anymore (still used for sync progress/caches).
- **Runtime**: sync resolvers read the snapshot; `ensureEstablishmentsLoaded()` awaited at route entrypoints; `NetworkManager.create()` is the async factory.
- **Admin**: global users (GHT53) manage establishments at `/administration` → `/api/admin/etablissements[/[code]]` (POST/PUT/DELETE, CSRF). Public list `/api/etablissements` feeds the selector. Post distribution is data-driven `classificationRules` (prefix/contains/regex + priority + catchAll) with live preview in the form.
- **Secrets**: server/PC passwords AES-256-GCM encrypted (per-field, `v1:iv:tag:cipher`) via `APP_ENCRYPTION_KEY` (base64 of 32 bytes) in `.env`. File holds only ciphertext.

**Why:** requested so "monsieur tout le monde" can add an establishment (server pwd, svc-procdeg PC pwd, network path, AD group) live from the UI without editing code or restarting.

**How to apply:** ⚠️ Losing `APP_ENCRYPTION_KEY` makes ALL establishments in the file unreadable. `.env` and `config/establishments.json` are gitignored (both hold secrets). `.env` was NOT gitignored before (only `.env.local`) — fixed; it was never committed. Delete via admin = permanent removal from the file (no revert-to-default). Durability = ordinary file on disk; back it up.
