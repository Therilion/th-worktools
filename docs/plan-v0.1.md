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
2. El fallback en cada `SKILL.md`: `${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/<skill>}`. En Antigravity, esa ruta es la única forma de encontrar los scripts.
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
│   └── plan-v0.1.md          # este documento
├── install.sh                # crea symlinks de skills y entrypoints
├── verify.sh                 # comprueba que cada agente ve los skills
├── examples/
│   └── config/               # configuración de ejemplo, solo con valores ficticios
├── skills/
│   └── th-worktree/
│       ├── SKILL.md
│       └── scripts/
│           ├── th-wt         # entrypoint con subcomandos
│           └── lib.sh        # funciones del skill
├── tests/
│   ├── smoke.sh              # ciclo completo en un repo temporal
│   └── lint-skills.sh        # validaciones estáticas de los SKILL.md
└── .github/workflows/ci.yml
```

**Los skills no comparten archivos entre sí**, porque el estándar no lo contempla. Si dos skills necesitan la misma lógica, se duplica (si es poca) o se compone por instrucciones: "usa el skill th-…".

---

## 4. Convenciones de skills

- `name` igual al nombre de la carpeta: prefijo `th-`, minúsculas y guiones.
- `description`: qué hace y cuándo usarlo. Si el skill tiene efectos secundarios, agregar: *"Úsalo solo cuando el usuario lo pida explícitamente."*
- `disable-model-invocation: true` en los skills con efectos secundarios. Claude Code lo respeta; Antigravity lo ignora, y por eso la descripción también debe ser restrictiva.
- `SKILL.md` de menos de 500 líneas; el detalle va a `references/`.
- El cuerpo no nombra herramientas de un agente específico: "lee el archivo", no "usa Read".
- **Rutas a scripts, siempre con prefijo y fallback:**
  ```
  "${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt"
  ```
  Nunca `scripts/th-wt` a secas: el agente ejecuta desde el repo del usuario, no desde la carpeta del skill (fue el bug de `ce-worktree` en compound-engineering). `tests/lint-skills.sh` lo verifica.
- Acciones de un mismo dominio = **subcomandos como argumentos**, no un skill por acción (ver §9).

---

## 5. Convenciones de scripts

- Shebang `#!/usr/bin/env bash` y `set -euo pipefail`.
- **Sin prompts interactivos** (`read`): los agentes ejecutan sin TTY y el script quedaría colgado.
- **Efectos secundarios:** sin `--yes` solo se muestra el plan (dry-run); con `--yes` se ejecuta.
- **Salida:** mensajes para personas a stderr. Con `--json`, un único objeto JSON a stdout, generado con `jq -n`.
- **Códigos de salida:** `0` OK · `1` error · `2` uso incorrecto · `3` dependencia faltante · `4` precondición no cumplida (cambios sin commitear, destino existente, etc.).
- `--help` en cada entrypoint.
- **Nunca imprimir el contenido** de archivos de entorno o configuración sensible; solo nombres de archivo.
- **Resolver la propia ubicación siguiendo symlinks**, porque el script puede invocarse desde `~/.local/bin`:

