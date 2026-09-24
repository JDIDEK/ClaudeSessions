---
name: no-credentials-in-ci-files
description: "User refuses hardcoded credentials/env values in CI workflow files, even \"public\" ones like NEXT_PUBLIC_SANITY_PROJECT_ID"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 68d8dd3c-f254-4d6f-bc92-57a5c5c2a1f3
---

Do not hardcode credential-like values (API keys, project IDs, env values) in CI workflow files, even when technically public (e.g. NEXT_PUBLIC_* values inlined in the client bundle). Use GitHub secrets/vars instead.

**Why:** On 2026-07-02 I hardcoded `NEXT_PUBLIC_SANITY_PROJECT_ID` in `.github/workflows/ci.yml` to fix a build failure; the user objected ("tu ne mets pas un credentials dans un dossier CI") and I reverted to `${{ secrets.… }}`.

**How to apply:** When a CI build fails from a missing env value, keep the `secrets.`/`vars.` reference in the workflow and tell the user to define it in GitHub repo settings, rather than inlining the value.
