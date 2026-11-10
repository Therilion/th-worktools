# th-worktools — Plan de desarrollo v0.1

> Documento de contexto para desarrollar el kit con agentes (Claude Code / Antigravity).
> Es la fuente de las decisiones tomadas. Si algo cambia, se actualiza aquí primero.
> Ubicación sugerida en el repo: `docs/plan-v0.1.md`.

---

## 1. Qué es

Kit personal y **público** de skills y scripts para agentes de código, compatible con **Claude Code** y **Antigravity CLI**, usado tanto en repos personales como del trabajo. También funciona como pieza de portafolio.

**Principios**

- **Estándar Agent Skills** (`SKILL.md`). Las extensiones propias de un agente se usan solo si el skill sigue funcionando cuando el otro agente las ignora.
- **Nada se escribe en los repos donde se usa el kit.** Todo vive en el kit, en `~/.config/th-worktools/` o en `~/.worktrees/`.
- **Herramientas externas opcionales:** se usan si están instaladas y se omiten si no.
- **Efectos secundarios:** dry-run por defecto; `--yes` para ejecutar.
- **Alcance chico:** cada versión cierra con un DoD. Las ideas nuevas se anotan; no se implementan fuera de su versión.

---

## 2. Decisiones tomadas

| Tema | Decisión |
|---|---|
| Nombre | `th-worktools`; todos los skills usan el prefijo `th-` |
| Agentes | Claude Code y Antigravity CLI. Codex y Pi quedan fuera de alcance |
| Ubicación del kit | `~/.local/share/th-worktools` (ruta fija; puede ser un symlink al clon de desarrollo) |
| Raíz de worktrees | `~/.worktrees` (configurable con `TH_WORKTREES_ROOT`) |
| Layout de worktrees | `<root>/<owner>/<repo>/<rama-normalizada>` y PRs en `<root>/<owner>/<repo>/pr-reviews/pr-<n>/code` |
| Lenguaje de scripts | bash compatible con 3.2. TypeScript solo si un script se vuelve inmanejable |
| Dependencias requeridas | `git`, `jq`; `gh` solo para funciones de GitHub |
| Dependencias opcionales | `codegraph` |
| Plataforma de código | GitHub (`gh`). GitLab queda fuera de la v0.1 |
| Indexador de código | codegraph (opcional). Serena y graphify descartados por ahora |
| Distribución | `install.sh` propio con symlinks (no `npx skills`) |
| Visibilidad | Repo público: ningún dato del trabajo entra al repo |

### Por qué la ubicación del kit es fija

Tres cosas dependen de esa ruta. Si se mueve, se rompen todas:

1. Los symlinks desde `~/.claude/skills/` y la ruta global de Antigravity.
2. La ruta fija en cada `SKILL.md`: `"$HOME/.local/share/th-worktools/skills/<skill>/scripts/…"`. En los dos agentes, esa ruta es la única forma de encontrar los scripts.
3. Los enlaces en `~/.local/bin/` para usar los scripts desde la terminal.

El clon de desarrollo puede vivir donde sea; la ruta fija apunta a él:

```bash
ln -s ~/dev/th-worktools ~/.local/share/th-worktools
```

---

## 3. Estructura del repo

```
th-worktools/
├── AGENTS.md                 # instrucciones para agentes que desarrollan el kit (ver §18)
├── CLAUDE.md                 # contiene solo: @AGENTS.md
├── README.md
├── docs/
│   ├── plan-v0.1.md          # este documento
│   ├── th-worktree.md        # referencia de usuario de th-wt
│   └── desarrollo.md         # guía de desarrollo y convenciones de tests
├── install.sh                # crea symlinks de skills y entrypoints (hecho, #12a)
├── verify.sh                 # comprueba que cada agente ve los skills (hecho, #12b)
├── lib.sh                    # compartido por install.sh y verify.sh: tabla de agentes, resolve, lectura de --agents
├── examples/
│   └── config/               # configuración de ejemplo, solo con valores ficticios (repos/ y config global listos, #7 y #8)
├── skills/
│   └── th-worktree/
│       ├── SKILL.md
│       └── scripts/
│           ├── th-wt         # entrypoint: usage, dependencias y despacho; carga solo el archivo del subcomando
│           ├── lib.sh        # funciones compartidas: die, bad_usage, resolve_repo, rama por defecto de origin
│           ├── new.sh        # subcomando new
│           ├── checkout.sh   # subcomando checkout
│           ├── list.sh       # subcomando list
│           ├── pr.sh         # subcomando pr
│           └── close.sh      # subcomando close
├── tests/
│   ├── smoke.sh              # ejecuta tests/smoke/*.sh, cada uno en un repo temporal propio
│   ├── lib.sh                # fixture compartida (HOME aislado, origin bare, fail/pass)
│   ├── smoke/                # un archivo por tema: new, new-errors, cli, list…
│   └── lint-skills.sh        # validaciones estáticas de los SKILL.md
└── .github/workflows/ci.yml
```

**Los skills no comparten archivos entre sí**, porque el estándar no lo contempla. Si dos skills necesitan la misma lógica, se duplica (si es poca) o se compone por instrucciones: "usa el skill th-…".

---

## 4. Convenciones de skills

