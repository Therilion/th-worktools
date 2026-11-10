# shellcheck shell=bash
# Shared by install.sh and verify.sh; they define err, die and bad_usage before calling pick_agents.

# shellcheck disable=SC2034 # used by the scripts that load this file
KIT_PATH="$HOME/.local/share/th-worktools"
# shellcheck disable=SC2034
BIN_DIR="$HOME/.local/bin"
SUPPORTED="claude agy"

# The agent name is also its binary; this maps it to its skills directory (empty if unsupported).
agent_dir() {
  case "$1" in
    claude) echo "$HOME/.claude/skills" ;;
    agy) echo "$HOME/.gemini/config/skills" ;;
    *) echo "" ;;
  esac
}

# Physical path of $1 after following the symlink chain; fails if it dangles or loops.
resolve() {
  local p="$1" dir n=0
  while [ -L "$p" ]; do
    n=$((n + 1))
    [ "$n" -le 40 ] || return 1
    dir="$(cd -P "${p%/*}" && pwd)" || return 1
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$dir/$p" ;; esac
  done
  if [ -d "$p" ]; then
    (cd -P "$p" && pwd)
  elif [ -e "$p" ]; then
    dir="$(cd -P "${p%/*}" && pwd)" || return 1
    echo "$dir/${p##*/}"
  else
    return 1
  fi
}

# pick_agents <--agents value or empty>: sets AGENTS (space-separated) to the listed agents, or to the supported ones in PATH.
pick_agents() {
  local rest a
  AGENTS=""
  if [ -n "$1" ]; then
    rest="$1,"
    while [ -n "$rest" ]; do
      a="${rest%%,*}"
      rest="${rest#*,}"
      [ -n "$a" ] || continue
      [ -n "$(agent_dir "$a")" ] || die 2 "unsupported agent: $a (supported: claude, agy)"
      case " $AGENTS " in *" $a "*) ;; *) AGENTS="$AGENTS $a" ;; esac
    done
    [ -n "$AGENTS" ] || bad_usage "--agents needs a comma-separated list of agents"
    for a in $AGENTS; do
      command -v "$a" >/dev/null || die 3 "agent not found in PATH: $a"
    done
  else
    for a in $SUPPORTED; do
      if command -v "$a" >/dev/null; then AGENTS="$AGENTS $a"; fi
    done
  fi
}
