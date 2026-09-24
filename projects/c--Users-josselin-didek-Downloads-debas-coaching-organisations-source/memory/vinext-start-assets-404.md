---
name: vinext-start-assets-404
description: "Le serveur de prod local (pnpm start / vinext start, port 3000) renvoie 404 sur tout /assets/* — tester dans le navigateur avec pnpm run dev"
metadata: 
  node_type: memory
  type: project
  originSessionId: 69e96ffe-8de3-42cb-a1ef-8029b1c44580
  modified: 2026-07-28T15:08:41.962Z
---

`pnpm start` (`vinext start`, port 3000) sert `/public` (favicon, images) mais renvoie **404 sur tous les `/assets/*`** — JS et CSS compris — alors que les fichiers existent bien dans `dist/client/assets/`. Résultat : la page arrive non stylée et sans hydratation, donc tous les liens font une navigation native.

**Pourquoi :** la vraie cible de déploiement est un Worker Cloudflare avec binding assets ; `vinext start` n'émule pas ce binding. Ce n'est pas une régression du code applicatif.

**Comment l'appliquer :** pour toute vérification comportementale dans un navigateur (transitions, hydratation, routage client), utiliser `pnpm run dev` — le port varie (5173, 5174, 5175… selon les instances déjà lancées), le lire dans la sortie du serveur. Garder `pnpm run build` uniquement pour valider la compilation et l'artefact.
