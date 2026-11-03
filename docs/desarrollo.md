# Guía de desarrollo

Cómo ejecutar las verificaciones y cómo están armados los tests del repositorio. Para las reglas del proyecto y de los scripts, consulta [`AGENTS.md`](../AGENTS.md) y [`docs/plan-v0.1.md` (§5 y §6)](plan-v0.1.md).

---

## 1. Verificaciones antes de dar algo por terminado

Antes de dar cualquier cambio por terminado, deben pasar estos tres checks desde la raíz del repositorio (los mismos que exige [`AGENTS.md`](../AGENTS.md) y ejecuta CI):

```bash
# 1. Análisis estático de todos los scripts y entrypoints
shellcheck -x $(git ls-files '*.sh') skills/*/scripts/th-wt

# 2. Validación estática de los SKILL.md (nombre de carpeta y prefijo CLAUDE_SKILL_DIR en rutas scripts/)
tests/lint-skills.sh

# 3. Suite completa de tests de humo
tests/smoke.sh
```

Para ejecutar un único archivo de tests durante el desarrollo:

```bash
bash tests/smoke/list.sh
```

### Probar con Bash 3.2 en macOS

En macOS, Homebrew suele anteponer Bash 5 en `PATH`, por lo que `#!/usr/bin/env bash` resuelve a esa versión en local. Como el kit debe funcionar con el Bash 3.2 del sistema (`/bin/bash`), prueba los cambios forzando `/bin` delante en `PATH` o invocando `/bin/bash`:

```bash
/bin/bash tests/smoke/list.sh
PATH="/bin:$PATH" tests/smoke.sh
```

### Probar en Linux desde macOS (Podman)

Para validar compatibilidad con herramientas GNU (Ubuntu) en local sin esperar a CI (`docs/plan-v0.1.md` §6):

```bash
podman run --rm -v "$PWD":/w -w /w ubuntu:24.04 \
  bash -c 'apt-get update -qq && apt-get install -y -qq git jq >/dev/null && tests/smoke.sh'
```

### Qué ejecuta CI (`.github/workflows/ci.yml`)

El workflow se ejecuta en cada `push` a `main` y en cada `pull_request`:

| Job | Sistema operativo | Qué hace |
|---|---|---|
| `shellcheck` | `ubuntu-latest` | Ejecuta `shellcheck -x $(git ls-files '*.sh') skills/*/scripts/th-wt`. |
| `test` | Matriz `macos-latest` + `ubuntu-latest` (`fail-fast: false`) | En `macos-latest` añade `/bin` a `GITHUB_PATH` y comprueba que `BASH_VERSINFO[0]` sea `3` (Bash 3.2). Luego ejecuta `tests/lint-skills.sh` y `tests/smoke.sh` en ambos sistemas. |

---

## 2. Convenciones de los tests

### Estructura y patrón de cada archivo

- **Un archivo por tema en `tests/smoke/`:** cada archivo (`cli.sh`, `no-prompt.sh`, `new.sh`, `new-errors.sh`, `deps.sh`, `checkout.sh`, `checkout-errors.sh`, `list.sh`, `list-remote.sh`, `close.sh`, `close-remote.sh`, `pr.sh`, `pr-errors.sh`, `close-pr.sh`) es ejecutado por `tests/smoke.sh` en un subproceso propio con su propio entorno temporal.
- **Carga de la fixture:** todo archivo en `tests/smoke/` empieza con `set -euo pipefail` y carga [`tests/lib.sh`](../tests/lib.sh):
  ```bash
  # shellcheck source=../lib.sh source-path=SCRIPTDIR
  . "$(dirname "$0")/../lib.sh"
  ```
  `tests/lib.sh` define `$ROOT` (raíz del repositorio) y `$WT` (`$ROOT/skills/th-worktree/scripts/th-wt`).
- **Patrón `name=` / `fail` / `pass`:** los nombres de los casos se escriben en **español**. Cada caso asigna `name`, verifica las condiciones con `|| fail "$name: detalle"` y termina con `pass "$name"`:
  ```bash
  name="new --json devuelve solo path, branch y repo"
  out="$(cd "$TMP/repo" && "$WT" new feature/json --json)" || fail "$name: th-wt new falló"
  expected="{\"branch\":\"feature/json\",\"path\":\"$HOME/.worktrees/acme/demo/feature-json\",\"repo\":\"acme/demo\"}"
  [ "$(printf '%s' "$out" | jq -S -c .)" = "$expected" ] || fail "$name: salida=[$out]"
  pass "$name"
  ```
- **Valores esperados literales:** el resultado esperado se escribe directamente a partir del criterio del test (`acme/demo`, `feature-json`), nunca recalculándolo con la misma transformación que usa el código bajo prueba.
- **Captura de códigos de salida distintos de `0`:** debido a `set -e`, los fallos esperados se capturan con:
  ```bash
  rc=0
  err="$(cd "$TMP/repo" && "$WT" new feature/x 2>&1)" || rc=$?
  [ "$rc" = 4 ] || fail "$name: exit=$rc, esperado 4"
  ```

### La fixture compartida (`tests/lib.sh`)

Al cargarse, `tests/lib.sh` prepara un entorno aislado que se borra automáticamente al terminar el script (`trap 'rm -rf "$TMP"' EXIT`):

