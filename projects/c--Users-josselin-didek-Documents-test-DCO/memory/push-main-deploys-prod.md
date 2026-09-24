---
name: push-main-deploys-prod
description: Pushing to main on JDIDEK/DCO triggers a Cloudflare Workers Builds production deploy of odebas.fr
metadata:
  node_type: memory
  type: project
  originSessionId: a3be2c16-6acf-447c-91e1-cfc20612615a
  modified: 2026-09-24T14:42:26.033Z
---

A push to `main` on github.com/JDIDEK/DCO immediately triggers a Cloudflare Workers Builds production deploy of the `dco` Worker (odebas.fr). Confirmed 2026-09-24 via the "Workers Builds: dco" GitHub check run. `vercel.json` only disables Vercel, not Cloudflare.

**Why:** I once told the user a push would not deploy; it did.
**How to apply:** Before pushing to main, state plainly that it ships to production. Check deploy status with `gh api repos/JDIDEK/DCO/commits/<sha>/check-runs`.
