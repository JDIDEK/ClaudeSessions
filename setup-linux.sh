#!/usr/bin/env bash
set -euo pipefail

NO_SCHEDULE="${1:-}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PROJECTS="$REPO/projects"
CLAUDE_ROOT="$HOME/.claude"
CLAUDE_PROJECTS="$CLAUDE_ROOT/projects"
SYNC_SCRIPT="$REPO/sync-linux.sh"

command -v git >/dev/null 2>&1 || { echo "Git n'est pas installe."; exit 1; }
[[ -d "$REPO/.git" ]] || { echo "Ce script doit etre a la racine du depot ClaudeSessions."; exit 1; }

mkdir -p "$CLAUDE_ROOT"

cd "$REPO"
branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  branch="main"
  git branch -M main
fi

if git fetch origin "$branch" >/dev/null 2>&1 && git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
  git pull --rebase origin "$branch"
fi

repo_has_data=false
if [[ -d "$REPO_PROJECTS" ]] && find "$REPO_PROJECTS" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
  repo_has_data=true
fi

if [[ -L "$CLAUDE_PROJECTS" ]]; then
  current_target="$(readlink -f "$CLAUDE_PROJECTS" || true)"
  wanted_target="$(readlink -f "$REPO_PROJECTS" 2>/dev/null || printf '%s' "$REPO_PROJECTS")"
  if [[ "$current_target" == "$wanted_target" ]]; then
    echo "Le lien Claude -> repo est deja en place."
  else
    echo "$CLAUDE_PROJECTS est deja un lien vers un autre emplacement." >&2
    exit 1
  fi
elif [[ -e "$CLAUDE_PROJECTS" ]]; then
  if [[ "$repo_has_data" == false ]]; then
    echo "Premier PC Linux detecte : import des sessions Claude."
    mv "$CLAUDE_PROJECTS" "$REPO_PROJECTS"
  else
    stamp="$(date '+%Y%m%d-%H%M%S')"
    backup="$CLAUDE_ROOT/projects.backup-$stamp-$(hostname)"
    echo "Sauvegarde des sessions locales dans : $backup"
    mv "$CLAUDE_PROJECTS" "$backup"
  fi
fi

mkdir -p "$REPO_PROJECTS"

if [[ ! -e "$CLAUDE_PROJECTS" && ! -L "$CLAUDE_PROJECTS" ]]; then
  ln -s "$REPO_PROJECTS" "$CLAUDE_PROJECTS"
  echo "Lien cree : $CLAUDE_PROJECTS -> $REPO_PROJECTS"
fi

chmod +x "$SYNC_SCRIPT" "$REPO/setup-linux.sh"

git add -- .gitignore README.md setup-windows.ps1 sync-windows.ps1 setup-linux.sh sync-linux.sh projects
if ! git diff --cached --quiet; then
  git commit -m "Initialize ClaudeSessions - $(hostname) - $(date '+%Y-%m-%d_%H-%M-%S')"
fi

git push -u origin "$branch" || echo "ATTENTION: push impossible. Authentifie GitHub puis lance '$SYNC_SCRIPT full'."

if [[ "$NO_SCHEDULE" != "--no-schedule" ]]; then
  if command -v crontab >/dev/null 2>&1; then
    tmp="$(mktemp)"
    crontab -l 2>/dev/null | grep -v 'ClaudeSessions managed sync' > "$tmp" || true
    {
      cat "$tmp"
      echo "*/5 * * * * /bin/bash \"$SYNC_SCRIPT\" push >/dev/null 2>&1 # ClaudeSessions managed sync"
      echo "@reboot sleep 30 && /bin/bash \"$SYNC_SCRIPT\" full >/dev/null 2>&1 # ClaudeSessions managed sync"
    } | crontab -
    rm -f "$tmp"
    echo "Cron installe : push toutes les 5 min + full sync au demarrage."
  else
    echo "crontab absent : pas de planification automatique."
  fi
fi

echo
echo "=== TERMINE ==="
echo "Avant de changer de PC, force si besoin :"
echo "  \"$SYNC_SCRIPT\" full"
echo "Log : ${XDG_STATE_HOME:-$HOME/.local/state}/ClaudeSessions/sync.log"
