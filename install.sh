#!/usr/bin/env bash
set -euo pipefail

src="${BASH_SOURCE[0]}"
case "$src" in */*) ;; *) src="./$src" ;; esac
while [ -L "$src" ]; do
  dir="$(cd -P "${src%/*}" && pwd)"
  src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
SELF_DIR="$(cd -P "${src%/*}" && pwd)"

KIT_PATH="$HOME/.local/share/th-worktools"
BIN_DIR="$HOME/.local/bin"
SUPPORTED="claude agy"

usage() {
  cat <<'USAGE'
Usage: install.sh [--link-here] [--agents <list>] [--yes]
       install.sh -h | --help

Install th-worktools through the fixed kit path ~/.local/share/th-worktools: link each skills/th-*/ into the chosen agents' skills directories and each executable in skills/th-*/scripts/ into ~/.local/bin. Dry-run unless --yes.

--link-here      Point the kit path at this clone (creates the symlink if it is missing).
--agents <list>  Comma-separated agents to link (supported: claude, agy). Default: the supported agents found in PATH.
--yes            Apply the plan.

Paths that already exist and are not part of the kit are never touched (exit 4).
USAGE
}

err() { echo "install.sh: $*" >&2; }
die() { local code="$1"; shift; err "$*"; exit "$code"; }
bad_usage() { err "$1"; usage >&2; exit 2; }

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

is_kit_path() {
  case "$1" in
    "$KIT_DIR"|"$KIT_DIR"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Whether a missing path can be created: its nearest existing ancestor (or symlink) must be a directory.
parent_ok() {
  local p="${1%/*}"
  while [ -n "$p" ] && [ ! -e "$p" ] && [ ! -L "$p" ]; do p="${p%/*}"; done
  [ -d "${p:-/}" ]
}

# True for a symlink value that goes through the fixed kit path, even if it does not resolve yet.
via_kit_path() {
  case "$1" in
    "$KIT_PATH"|"$KIT_PATH"/*) return 0 ;;
    *) return 1 ;;
  esac
}

LINK_HERE=0
YES=0
AGENTS_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --link-here) LINK_HERE=1 ;;
    --yes) YES=1 ;;
    --agents)
      [ -n "${2:-}" ] || bad_usage "--agents needs a comma-separated list of agents"
      AGENTS_ARG="$2"
      shift ;;
    *) bad_usage "unknown option: $1" ;;
  esac
  shift
done

# Chosen agents, space-separated. Validated before touching anything.
AGENTS=""
if [ -n "$AGENTS_ARG" ]; then
  rest="$AGENTS_ARG,"
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
  if [ -z "$AGENTS" ]; then
    err "warning: no supported agent found in PATH (claude, agy); linking only the kit path and entrypoints"
  fi
fi

KIT_STATE=ok
if [ "$LINK_HERE" = 1 ]; then
  KIT_DIR="$SELF_DIR"
  if [ -e "$KIT_PATH" ] || [ -L "$KIT_PATH" ]; then
    resolved="$(cd -P "$KIT_PATH" 2>/dev/null && pwd)" || resolved=""
    [ "$resolved" = "$KIT_DIR" ] || die 4 "kit path $KIT_PATH is not this clone; move it away and run again"
  else
    parent_ok "$KIT_PATH" || die 4 "cannot create kit path $KIT_PATH: parent is not a directory"
    KIT_STATE=create
  fi
else
  if [ ! -d "$KIT_PATH" ]; then
    if [ -L "$KIT_PATH" ]; then die 4 "kit path $KIT_PATH is a broken symlink; move it away and run again"; fi
    die 4 "kit path not found: $KIT_PATH; run install.sh --link-here from a clone"
  fi
  KIT_DIR="$(cd -P "$KIT_PATH" && pwd)"
fi

SKIPS=0

# plan_link <dest> <target>: classify dest, print the plan line and, with --yes, apply it.
plan_link() {
  local dest="$1" target="$2" verb why="not part of the kit" r l
  if [ -L "$dest" ]; then
    l="$(readlink "$dest")"
    if [ "$l" = "$target" ]; then
      verb=ok
    elif via_kit_path "$l" || { r="$(resolve "$dest")" && is_kit_path "$r"; }; then
      verb=fix
    else
      verb=skip
    fi
  elif [ -e "$dest" ]; then
    verb=skip
  elif parent_ok "$dest"; then
    verb=create
  else
    verb=skip
    why="parent is not a directory"
  fi
  case "$verb" in
    ok) printf '%-6s %s\n' ok "$dest" >&2 ;;
    skip) printf '%-6s %s\n' skip "$dest ($why)" >&2; SKIPS=$((SKIPS + 1)) ;;
    *) printf '%-6s %s\n' "$verb" "$dest -> $target" >&2 ;;
  esac
  [ "$YES" = 1 ] || return 0
  case "$verb" in
    create|fix)
      mkdir -p "${dest%/*}"
      if [ "$verb" = fix ]; then rm "$dest"; fi
      ln -s "$target" "$dest" ;;
  esac
}

# The kit path was validated above: if it exists it already is this clone, even as a real directory.
if [ "$KIT_STATE" = create ]; then plan_link "$KIT_PATH" "$KIT_DIR"; else printf '%-6s %s\n' ok "$KIT_PATH" >&2; fi

for skill in "$KIT_DIR"/skills/th-*/; do
  [ -d "$skill" ] || continue
  skill="${skill%/}"
  skill="${skill##*/}"
  for a in $AGENTS; do
    plan_link "$(agent_dir "$a")/$skill" "$KIT_PATH/skills/$skill"
  done
  for f in "$KIT_DIR/skills/$skill/scripts/"*; do
    { [ -f "$f" ] && [ -x "$f" ]; } || continue
    plan_link "$BIN_DIR/${f##*/}" "$KIT_PATH/skills/$skill/scripts/${f##*/}"
  done
done

if [ "$YES" = 0 ]; then
  err "dry run, nothing changed; run with --yes to apply"
elif [ "$SKIPS" = 0 ]; then
  err "done"
fi
if [ "$SKIPS" -gt 0 ]; then
  die 4 "left $SKIPS path(s) untouched: not part of the kit"
fi