- `name` igual al nombre de la carpeta: prefijo `th-`, minúsculas y guiones.
- `description`: qué hace y cuándo usarlo. Si el skill tiene efectos secundarios, agregar: *"Úsalo solo cuando el usuario lo pida explícitamente."*
- `disable-model-invocation: true` en los skills con efectos secundarios. Claude Code y Antigravity (agy 1.5.3) lo respetan: el modelo no ve el skill y solo se invoca con `/<name>`. La descripción también es restrictiva, por si un agente lo ignora.
- `SKILL.md` de menos de 500 líneas; el detalle va a `references/`.
- El cuerpo no nombra herramientas de un agente específico: "lee el archivo", no "usa Read".
- **Rutas a scripts, siempre con la ruta fija, sin llaves:**
  ```
  "$HOME/.local/share/th-worktools/skills/th-worktree/scripts/th-wt"
  ```
  Nunca `scripts/th-wt` a secas: el agente ejecuta desde el repo del usuario, no desde la carpeta del skill (fue el bug de `ce-worktree` en compound-engineering). Nunca `${…}`: Claude Code pide permiso siempre ante un comando con variables entre llaves, sea cual sea la regla (#13), y eso rompe los permisos sugeridos de §13. `tests/lint-skills.sh` lo verifica.
- Acciones de un mismo dominio = **subcomandos como argumentos**, no un skill por acción (ver §9).

---

## 5. Convenciones de scripts

- Shebang `#!/usr/bin/env bash` y `set -euo pipefail`.
- **Sin prompts interactivos** (`read`): los agentes ejecutan sin TTY y el script quedaría colgado.
- **Efectos secundarios:** sin `--yes` solo se muestra el plan (dry-run); con `--yes` se ejecuta.
- **Salida:** mensajes para personas a stderr (excepción: `--help`/`-h` y, sin `--json`, las filas de `list` van a stdout para poder filtrarlas con `grep`; sus avisos siguen en stderr). `new` y `checkout` sin `--json` escriben `  path:   <ruta>` por stderr al terminar bien, como `pr`. Con `--json`, un único objeto JSON a stdout, generado con `jq` (`-n` o `-s`), nunca a mano.
- **Códigos de salida:** `0` OK · `1` error · `2` uso incorrecto · `3` dependencia faltante · `4` precondición no cumplida (cambios sin commitear, destino existente, `origin` o GitHub inaccesibles, etc.).
- `--help` en cada entrypoint.
- **Nunca imprimir el contenido** de archivos de entorno o configuración sensible; solo nombres de archivo.
- **Resolver la propia ubicación siguiendo symlinks**, porque el script puede invocarse desde `~/.local/bin`:

```bash
src="${BASH_SOURCE[0]}"
case "$src" in */*) ;; *) src="./$src" ;; esac
while [ -L "$src" ]; do
  dir="$(cd -P "${src%/*}" && pwd)"
  src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
SCRIPT_DIR="$(cd -P "${src%/*}" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
. "$SCRIPT_DIR/lib.sh"
```

---

## 6. Compatibilidad macOS + Linux

### Bash 3.2

El objetivo es el bash de macOS (`/bin/bash`, 3.2). No basta con exigir el de Homebrew: los agentes no siempre heredan tu `PATH` completo, y `#!/usr/bin/env bash` puede resolver al bash del sistema.

**No usar:**

- `declare -A` (arrays asociativos), `mapfile` / `readarray`
- `local -n`, `[[ -v var ]]`, `wait -n`, `coproc`, `|&`
- `${var,,}` / `${var^^}` (usar `tr '[:upper:]' '[:lower:]'`)

**Trampas:**

- Array vacío con `set -u` falla en bash < 4.4 → usar `${arr[@]+"${arr[@]}"}`.
- `local x=$(cmd)` oculta el código de salida de `cmd` → declararla y asignarla en dos líneas (`local x; x=$(cmd)`).
- `case … esac` dentro de `$( … )` falla en 3.2 (parsea mal el `)` de los patrones) → moverlo a una función.
- El entrypoint `th-wt` usa solo builtins antes de la comprobación de dependencias (`${src%/*}`, no `dirname`), porque los tests lo ejecutan con un `PATH` mínimo sin `dirname`.

### GNU (Linux) vs BSD (macOS)

| Evitar | Usar |
|---|---|
| `sed -i` (cambia la sintaxis) | escribir a un temporal y luego `mv` |
| `sed -r` | `sed -E` |
| `readlink -f`, `realpath` | `cd -P "$dir" && pwd` |
| `date -d` / `date -v` | evitar aritmética de fechas; `date +%s` está bien |
| `stat -c` / `stat -f` | evitar `stat` |
| `grep -P` | `grep -E` |
| `find -printf`, `xargs -r`, `sort -V` | bucles `while IFS= read -r` |
| `mktemp -t prefijo` | `mktemp -d "${TMPDIR:-/tmp}/th.XXXXXX"` |
| `wc -l` sin más | `wc -l \| tr -d ' '` (macOS agrega espacios) |

Funcionan igual en ambos: `find -L`, `find -maxdepth`, `cp -a`, `ln -sfn`, `sed -E`, `mktemp -d`.

### JSON

- `jq` es dependencia **requerida**: se declara en el README y se verifica al inicio (código de salida `3` si falta).
- Para la salida de `gh`, preferir `gh … --json campos --jq 'expr'`: menos procesos y sin pipes.
- `jq` para todo lo demás, incluida la construcción de la salida `--json` de los scripts.

### Verificación

- **ShellCheck** sobre todos los `.sh` y los entrypoints sin extensión (`th-wt`).
- **CI** con matriz `macos-latest` + `ubuntu-latest` (§14).
- Probar Linux en local con Podman:
  ```bash
  podman run --rm -v "$PWD":/w -w /w ubuntu:24.04 \
    bash -c 'apt-get update -qq && apt-get install -y -qq git jq >/dev/null && tests/smoke.sh'
  ```

---

## 7. Configuración

### Ubicación y precedencia

- Directorio: `${XDG_CONFIG_HOME:-$HOME/.config}/th-worktools/`
- Precedencia: **variable de entorno > archivo `config` > valor por defecto**.

### Global: `config`

Formato `CLAVE=valor`, una por línea; `#` para comentarios.
**Se parsea línea a línea, nunca se hace `source`**: la configuración no debe poder ejecutar código.

| Clave | Por defecto | Uso |
|---|---|---|
| `TH_WORKTREES_ROOT` | `~/.worktrees` | Raíz de todos los worktrees |
| `TH_INSTALL_DEPS` | `1` | Instalar dependencias al crear un worktree |
| `TH_CODEGRAPH` | `auto` | `auto` (usar si está instalado) u `off`. `off` solo afecta a la creación, no a `close` |
| `TH_PR_LIMIT` | `500` | Límite de PRs consultados en `list --remote` (mínimo `100`) |

Archivo: `${XDG_CONFIG_HOME:-$HOME/.config}/th-worktools/config`. `#` y las líneas vacías se ignoran, se tolera CRLF y, si una clave se repite, gana la última. Una variable de entorno vacía cuenta como no definida.

**Carga:** al empezar cualquier subcomando, después de parsear sus argumentos (así `--help` y los errores de uso no dependen del config). Sin archivo ni variables, todo funciona con los valores por defecto.

**Validaciones (si alguna falla, no se crea ni se borra nada y sale con `4`):**

1. Clave conocida (`unknown key: <CLAVE>`; una clave que no está en mayúsculas sale como `invalid key (not shown)`) y formato `CLAVE=valor` (`expected KEY=value`).
2. `TH_WORKTREES_ROOT`: ruta absoluta o con `~/` al inicio (se expande a `$HOME`), sin segmentos `.`, `..` ni vacíos; una barra final se ignora. No se expanden `$VAR`. Se resuelven los symlinks de la parte que existe, así una raíz bajo un symlink funciona y `list`/`close` comparan contra las rutas reales de git.
   También se rechazan (exit `4`, sin crear ni borrar nada): `TH_WORKTREES_ROOT must not contain control characters`; `cannot resolve the worktrees root: <ruta>` (p. ej. un symlink roto o un ancestro sin permiso); y `worktrees root <raíz>/<owner>/<repo> overlaps the main checkout <ruta>` (la raíz del repo y el checkout principal no pueden contenerse uno a otro).
3. `TH_INSTALL_DEPS`: `0` o `1`. Con `0`, `new` y `checkout` no instalan (`deps: "skipped"`) y avisan por stderr; `pr` no cambia (nunca instala).
4. `TH_CODEGRAPH`: `auto` u `off` (`TH_CODEGRAPH must be auto or off: <valor>`).
5. `TH_PR_LIMIT`: entero positivo sin ceros a la izquierda y con un mínimo de 100 (`TH_PR_LIMIT must be an integer >= 100: <valor>`).

El error es `th-wt: <ruta del config>:<línea>: <motivo>` o, si falla una variable de entorno, `th-wt: <VAR> (environment): <motivo>`. Tras cambiar la raíz, `list` y `close` solo ven la nueva. No hay subcomando para ver la configuración efectiva.

### Por repo: `repos/<owner>/<repo>.conf`

`<owner>/<repo>` se deriva del remote `origin` (ver más abajo). Sin este archivo, **no se enlaza nada**. `pr` (y `checkout` de una rama `review/pr-*`) nunca lo aplica: el código del PR podría leer los `.env` enlazados.

```
# ~/.config/th-worktools/repos/mi-org/mi-repo.conf
link .wiki
link .env
link docs/local
```

Una acción por línea; `#` y las líneas vacías se ignoran. Se parsea línea a línea, nunca con `source`.

| Acción | Efecto |
|---|---|
| `link <ruta>` | Symlink desde el worktree hacia `<ruta>` en el checkout principal |

No hay `copy`: multiplicaría secretos en disco, y una lista de nombres prohibidos nunca está completa (idea en el README).

**Validaciones (se validan todas las líneas antes de enlazar nada; si alguna falla, no se enlaza ninguna, se deshace el worktree recién creado, y la rama si la creó el comando y sigue en su commit de inicio, y sale con `4`; un fallo al enlazar ya validado también lo deshace, con código `1`):**

1. Acción `link` con exactamente una ruta; ruta relativa: sin `/` inicial, sin segmentos `.`, `..` ni vacíos (`a//b`) y sin barra final.
2. Rutas exactas, sin globs (`*`, `?`, `[`) (v0.1).
3. Sin duplicados ni entradas que se solapen (`docs` y `docs/local`).
4. Debe existir en el checkout principal (la primera entrada de `git worktree list`).
5. Si algún padre de la ruta ya existe en el worktree, debe ser un directorio real (no un archivo versionado ni un symlink).
6. **Debe estar ignorada por git en el worktree nuevo** (`git check-ignore -q <ruta>` antes de crear el enlace: git la ve como archivo, igual que al symlink, y usa el `.gitignore` de la rama abierta). Así nunca se enlaza un archivo versionado y no hay riesgo de commitearlo. Si solo está ignorada como directorio (`.wiki/`), se rechaza con un mensaje que lo explica (ver «Gitignore y symlinks», §8).

El error es `th-wt: <ruta del .conf>:<línea>: <motivo>`. Un worktree sin `.conf` no enlaza nada y no avisa. Una rama local que ya existía y se abrió con `checkout` se conserva siempre.

**Enlace:** symlink con destino absoluto `<checkout principal>/<ruta>`, creando los directorios intermedios en el worktree. El script nunca escribe en `.git/info/exclude`.

### Derivación de `<owner>/<repo>`

| Remote | Resultado |
|---|---|
| `git@github.com:owner/repo.git` | `owner/repo` |
| `git@github-work:acme/demo` (alias SSH) | `owner/repo` |
| `https://github.com/owner/repo(.git)` | `owner/repo` |
| `GitLab con subgrupos group/sub/repo` | `group/sub/repo` (ruta completa, sin host) |
| Sin `origin` | `_local/<nombre-del-directorio>` |

- **Nombre del repo principal**, también cuando se ejecuta desde un worktree:
  `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`
- **Ramas normalizadas:** `/` → `-` en el nombre del directorio; la rama conserva su nombre real.
- **Nombre reservado:** `pr-reviews`.

---

## 8. Seguridad y privacidad

### Archivos de entorno (`.env*`)

**Riesgos:**

- Copias del mismo secreto multiplicadas en disco.
- Restos en worktrees abandonados.
- Lectura por el agente: el contenido entra al contexto del modelo y se envía al proveedor.
- Commit accidental.

**Decisiones:**

1. **Opt-in por repo.** Por defecto no se toca ningún `.env`.
2. **Solo `link`, nunca copias:** queda una sola copia del secreto en disco, y al borrar el worktree solo desaparece el enlace (`git worktree remove` no sigue el symlink). Un worktree no puede tener valores propios (otro puerto, otra base de datos); idea en el README.
3. **`pr` no aplica el `.conf`:** el código de un PR (de un fork, de un tercero) podría leer los secretos enlazados.
4. **Validación con `git check-ignore`** (§7).
5. **Los scripts nunca imprimen contenido**; el dry-run lista solo nombres.
6. **Bloquear la lectura por parte de los agentes**, en la configuración de usuario (§13). Es una mitigación, no una garantía: un comando que ejecuta la aplicación igual carga las variables.

### Gitignore y symlinks

Una entrada con barra final (`.wiki/`) **no ignora un symlink**, porque para git un symlink es un archivo. Para los directorios enlazados, la entrada va **sin barra** (en el `.gitignore` o en el `.git/info/exclude` del repo, que es local y se comparte entre todos los worktrees). Lo agrega el usuario: el script no lo escribe, solo rechaza la entrada (§7, validación 6) y el agente sugiere la línea (la `<ruta>` sin barra).

### Repo público

- Ningún nombre de organización, repo, ruta interna, clave de ticket ni URL del trabajo entra al repo. Todo eso va a `~/.config/th-worktools/`.
- `examples/config/` contiene solo valores ficticios.
- Revisar el diff antes de cada push. Más adelante: `gitleaks` en CI.

---

## 9. Subcomandos

**Un skill por dominio, con las acciones como argumentos.**

- **Claude Code y Antigravity:** `/th-worktree new feature/login`, `/th-worktree cierra feature/login`. Con `disable-model-invocation` el modelo no ve el skill, así que sin la `/` no se activa. El texto tras el nombre llega al modelo en los dos agentes; el `SKILL.md` no usa `$ARGUMENTS`, porque Antigravity no lo sustituye.
- El `SKILL.md` incluye una tabla que asocia cada subcomando con su invocación del script. Si las instrucciones de un subcomando crecen, se mueven a `references/<subcomando>.md`, que se lee solo cuando aplica.
- La sintaxis `th:worktree`, con dos puntos, requiere empaquetar el kit como **plugin** de Claude Code (namespace `plugin:skill`). Queda fuera de la v0.1 y se evalúa después.

---

## 10. Herramientas y skills de terceros

- **Preferir herramientas (CLI/MCP) a skills como dependencias:** su interfaz es estable y se detectan de forma determinista (`command -v codegraph`).
- **Skills de terceros:** con una instrucción condicional en el `SKILL.md`: *"Si tienes disponible el skill X, úsalo para Y; si no, haz Z."* El modelo conoce su propia lista de skills.
- **MCP** (por ejemplo, Jira): con el mismo patrón: *"Si tienes herramientas de Jira disponibles…"*.
- **Riesgos:** el texto de un skill ajeno cambia con cada actualización, y su nombre puede cambiar o colisionar con otro.
  **Mitigación:** instalarlos desde un tag o commit fijo, y listar en el README las dependencias opcionales con la versión probada.

---

## 11. Skill v0.1: `th-worktree`

### Subcomandos

| Subcomando | Efecto | Requiere `--yes` |
|---|---|---|
| `new <rama> [--base <rama>]` | Rama nueva desde `origin/<rama>` (por defecto, la rama por defecto de `origin`) | No |
| `checkout <rama> [--remote]` | Worktree de una rama existente, local o remota | No |
| `pr <n>` | Worktree de un PR en `pr-reviews/pr-<n>/code` | No |
| `list [--remote]` | Worktrees del repo actual bajo la raíz, con su estado (`--remote` actualiza la rama por defecto de `origin` y consulta los PRs en GitHub) | No |
| `close <rama> [--remote] [--force]` (un PR: `close review/pr-<n>`) | Cierra el worktree (`--remote` considera mergeada la rama si su PR en GitHub está `MERGED` sin commits locales posteriores; ver abajo) | **Sí** |

Crear un worktree no es destructivo y es fácil de revertir, por eso se ejecuta directo. Cerrar sí lo es.

### `new` / `checkout` / `pr`

1. Verificar dependencias (`git`, `jq`; `gh` solo para `pr`).
2. Con `origin`, no hace falta `--git-common-dir`: `<owner>/<repo>` sale de `remote.origin.url`, que es la misma config en el checkout principal y en sus worktrees. `--git-common-dir` solo se usará en el fallback `_local/<directorio>`; mientras tanto, sin `origin` sale con código `4`.
3. Derivar `<owner>/<repo>`, calcular la ruta destino y abortar (código `4`) si ya existe.
4. `git fetch origin +refs/heads/<base>:refs/remotes/origin/<base>` (explícito, para que funcione en clones `--single-branch` o con refspec personalizado; si falla, código `4`; en `checkout` el fetch solo ocurre con `--remote`).
5. Crear el worktree:
   - `new`: `git worktree add --no-track -b <rama> <ruta> origin/<base>` (`--no-track`: la rama nueva no debe seguir a `origin/<base>`, o un `git push` iría a la rama base)
   - `checkout`: si la rama es local, `git worktree add <ruta> <rama>` sin red. Si no, sale de `origin/<rama>` (con `--remote`, primero `ls-remote` y el mismo fetch explícito; sin `--remote`, la copia ya traída): `git worktree add --no-track -b <rama> <ruta> origin/<rama>` y el upstream (`branch.<rama>.remote`/`.merge`) se escribe a mano, porque `--track` falla en clones `--single-branch`.
   - `pr`: `git fetch -q --no-tags origin refs/pull/<n>/head` (solo `FETCH_HEAD`) y `git worktree add --no-track -b review/pr-<n> <ruta> <oid>`. Metadatos con `gh pr view <n> -R <owner>/<repo> --json number,title,headRefName,baseRefName`.
6. Aplicar el `.conf` del repo (`link`, validados, §7), salvo en `pr` y en `checkout` de `review/pr-*`. Si una entrada es inválida, se deshace la creación (worktree y, si la creó el comando, rama) y sale con `4`; el stderr lleva `th-wt: <conf>:<línea>: <motivo>`, y en texto cada enlace se informa como `th-wt: linked <ruta>`.
7. Si `TH_INSTALL_DEPS=1`, instalar dependencias según el lockfile:
   - `pnpm-lock.yaml` → `pnpm install --frozen-lockfile`
   - `package-lock.json` → `npm ci`
   - Cualquier otro: avisar por stderr y omitir (v0.1); se avisa el nombre de `yarn.lock`, `bun.lock`, `bun.lockb`, `Cargo.lock`, `uv.lock` o `poetry.lock` si existe.
   - Si hay ambos lockfiles gana pnpm. Corre en el worktree, con la salida del gestor a stderr (stdout queda para `--json`) y `</dev/null`. `pr` **no instala** (`deps: "skipped"`): el `.npmrc` y el `packageManager` del PR controlan el gestor y la instalación ejecutaría código de un tercero (`--ignore-scripts` no basta); solo avisa por stderr con el comando a ejecutar a mano (`pnpm install --frozen-lockfile` / `npm ci`) si hay un lockfile soportado.
   - Si el gestor falla: se conserva el worktree, aviso por stderr, `deps: "failed"` y código `0`. Si hay lockfile pero el gestor no está en `PATH`: aviso por stderr, `deps: "skipped"` y código `0`.
8. Si `TH_CODEGRAPH=auto` y codegraph está instalado, después de las dependencias: `codegraph init -y <worktree>` (`-y` = no interactivo, toma los valores por defecto; verificado con codegraph 1.6.2), con la salida a stderr y `</dev/null`, y con `CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_UPDATE_CHECK=1` (sin telemetría ni comprobación de actualizaciones, para que el subcomando siga offline) y `CODEGRAPH_NO_WATCH=` y `CODEGRAPH_DIR=` vacías (con `CODEGRAPH_NO_WATCH=1` en el entorno del usuario, `init -y` instalaría hooks de sincronización de git en el `.git/hooks` compartido, que el kit no debe escribir; y `CODEGRAPH_DIR` movería el índice a una carpeta que el kit no comprueba). No indexa si `.codegraph` ya existe en el worktree como symlink (p. ej. `link .codegraph` del `.conf`) o con algo más que un `.gitignore` que sea un archivo regular (p. ej. un PR que versiona su `.codegraph/codegraph.db`, o un `.gitignore` que es un symlink): aviso `th-wt: warning: .codegraph already exists in <ruta>; not indexed`, `codegraph: false`, código `0`; un índice aportado por un PR nunca se usa. También en `pr` y en `checkout` de `review/pr-*`: indexar es análisis estático y no ejecuta el código del PR (el índice que traiga el PR es otro asunto: ver arriba). Igual que las dependencias, si falla se conserva el worktree, aviso por stderr (`th-wt: warning: codegraph init failed in <ruta>; run 'codegraph init -y' there manually`), `codegraph: false` y código `0`. Sin codegraph instalado o con `off`: `codegraph: false` sin mensaje. `init` puede tardar minutos en un repo grande.
9. Mostrar un resumen. Con `--json`:
   `{ "path", "branch", "repo", "linked": [], "deps": "pnpm|npm|skipped|failed", "codegraph": true|false }`
   (`codegraph: true` = indexado; `false` = no instalado, `off` o `init` falló.)
   (`linked`: array de rutas enlazadas; siempre `[]` en `pr`. No hay campo `copied`: no existe `copy`.)
10. Indicar al usuario que abra **una sesión nueva del agente** en esa ruta.

### `close`

**Sin `--yes` (dry-run)** muestra: ruta, rama, si está mergeada, si hay cambios sin commitear o commits sin push, y qué se va a eliminar.

**Con `--yes`:**

1. Abortar (código `4`) si hay cambios sin commitear o commits sin push, salvo que se pase `--force`.
2. Si `.codegraph/` es un directorio real (no un symlink) y git no versiona nada dentro: el kit borra `.codegraph/` él mismo, justo antes de `git worktree remove`, sin ejecutar `codegraph` (no hace falta que esté instalado). No usa `codegraph uninit`: además de borrar la carpeta, quita los hooks de sincronización de git del `.git/hooks` compartido por el checkout principal y todos los worktrees, y el kit no escribe en el repo del usuario (verificado con codegraph 1.6.2: su `uninitialize` solo cierra la base de datos y borra la carpeta, así que borrarla directamente no pierde nada). Si git versiona algo bajo `.codegraph/`, el kit no lo toca: `git worktree remove` se lleva el índice ignorado. `TH_CODEGRAPH=off` no afecta a `close`. En `list` y en el dry-run de `close`, lo que genera codegraph (el directorio `.codegraph/` sin seguimiento y sus archivos ignorados) no cuenta como cambio pendiente (`dirty`) ni se lista en `ignored`; los cambios en archivos que git versiona bajo `.codegraph/` (p. ej. un `.codegraph/.gitignore` commiteado) sí cuentan como `dirty` y bloquean el cierre sin `--force`.
3. `git worktree remove <ruta>` (con `--force` solo si se pasó explícitamente).
4. Rama:
   - Normal: si está contenida en la rama por defecto de `origin` (mismo criterio que `list`), `git update-ref -d refs/heads/<rama> <oid>`, que falla si la rama se movió. No se usa `git branch -d` porque compara contra el HEAD local, que suele estar atrasado, y rechaza ramas ya mergeadas. Si no está contenida (o no se sabe), se conserva y se avisa; **no se fuerza**.
   - Worktree de PR (`pr-reviews/pr-<n>/code`, por la ruta): se borra `review/pr-<n>` (es solo una copia local del PR remoto), salvo con `--force` y commits propios posteriores al PR (o desconocidos): ahí se conserva. Bloquean `dirty` y los commits propios posteriores a la creación de la rama (primera entrada de su reflog; sin reflog, desconocido).
5. Sin `git worktree prune`: `git worktree remove` ya limpia su propio registro, incluso si el directorio ya no existe, y `prune` borraría también el registro de otros worktrees con el directorio faltante.
6. PRs: eliminar `pr-reviews/pr-<n>/` solo si quedó vacío. Los demás archivos de `pr-<n>/` (p. ej. `report.md`) los gestionará `th-pr-review` (v0.3); `close` no los toca.

### `list`

`git worktree list --porcelain`, filtrado a los worktrees bajo `TH_WORKTREES_ROOT`, con estado: limpio o con cambios, mergeada o no.

### Borrador de `SKILL.md`

> Borrador inicial; la versión vigente es [`skills/th-worktree/SKILL.md`](../skills/th-worktree/SKILL.md).

````markdown
---
name: th-worktree
description: Crea, lista y cierra git worktrees en ~/.worktrees, con dependencias instaladas, enlaces de configuración por repo y codegraph opcional. Úsalo solo cuando el usuario pida explícitamente crear, revisar un PR en, listar o cerrar un worktree.
disable-model-invocation: true
---

# th-worktree

Script (ruta relativa a la carpeta de este SKILL.md, no al repo actual):

`"$HOME/.local/share/th-worktools/skills/th-worktree/scripts/th-wt"`

## Subcomandos

| Pedido del usuario | Comando |
|---|---|
| Crear rama nueva | `th-wt new <rama> [--base <rama>] --json` |
| Trabajar en rama existente | `th-wt checkout <rama> --json` |
| Revisar un PR | `th-wt pr <n> --json` |
| Ver worktrees | `th-wt list --json` |
| Cerrar | `th-wt close <rama>` (un PR: `close review/pr-<n>`; ver reglas) |

Argumentos recibidos: $ARGUMENTS

## Reglas

- `close`: ejecutar primero **sin** `--yes`, mostrar el plan al usuario y esperar confirmación explícita antes de repetirlo con `--yes`.
- No usar `--force` salvo que el usuario lo pida.
- Al terminar `new`, `checkout` o `pr`: informar la ruta y sugerir abrir una sesión nueva del agente ahí.
- Código de salida `3`: informar qué dependencia falta y detenerse.
- Código de salida `4`: mostrar el motivo y preguntar al usuario cómo seguir.
````

---

## 12. Instalación

**`install.sh`** (#12a)

Uso: `install.sh [--link-here] [--agents <lista>] [--yes]`, `-h|--help`. Dry-run por defecto (muestra el plan en stderr y no cambia nada); `--yes` lo aplica.

1. Ruta fija `~/.local/share/th-worktools`. Con `--link-here` es un symlink al clon donde vive el script. Sin `--link-here`, si la ruta no existe sale con `4`. Con `--link-here`, si la ruta existe y no es este clon, sale con `4` sin tocar nada. Si la ruta es un symlink colgante (no resuelve a un directorio), sale con `4` con `is a broken symlink`, con o sin `--link-here`, antes de comprobar si es este clon. Si hay que crearla y su padre no es un directorio, sale con `4` sin tocar nada.
2. Agentes soportados:

   | Agente | Binario | Ruta de skills |
   |---|---|---|
   | Claude Code | `claude` | `~/.claude/skills/` |
   | Antigravity | `agy` | `~/.gemini/config/skills/` (verificado en agy 1.5.3; sigue symlinks) |

   Por defecto, los que tengan el binario en el `PATH`; si no hay ninguno, instala igualmente la ruta fija y los entrypoints y avisa. `--agents claude,agy` los elige: un agente no soportado sale con `2` y uno pedido que no está en el `PATH`, con `3`; en ambos casos no cambia nada.
3. Solo se enlazan los `skills/th-*/` (cada uno en cada agente elegido) y cada ejecutable de `skills/th-*/scripts/` (hoy `th-wt`) en `~/.local/bin/`, siempre a través de la ruta fija (por ejemplo, `~/.claude/skills/th-worktree -> ~/.local/share/th-worktools/skills/th-worktree`). `th-wt` desde la terminal exige `~/.local/bin` en el `PATH`.
4. Plan en stderr, una línea por destino: `create <destino> -> <objetivo>`, `ok <destino>`, `fix <destino> -> <objetivo>`, `skip <destino> (not part of the kit)`, `skip <destino> (parent is not a directory)`. Repetirlo lo deja todo en `ok` y no cambia nada.
5. Un symlink es propio del kit si, resuelto, apunta dentro del kit: si ya pasa por la ruta fija es `ok`; si no (por ejemplo, directo al clon) se reapunta a través de la ruta fija (`fix`). Cualquier otra cosa en un destino (archivo, directorio, symlink a otro sitio, symlink colgante) no se toca nunca: `skip`, se instala el resto y sale con `4`. Un symlink cuyo valor absoluto pasa por la ruta fija es del kit aunque esa ruta aún no exista (`fix`), igual en dry-run y con `--yes`. Si el padre de un destino es un archivo o un symlink colgante, se trata como cualquier otra ruta ajena: `skip (parent is not a directory)`.

Códigos de salida: `2` agente no soportado, `3` agente pedido que no está en el `PATH`, `4` ruta del kit ausente o ajena, o rutas sin tocar.

**`verify.sh`** (#12b)

Uso: `verify.sh [--agents <lista>]`, `-h|--help`. Solo lectura: no escribe, no usa la red y no lanza los agentes. Comprueba el clon donde vive el script.

1. Sin `--agents`, los agentes soportados que estén en el `PATH` (igual que `install.sh`). Con `--agents`: un agente no soportado sale con `2` y uno pedido que no está en el `PATH`, con `3`; en ambos casos antes de comprobar nada.
2. Una línea por elemento en stderr, sin detenerse en el primer fallo, en este orden:
   - La ruta fija `~/.local/share/th-worktools`: `ok` si resuelve a este clon.
   - Cada `skills/th-*/` en el directorio de skills de cada agente elegido: `ok` si, resuelto, llega a la carpeta del skill en el kit (también si apunta directo al clon) y el `name` de su `SKILL.md` coincide con la carpeta.
   - Cada entrypoint de `~/.local/bin`: `ok` si resuelve al script del kit.
   - `git` y `jq`.
3. Formato de línea: `ok     <ruta>` o `fail   <ruta> (<causa>)`. Causas: `missing`, `broken symlink`, `not a symlink`, `points outside the kit: <ruta>`, `name '<x>' does not match its folder`; dependencias: `fail   jq (not found in PATH)`.
4. Al final, en stderr:
   - Si `~/.local/bin` no está en el `PATH`: `verify.sh: warning: ~/.local/bin is not in PATH; th-wt will not run from the terminal`. No cambia el código de salida.
   - Si falló algo que no sea una dependencia: `verify.sh: <N> problem(s) found; run install.sh --yes (install.sh --link-here --yes from the clone if the kit path is missing)`.
   - Si todo está bien: `verify.sh: all ok`.

Códigos de salida: `0` todo bien, `2` uso incorrecto o agente no soportado, `3` falta una dependencia requerida (`git` o `jq`; tiene prioridad sobre `4`), `4` cualquier otro fallo.

---

## 13. Permisos sugeridos (configuración de usuario)

**Claude Code** — `~/.claude/settings.json`

```json
{
  "permissions": {
    "allow": ["Bash(*th-wt list*)"],
    "ask": ["Bash(*th-wt close*--yes*)"],
    "deny": ["Read(**/.env*)"]
  }
}
```

**Antigravity CLI** — `~/.gemini/antigravity-cli/settings.json`

```json
{
  "permissions": {
    "allow": ["command(regex:.*/th-wt\"? list( .*)?)"],
    "ask": ["command(regex:.*/th-wt\"? close .*--yes.*)"]
  }
}
```

Verificado el 2026-11-10 en macOS con Claude Code 2.1.311 y agy 1.5.3 (#13):

- `list` y `list --remote` corren sin pedir permiso en los dos agentes. Sin la regla `allow`, los dos lo piden; agy también para `list` (el plan original no tenía `allow` para agy).
- `ask` gana a `allow` en ambos: `close … --yes` pide permiso incluso con un `allow` amplio (`Bash(*th-wt*)`, `command(regex:.*th-wt.*)`). El `close` sin `--yes` (dry-run) pide permiso en agy porque no coincide con el `allow`.
- Un comando encadenado (`… list --json && touch …`) pide permiso en los dos.
- Claude Code rechaza auto-aprobar cualquier comando con `${…}` («A variable in braces in this command can't be checked before it runs»), sea cual sea la regla. Por eso el `SKILL.md` usa la ruta fija `"$HOME/.local/share/th-worktools/skills/th-worktree/scripts/th-wt"`, sin llaves.
- En agy, la comilla de cierre de la ruta queda entre `th-wt` y el subcomando; el patrón original `command(regex:.*th-wt close.*--yes.*)` no coincidía. De ahí `th-wt"?` en los patrones de agy.
- `Read(**/.env*)` deniega leer `.env.local` con la herramienta de lectura de Claude Code. Límite: no cubre un `cat .env` por la shell. En agy no se probó bloquear `.env`.

---

## 14. CI (`.github/workflows/ci.yml`)

Matriz: `macos-latest` y `ubuntu-latest`.

1. **ShellCheck** sobre todos los scripts.
2. **`tests/lint-skills.sh`:**
   - `name` en el frontmatter igual al nombre de la carpeta.
   - Toda línea con `scripts/` lleva la forma `"$HOME/.local/share/th-worktools/skills/<carpeta>/scripts/` y ninguna usa `${`.
3. **`tests/smoke.sh`:** crea un repo temporal con un remote local (`git init --bare` como `origin`) y ejecuta `new` → `list` → `close` (dry-run) → `close --yes`. No requiere `gh`.

---

## 15. Definition of Done — v0.1

- [x] `th-worktree` crea worktrees para una rama nueva, para una rama existente y para un PR.
- [ ] Al crear: aplica el `.conf` del repo (enlaza `.wiki`), instala dependencias e inicializa codegraph si está disponible (parcial: `.conf` del repo, solo `link` y sin `copy` (#7), instalación de dependencias y codegraph listos).
- [x] Al cerrar: dry-run por defecto; con `--yes` borra el índice de codegraph, elimina el worktree y borra la rama si está mergeada.
- [x] Funciona invocado desde Claude Code y desde Antigravity en macOS.
- [ ] `git status` limpio en un worktree del repo del trabajo (la `.wiki` enlazada no aparece).
- [x] CI en verde en macOS y Ubuntu.
- [x] README con instalación en tres pasos y dependencias declaradas.

Cuando todo esté marcado: tag `v0.1`, usarlo una semana y anotar lo que moleste. **Esa lista define la v0.2.**

---

## 16. Hoja de ruta

| Versión | Contenido |
|---|---|
| **v0.1** | `th-worktree` + instalación + CI |
| v0.2 | `th-repo-context`: índice de documentación generado al vuelo (`find -L`, título y primer párrafo por documento) y selección de lo relevante |
| v0.3 | `th-pr-review`: `pr-reviews/pr-<n>/{code,report.md,…}`, Stryker limitado a los archivos del diff, salida de tests resumida, comentarios en una sola review vía `gh api` con confirmación |
| v0.4 | `th-integration-context`: documento de contexto entre repos, fuera de los repos |
| Después | Skills de desarrollo, empaquetado como plugin (`th:…`), GitLab |

---

## 17. Por verificar al empezar

- [x] Ruta global de skills de Antigravity en la versión instalada. `~/.gemini/config/skills/` según la guía integrada de agy 1.5.3 (el plan decía `~/.gemini/antigravity/skills/`); sigue symlinks (2026-11-09).
- [x] Que Claude Code sustituya `${CLAUDE_SKILL_DIR}` dentro de la forma `${CLAUDE_SKILL_DIR:-…}`. **No:** la variable no existe en el shell de Bash (2026-10-26). Sin el symlink fijo, Claude improvisó la ruta; con `~/.local/share/th-worktools` presente, la ruta del `SKILL.md` funciona. El fallback fijo es obligatorio en la instalación (`install.sh`, hecho en #12a; `verify.sh`, en #12b, lo comprueba). Desde #13 el `SKILL.md` usa directamente la ruta fija `"$HOME/.local/share/th-worktools/skills/<skill>/scripts/…"`, sin `${…}`, porque Claude Code pide permiso siempre ante `${…}` (2026-11-10).
- [x] Que Antigravity ejecute los comandos en un shell que expanda `$HOME` y `${…:-…}`. Sí, zsh; `CLAUDE_SKILL_DIR` no existe y se usa el fallback (2026-11-09).
- [ ] Que las búsquedas del agente sigan el symlink `.wiki`.
- [ ] Cómo está la entrada de `.wiki` en el `.gitignore` del repo del trabajo (con o sin barra).
- [x] Flags no interactivos de `codegraph init` y comportamiento de `codegraph uninit`. `init -y` salta todos los prompts y toma los valores por defecto; `uninit -f` salta la confirmación (codegraph 1.6.2). Pero `uninit` también quita los hooks de sincronización de git del `.git/hooks` compartido, así que el kit no lo usa: `close` borra `.codegraph/` directamente.
- [x] Sintaxis de los patrones de permisos en ambos agentes. Verificada en Claude Code 2.1.311 y agy 1.5.3; patrones y hallazgos en §13 (2026-11-10).
- [x] Cómo recibe argumentos un skill en Antigravity. Con `/th-worktree <pedido>`; el texto llega al modelo y `$ARGUMENTS` queda sin sustituir; sin `$ARGUMENTS`, Claude Code y agy pasan igual el texto (y nada si no lo hay), así que el `SKILL.md` no lo usa. `disable-model-invocation: true` oculta el skill al modelo (2026-11-09).
- [x] Timeout de comandos largos en Antigravity. agy pasa el comando a segundo plano y espera a que termine (probado con 200 s); la línea de 600000 ms del `SKILL.md` no le afecta (2026-11-09).

---

## 18. Base para `AGENTS.md`

```markdown
# th-worktools — instrucciones para agentes

- Antes de cambiar algo, lee `docs/plan-v0.1.md`. Las decisiones están ahí; no las reabras sin preguntar.
- Scripts en bash compatible con 3.2 y portables entre macOS y Linux (§6 del plan).
- Antes de dar algo por terminado: `shellcheck` sobre los scripts, `tests/lint-skills.sh` y `tests/smoke.sh`.
- Nunca agregues datos reales del trabajo (organizaciones, repos, rutas, tickets). El repo es público.
- Alcance: solo lo que pide el DoD de la versión vigente. Las ideas nuevas van a la sección "Ideas" del README, no al código.
- Rutas a scripts en SKILL.md: siempre con la forma fija `"$HOME/.local/share/th-worktools/skills/<skill>/scripts/…"`, nunca relativas a secas y nunca con `${…}`.
```
