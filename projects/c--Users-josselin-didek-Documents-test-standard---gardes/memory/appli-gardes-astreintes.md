---
name: appli-gardes-astreintes
description: "Projet en cours — appli web Go/MariaDB remplaçant le circuit Excel des gardes hospitalières, état et étapes restantes"
metadata: 
  node_type: memory
  type: project
  originSessionId: 126b39f6-289c-4e37-89c8-2704f80cebf8
  modified: 2026-08-04T11:50:48.941Z
---

Application `gardes/` (Go + MariaDB + auth Active Directory), écrite en août 2026
pour remplacer le circuit Excel `tabgarde.xls` → macro → `RECHERCHEV` du tableau
des gardes et astreintes. Établissement du GHT53 ; hébergement prévu sur un
serveur Windows portant déjà un WAMP.

Décisions arrêtées avec l'utilisateur : Go plutôt que PHP, MariaDB de WAMP,
authentification AD/LDAP, une seule sortie demandée (vue web temps réel) — pas
de PDF, pas d'export Excel, pas d'API.

Étapes restantes au 04/08/2026, aucune vérifiable depuis le poste de dev
(ni MariaDB ni AD accessibles) :

- créer la base et le compte MariaDB sur le WAMP du serveur
- renseigner `gardes.env`, puis `gardes.exe -verifier`
- valider le bind LDAP réel (le durcissement LDAP Microsoft est le principal
  risque de rupture à moyen terme)
- faire relire `outils/reprise_personnes.csv` par la médecine du travail avant
  import : 548 agents extraits, 107 sans aucun numéro, quasi-doublons du type
  `DR ABDELEDHI`/`DR ABDELHEDI` à arbitrer humainement
- prévoir un reverse proxy TLS : l'appli sert du HTTP en clair, un mot de passe
  AD transite à chaque connexion

**Why:** ces points ne sont pas dans le dépôt en tant qu'état d'avancement, et
la reprise des données dépend d'un arbitrage humain externe.

**How to apply:** reprendre depuis le README de `gardes/` ; ne pas relancer
l'import du CSV sans confirmation que la médecine du travail l'a relu.
Voir [[explications-deploiement-josselin]].
