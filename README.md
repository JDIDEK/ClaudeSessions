# ClaudeSessions

Synchronisation privée des sessions Claude Code entre plusieurs machines.

## Données synchronisées

Uniquement `~/.claude/projects/`, qui contient notamment les transcriptions de sessions et l'auto-memory par projet.

Ne rendez jamais ce dépôt public : les transcriptions Claude peuvent contenir du code, des sorties de commandes, du contenu de fichiers et des secrets lus pendant une session.

## Windows

Après clonage du dépôt :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup-windows.ps1
```

Synchronisation manuelle complète :

```powershell
.\sync-windows.ps1 -Mode full
```

Le setup crée :
- une jonction `%USERPROFILE%\.claude\projects` -> `<repo>\projects`
- un push toutes les 5 minutes
- un full sync à l'ouverture de session

## Linux

Après clonage :

```bash
chmod +x setup-linux.sh sync-linux.sh
./setup-linux.sh
```

Synchronisation manuelle complète :

```bash
./sync-linux.sh full
```

Le setup crée :
- un lien `~/.claude/projects` -> `<repo>/projects`
- un push toutes les 5 minutes via cron
- un full sync au démarrage

## Règle importante

Éviter de continuer exactement la même session Claude simultanément sur deux machines.

Le push périodique ne fait volontairement PAS de pull pendant que Claude est en cours d'utilisation. Le full sync est fait au démarrage/logon ou manuellement, afin de ne pas réécrire une transcription active.
