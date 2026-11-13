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

name="new vacía GIT_ASKPASS en cada git aunque el llamador exporte uno"
cat > "$TMP/shim/git" <<EOF2
#!/usr/bin/env bash
printf '[%s]\n' "\${GIT_ASKPASS-unset}" >> "$log"
exec "$real_git" "\$@"
EOF2
: > "$log"
out="$(cd "$TMP/repo" && GIT_ASKPASS=/some/askpass PATH="$TMP/shim:$PATH" "$WT" new feature/no-askpass --json 2>&1)" || fail "$name: th-wt new falló: [$out]"
[ -s "$log" ] || fail "$name: el shim no registró ningún git"
if grep -qvx '\[\]' "$log"; then
  fail "$name: GIT_ASKPASS no vacío: [$(sort -u "$log" | tr '\n' ' ')]"
fi
pass "$name"

# Desde aquí origin pasa de verdad por ssh: sin el insteadOf global ni el shim de git.
rm -rf "$TMP/shim"
git config --global --unset-all "url.$TMP/origin.git.insteadOf"
git -C "$TMP/repo" remote set-url origin git@ssh.example.invalid:acme/demo.git

# Falso ssh que anota un argumento por línea y falla como un ssh sin acceso.
mkfake() {
  cat > "$1" <<EOF2
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$1.log"
exit 255
EOF2
  chmod +x "$1"
}
# th-wt new en $TMP/repo debe salir con 4 (origin inalcanzable).
expect_exit4() {
  rc=0
  out="$(cd "$TMP/repo" && PATH="$TMP/bin:$PATH" "$WT" new "$2" --json 2>&1)" || rc=$?
  [ "$rc" -eq 4 ] || fail "$1: salida $rc en vez de 4: [$out]"
}
mkdir "$TMP/bin"
unset GIT_SSH_COMMAND GIT_SSH GIT_ASKPASS

name="new llama al core.sshCommand del usuario con BatchMode=yes"
mkfake "$TMP/fakessh"
git -C "$TMP/repo" config core.sshCommand "$TMP/fakessh --marca"
expect_exit4 "$name" feature/ssh-config
grep -qx -e '--marca' "$TMP/fakessh.log" || fail "$name: falta el marcador: [$(tr '\n' ' ' < "$TMP/fakessh.log")]"
grep -qx 'BatchMode=yes' "$TMP/fakessh.log" || fail "$name: falta BatchMode=yes: [$(tr '\n' ' ' < "$TMP/fakessh.log")]"
pass "$name"

name="sin core.sshCommand, new llama a ssh con BatchMode=yes"
git -C "$TMP/repo" config --unset core.sshCommand
mkfake "$TMP/bin/ssh"
expect_exit4 "$name" feature/ssh-plain
grep -qx 'BatchMode=yes' "$TMP/bin/ssh.log" || fail "$name: falta BatchMode=yes: [$(tr '\n' ' ' < "$TMP/bin/ssh.log" 2>&1)]"
pass "$name"

name="un GIT_SSH_COMMAND del llamador gana a core.sshCommand y recibe BatchMode=yes"
mkfake "$TMP/fakea"
mkfake "$TMP/fakeb"
git -C "$TMP/repo" config core.sshCommand "$TMP/fakea"
GIT_SSH_COMMAND="$TMP/fakeb" expect_exit4 "$name" feature/ssh-env
grep -qx 'BatchMode=yes' "$TMP/fakeb.log" || fail "$name: falta BatchMode=yes en B: [$(tr '\n' ' ' < "$TMP/fakeb.log" 2>&1)]"
[ ! -e "$TMP/fakea.log" ] || fail "$name: se llamó a core.sshCommand"
pass "$name"

name="con solo GIT_SSH del llamador, new lo respeta sin BatchMode y ssh no usa askpass"
git -C "$TMP/repo" config --unset core.sshCommand || true
unset GIT_SSH_COMMAND
cat > "$TMP/gitssh" <<EOF2
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$TMP/gitssh.log"
printf 'SSH_ASKPASS_REQUIRE=%s\n' "\${SSH_ASKPASS_REQUIRE-unset}" >> "$TMP/gitssh.log"
exit 255
EOF2
chmod +x "$TMP/gitssh"
GIT_SSH="$TMP/gitssh" expect_exit4 "$name" feature/ssh-gitssh
[ -s "$TMP/gitssh.log" ] || fail "$name: no se llamó al programa de GIT_SSH"
if grep -qx 'BatchMode=yes' "$TMP/gitssh.log"; then
  fail "$name: GIT_SSH recibió BatchMode=yes: [$(tr '\n' ' ' < "$TMP/gitssh.log")]"
fi
grep -qx 'SSH_ASKPASS_REQUIRE=never' "$TMP/gitssh.log" || fail "$name: falta SSH_ASKPASS_REQUIRE=never: [$(tr '\n' ' ' < "$TMP/gitssh.log")]"
pass "$name"