- **`$TMP` canonicalizado (`cd -P`):** en macOS `$TMPDIR` cuelga de `/var` (symlink a `/private/var`), y `git worktree list` devuelve rutas físicas. Resolver `$TMP` con `cd -P` evita falsos negativos al comparar rutas.
- **Entorno git y `HOME` aislados:**
  - `HOME="$TMP/home"`: tanto `~/.worktrees` como el `~/.gitconfig` global viven dentro de `$TMP`, sin leer ni modificar el directorio personal real.
  - `GIT_CONFIG_NOSYSTEM=1` y variables `GIT_AUTHOR_*` / `GIT_COMMITTER_*` fijas para que los commits de prueba no dependan de la configuración de la máquina.
- **`origin` bare local con URL de GitHub vía `insteadOf`:**
  - Crea un repositorio bare en `$TMP/origin.git` y un clon de trabajo en `$TMP/repo` con `REMOTE_URL="git@github.com:acme/demo.git"`.
  - Configura `git config --global "url.$TMP/origin.git.insteadOf" "$REMOTE_URL"`.
  - **Por qué:** `th-wt` deriva `<owner>/<repo>` (`acme/demo`) de `remote.origin.url` y rechaza rutas locales con código `4`. Con `insteadOf`, `git config --get remote.origin.url` sigue devolviendo `git@github.com:acme/demo.git`, pero `ls-remote`, `fetch` y `push` operan contra `$TMP/origin.git` sin usar la red.

### `advance_origin` y por qué no usar `git push`

`tests/lib.sh` incluye el helper:

```bash
advance_origin() { git -C "$TMP/origin.git" fetch -q "$1" HEAD:refs/heads/main; }
```

Cuando un test necesita simular que `main` avanzó en `origin` sin que el clon local `$TMP/repo` se haya enterado (por ejemplo, para contrastar `list` frente a `list --remote`), debe usar `advance_origin <worktree>` (o pushear desde un segundo clon `$TMP/other`) en lugar de hacer `git push` desde un worktree de `$TMP/repo`. En versiones recientes de git (visto en 2.56), hacer `push` a una URL que coincide con `origin` actualiza también `refs/remotes/origin/*` en el repositorio local. Haciendo que `origin.git` traiga el commit él mismo con `fetch`, las refs remotas de `$TMP/repo` quedan intactas.

### Simulación de fallos y dependencias externas

- **`origin` inaccesible:** renombrar temporalmente el repositorio bare antes de invocar `th-wt` y restaurarlo después (`list.sh`, `checkout.sh`, `checkout-errors.sh`, `list-remote.sh`, `close-remote.sh`):
  ```bash
  mv "$TMP/origin.git" "$TMP/origin.git.bak"
  rc=0
  err="$(cd "$TMP/repo" && "$WT" checkout feature/offline --remote 2>&1)" || rc=$?
  mv "$TMP/origin.git.bak" "$TMP/origin.git"
  ```
- **Shims de `git` en `PATH`:** cuando hace falta interceptar una llamada concreta a `git` sin afectar al resto, se crea un script `$shim/git` y se antepone al `PATH`:
  - Fallo selectivo de `git ls-remote --heads` tras superar `ls-remote --symref` ([`tests/smoke/new-errors.sh`](../tests/smoke/new-errors.sh)).
  - Registro de `GIT_TERMINAL_PROMPT` en cada subcomando de `git` ([`tests/smoke/no-prompt.sh`](../tests/smoke/no-prompt.sh)).
  - Salida masiva en `git worktree list --porcelain` para comprobar que no ocurre `SIGPIPE` / exit `141` ([`tests/smoke/checkout-errors.sh`](../tests/smoke/checkout-errors.sh)).
  - Inyección de un commit justo antes de `git worktree remove` para probar la protección contra carrera en `close --yes` ([`tests/smoke/close.sh`](../tests/smoke/close.sh)).
- **`gh` falso (`list-remote.sh` y `close-remote.sh`):** se coloca un script `$TMP/bin/gh` al principio del `PATH` que guarda los argumentos recibidos en `$TMP/gh.calls` e imprime el JSON preparado en `$TMP/gh.json` (o devuelve `exit 1` con error en stderr para probar fallos de autenticación).
- **`PATH` mínimo para dependencias faltantes (código `3`):** se crea un directorio temporal con symlinks solo a las utilidades básicas (`bash`, `git`, `jq`, `awk`, `sed`, `cat`, `env`), omitiendo el binario cuya ausencia se quiere verificar (`git` o `jq` en [`tests/smoke/new-errors.sh`](../tests/smoke/new-errors.sh); `gh` en [`tests/smoke/list-remote.sh`](../tests/smoke/list-remote.sh) y [`tests/smoke/close-remote.sh`](../tests/smoke/close-remote.sh)), y se ejecuta con `PATH="$shim"`.

### Compatibilidad con Bash 3.2 y BSD/GNU en los tests

Los archivos de `tests/` pasan por ShellCheck y se ejecutan con `/bin/bash` 3.2 en macOS y en Ubuntu, por lo que deben respetar las mismas reglas de portabilidad descritas en [`docs/plan-v0.1.md` (§5 y §6)](plan-v0.1.md).
