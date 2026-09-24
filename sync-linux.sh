#!/usr/bin/env bash
set -u

MODE="${1:-push}"
if [[ "$MODE" != "push" && "$MODE" != "full" ]]; then
  echo "Usage: $0 [push|full]" >&2
  exit 2
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS="$REPO/projects"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ClaudeSessions"
LOG="$STATE_DIR/sync.log"
LOCK="$STATE_DIR/sync.lock"

mkdir -p "$PROJECTS" "$STATE_DIR"

log() {
  printf '%s [%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(hostname)" "$MODE" "$1" >> "$LOG"
}

exec 9>"$LOCK"
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || exit 0
fi

cd "$REPO" || exit 1

if [[ ! -d .git ]]; then
  log "ERREUR : pas de depot Git."
  exit 1
fi

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  branch="main"
  git branch -M main || exit 1
fi

git add -- projects || exit 1

if ! git diff --cached --quiet -- projects; then
  stamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  git commit -m "Claude sync - $(hostname) - $stamp" -- projects || exit 1
  log "Nouvelles donnees Claude committees."
fi

if [[ "$MODE" == "full" ]]; then
  if git fetch origin "$branch"; then
    if git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
      if ! git rebase "origin/$branch"; then
        git rebase --abort >/dev/null 2>&1 || true
        log "ERREUR : conflit Git, rebase annule."
        echo "Conflit Git. Rien n'a ete ecrase. Ferme Claude et resous le conflit manuellement." >&2
        exit 1
      fi
      log "Nouveautes distantes integrees."
    fi
  fi
fi

if ! git push -u origin "$branch"; then
  log "ERREUR : push refuse/echec."
  if [[ "$MODE" == "push" ]]; then
    echo "Push refuse. Lance '$0 full' quand Claude est ferme." >&2
  fi
  exit 1
fi

log "Synchronisation terminee."