```bash
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$src")" && pwd)"
# shellcheck source=lib.sh
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
| `TH_CODEGRAPH` | `auto` | `auto` (usar si está instalado) u `off` |

### Por repo: `repos/<owner>/<repo>.conf`

`<owner>/<repo>` se deriva del remote `origin` (ver más abajo). Sin este archivo, **no se enlaza ni se copia nada**.

```
# ~/.config/th-worktools/repos/mi-org/mi-repo.conf
link .wiki
link .env
copy .env.local
```

| Acción | Efecto |
|---|---|
| `link <ruta>` | Symlink desde el worktree hacia `<ruta>` en el checkout principal |
| `copy <ruta>` | Copia independiente (solo si el worktree necesita valores distintos) |

**Validaciones (si alguna falla, el script aborta antes de modificar nada):**

1. Ruta relativa: sin `/` inicial ni segmentos `..`.
2. Debe existir en el checkout principal.
3. **Debe estar ignorada por git** (`git check-ignore -q <ruta>`). Así nunca se enlaza un archivo versionado y no hay riesgo de commitearlo.
4. Rutas exactas, sin globs (v0.1).

### Derivación de `<owner>/<repo>`

| Remote | Resultado |
|---|---|
| `git@github.com:owner/repo.git` | `owner/repo` |
| `https://github.com/owner/repo(.git)` | `owner/repo` |
| GitLab con subgrupos `group/sub/repo` | `group/sub/repo` (ruta completa, sin host) |
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
2. **Preferir `link` sobre `copy`:** queda una sola copia del secreto en disco, y al borrar el worktree solo desaparece el enlace. `copy` solo cuando el worktree necesita valores distintos (otro puerto, otra base de datos); el script lo advierte.
3. **Validación con `git check-ignore`** (§7).
4. **Los scripts nunca imprimen contenido**; el dry-run lista solo nombres.
5. **Bloquear la lectura por parte de los agentes**, en la configuración de usuario (§13). Es una mitigación, no una garantía: un comando que ejecuta la aplicación igual carga las variables.

### Gitignore y symlinks

Una entrada con barra final (`.wiki/`) **no ignora un symlink**, porque para git un symlink es un archivo. Para los directorios enlazados, agregar la entrada **sin barra** al `.git/info/exclude` del repo. Ese archivo es local y se comparte entre todos los worktrees.

### Repo público

- Ningún nombre de organización, repo, ruta interna, clave de ticket ni URL del trabajo entra al repo. Todo eso va a `~/.config/th-worktools/`.
- `examples/config/` contiene solo valores ficticios.
- Revisar el diff antes de cada push. Más adelante: `gitleaks` en CI.

---

## 9. Subcomandos

**Un skill por dominio, con las acciones como argumentos.**

- **Claude Code:** `/th-worktree new feature/login`, `/th-worktree close feature/login`. Los argumentos llegan al cuerpo del skill vía `$ARGUMENTS`.
- **Antigravity:** en lenguaje natural: "usa th-worktree para cerrar feature/login".
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
| `checkout <rama>` | Worktree de una rama existente, local o remota | No |
| `pr <n>` | Worktree de un PR en `pr-reviews/pr-<n>/code` | No |
| `list` | Worktrees del repo actual bajo la raíz, con su estado | No |
| `close <rama\|pr-<n>> [--force]` | Cierra el worktree (ver abajo) | **Sí** |

Crear un worktree no es destructivo y es fácil de revertir, por eso se ejecuta directo. Cerrar sí lo es.

### `new` / `checkout` / `pr`

1. Verificar dependencias (`git`, `jq`; `gh` solo para `pr`).
2. Con `origin`, no hace falta `--git-common-dir`: `<owner>/<repo>` sale de `remote.origin.url`, que es la misma config en el checkout principal y en sus worktrees. `--git-common-dir` solo se usará en el fallback `_local/<directorio>`; mientras tanto, sin `origin` sale con código `4`.
3. Derivar `<owner>/<repo>`, calcular la ruta destino y abortar (código `4`) si ya existe.
4. `git fetch origin`.
5. Crear el worktree:
   - `new`: `git worktree add --no-track -b <rama> <ruta> origin/<base>` (`--no-track`: la rama nueva no debe seguir a `origin/<base>`, o un `git push` iría a la rama base)
   - `checkout`: `git worktree add <ruta> <rama>` (si la rama solo existe en el remoto, se crea con tracking).
   - `pr`: `git fetch origin pull/<n>/head:th/pr-<n>` y luego `git worktree add <ruta> th/pr-<n>`. Metadatos con `gh pr view <n> --json number,title,headRefName,baseRefName`.
