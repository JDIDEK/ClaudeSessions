---
name: explications-deploiement-josselin
description: "Expliquer le déploiement par analogie avec le WAMP existant, pas en jargon d'écosystème"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 126b39f6-289c-4e37-89c8-2704f80cebf8
  modified: 2026-08-04T11:51:01.437Z
---

Ancrer les explications de déploiement dans ce qui tourne déjà sur le serveur
(Apache et MariaDB de WAMP, applis PHP dans `www/`) plutôt que dans le
vocabulaire de l'écosystème utilisé.

**Why:** en livrant l'appli Go, dire « binaire unique, service Windows,
port 8080 » n'a pas suffi — la question posée a été « le .exe sert à quoi
alors ? ». Le modèle mental de référence est « une URL servie par l'Apache du
WAMP, comme les autres applis », et un `.exe` n'y ressemble pas. L'explication
qui a fonctionné : `httpd.exe` et `mysqld.exe` sont eux aussi des `.exe` qui
tournent sur le serveur, personne ne les ouvre.

**How to apply:** pour toute techno nouvelle sur ce parc, montrer d'abord où
elle se branche dans l'existant (schéma serveur ↔ postes, URL finale, place
dans WAMP), avant de parler des propriétés de la stack. Vérifier tôt que l'URL
finale correspond à ce qui est attendu — un `:8080` peut à lui seul faire
croire que le livrable n'est pas une appli web.
Voir [[appli-gardes-astreintes]].
