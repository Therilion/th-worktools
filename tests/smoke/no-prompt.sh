#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../lib.sh"

# Shim de git: anota "<GIT_TERMINAL_PROMPT> <subcomando>" en cada invocación y ejecuta el git real.
real_git="$(command -v git)"
log="$TMP/prompt.log"
mkdir "$TMP/shim"
cat > "$TMP/shim/git" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "\${GIT_TERMINAL_PROMPT-unset}" "\${1-}" >> "$log"
exec "$real_git" "\$@"
EOF
chmod +x "$TMP/shim/git"

name="new fija GIT_TERMINAL_PROMPT=0 en cada git, también en ls-remote y fetch, aunque el llamador lo exporte a 1"
export GIT_TERMINAL_PROMPT=1
: > "$log"
out="$(cd "$TMP/repo" && PATH="$TMP/shim:$PATH" "$WT" new feature/no-prompt --json 2>&1)" || fail "$name: th-wt new falló: [$out]"
unset GIT_TERMINAL_PROMPT
grep -q '^0 ls-remote$' "$log" || fail "$name: ningún ls-remote con 0: [$(sort -u "$log" | tr '\n' ' ')]"
grep -q '^0 fetch$' "$log" || fail "$name: ningún fetch con 0: [$(sort -u "$log" | tr '\n' ' ')]"
if grep -qv '^0 ' "$log"; then
  fail "$name: valores distintos de 0: [$(sort -u "$log" | tr '\n' ' ')]"
fi
pass "$name"