6. Aplicar el `.conf` del repo (`link` / `copy`, validados).
7. Si `TH_INSTALL_DEPS=1`, instalar dependencias según el lockfile:
   - `pnpm-lock.yaml` → `pnpm install --frozen-lockfile`
   - `package-lock.json` → `npm ci`
   - Cualquier otro: avisar y omitir (v0.1).
8. Si `TH_CODEGRAPH=auto` y codegraph está instalado, inicializarlo en el worktree (verificar los flags no interactivos de `codegraph init`).
9. Mostrar un resumen. Con `--json`:
   `{ "path", "branch", "repo", "linked": [], "copied": [], "deps": "pnpm|npm|skipped", "codegraph": true|false }`
10. Indicar al usuario que abra **una sesión nueva del agente** en esa ruta.

### `close`

**Sin `--yes` (dry-run)** muestra: ruta, rama, si está mergeada, si hay cambios sin commitear o commits sin push, y qué se va a eliminar.

**Con `--yes`:**

1. Abortar (código `4`) si hay cambios sin commitear o commits sin push, salvo que se pase `--force`.
2. Si existe `.codegraph/` y codegraph está instalado: `codegraph uninit`.
3. `git worktree remove <ruta>` (con `--force` solo si se pasó explícitamente).
4. Rama:
   - Normal: `git branch -d`. Si falla porque no está mergeada, se informa y **no se fuerza**.
   - `th/pr-*`: `git branch -D` (es solo una copia local del PR remoto).
5. `git worktree prune`.
6. PRs: eliminar `pr-reviews/pr-<n>/` solo si quedó vacío. El directorio `review/` lo gestionará `th-pr-review` (v0.3); `close` no lo toca.

### `list`

`git worktree list --porcelain`, filtrado a los worktrees bajo `TH_WORKTREES_ROOT`, con estado: limpio o con cambios, mergeada o no.

### Borrador de `SKILL.md`

````markdown
---
name: th-worktree
description: Crea, lista y cierra git worktrees en ~/.worktrees, con dependencias instaladas, enlaces de configuración por repo y codegraph opcional. Úsalo solo cuando el usuario pida explícitamente crear, revisar un PR en, listar o cerrar un worktree.
disable-model-invocation: true
---

# th-worktree

Script (ruta relativa a la carpeta de este SKILL.md, no al repo actual):

`"${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt"`

## Subcomandos

| Pedido del usuario | Comando |
|---|---|
| Crear rama nueva | `th-wt new <rama> [--base <rama>] --json` |
| Trabajar en rama existente | `th-wt checkout <rama> --json` |
| Revisar un PR | `th-wt pr <n> --json` |
| Ver worktrees | `th-wt list --json` |
| Cerrar | `th-wt close <rama\|pr-<n>>` (ver reglas) |

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

**`install.sh`**

1. Asegurar la ruta fija `~/.local/share/th-worktools`. Con `--link-here`, crear el symlink hacia el clon actual.
2. Para cada `skills/*/`, crear un symlink en:
   - `~/.claude/skills/<name>`
   - la ruta global de skills de Antigravity (verificar en la versión instalada; candidata: `~/.gemini/antigravity/skills/`).
3. Crear symlinks de los entrypoints en `~/.local/bin/` (por ejemplo, `th-wt`).
4. Idempotente: nunca sobrescribir algo que no sea un symlink propio del kit.

**`verify.sh`**

- Cada symlink apunta a un destino existente.
- En cada `SKILL.md`, `name` coincide con el nombre de la carpeta.
- Las dependencias requeridas están instaladas.
- Código de salida distinto de `0` si algo falla.

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
    "ask": ["command(regex:.*th-wt close.*--yes.*)"]
  }
}
```

⚠️ Verificar la sintaxis de los patrones en las versiones instaladas antes de confiar en ellos.

---

## 14. CI (`.github/workflows/ci.yml`)

Matriz: `macos-latest` y `ubuntu-latest`.

1. **ShellCheck** sobre todos los scripts.
2. **`tests/lint-skills.sh`:**
   - `name` en el frontmatter igual al nombre de la carpeta.
   - Ninguna ruta `scripts/` sin el prefijo `${CLAUDE_SKILL_DIR`.
3. **`tests/smoke.sh`:** crea un repo temporal con un remote local (`git init --bare` como `origin`) y ejecuta `new` → `list` → `close` (dry-run) → `close --yes`. No requiere `gh`.

---

## 15. Definition of Done — v0.1

- [ ] `th-worktree` crea worktrees para una rama nueva, para una rama existente y para un PR.
- [ ] Al crear: aplica el `.conf` del repo (enlaza `.wiki`), instala dependencias e inicializa codegraph si está disponible.
- [ ] Al cerrar: dry-run por defecto; con `--yes` ejecuta `codegraph uninit`, elimina el worktree y borra la rama si está mergeada.
- [ ] Funciona invocado desde Claude Code y desde Antigravity en macOS.
- [ ] `git status` limpio en un worktree del repo del trabajo (la `.wiki` enlazada no aparece).
- [ ] CI en verde en macOS y Ubuntu.
- [ ] README con instalación en tres pasos y dependencias declaradas.

Cuando todo esté marcado: tag `v0.1`, usarlo una semana y anotar lo que moleste. **Esa lista define la v0.2.**

---

## 16. Hoja de ruta

| Versión | Contenido |
|---|---|
| **v0.1** | `th-worktree` + instalación + CI |
| v0.2 | `th-repo-context`: índice de documentación generado al vuelo (`find -L`, título y primer párrafo por documento) y selección de lo relevante |
| v0.3 | `th-pr-review`: `pr-reviews/pr-<n>/{code,review}`, Stryker limitado a los archivos del diff, salida de tests resumida, comentarios en una sola review vía `gh api` con confirmación |
| v0.4 | `th-integration-context`: documento de contexto entre repos, fuera de los repos |
| Después | Skills de desarrollo, empaquetado como plugin (`th:…`), GitLab |

---

## 17. Por verificar al empezar

- [ ] Ruta global de skills de Antigravity en la versión instalada.
- [x] Que Claude Code sustituya `${CLAUDE_SKILL_DIR}` dentro de la forma `${CLAUDE_SKILL_DIR:-…}`. **No:** la variable no existe en el shell de Bash (2026-10-26). Sin el symlink fijo, Claude improvisó la ruta; con `~/.local/share/th-worktools` presente, la ruta del `SKILL.md` funciona. El fallback fijo es obligatorio en la instalación (`install.sh`, #12).
- [ ] Que Antigravity ejecute los comandos en un shell que expanda `$HOME` y `${…:-…}`.
- [ ] Que las búsquedas del agente sigan el symlink `.wiki`.
- [ ] Cómo está la entrada de `.wiki` en el `.gitignore` del repo del trabajo (con o sin barra).
- [ ] Flags no interactivos de `codegraph init` y comportamiento de `codegraph uninit`.
- [ ] Sintaxis de los patrones de permisos en ambos agentes.
- [ ] Cómo recibe argumentos un skill en Antigravity.

---

## 18. Base para `AGENTS.md`

```markdown
# th-worktools — instrucciones para agentes

- Antes de cambiar algo, lee `docs/plan-v0.1.md`. Las decisiones están ahí; no las reabras sin preguntar.
- Scripts en bash compatible con 3.2 y portables entre macOS y Linux (§6 del plan).
- Antes de dar algo por terminado: `shellcheck` sobre los scripts, `tests/lint-skills.sh` y `tests/smoke.sh`.
- Nunca agregues datos reales del trabajo (organizaciones, repos, rutas, tickets). El repo es público.
- Alcance: solo lo que pide el DoD de la versión vigente. Las ideas nuevas van a la sección "Ideas" del README, no al código.
- Rutas a scripts en SKILL.md: siempre con `${CLAUDE_SKILL_DIR:-…}`, nunca relativas a secas.
```
