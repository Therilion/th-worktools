# Referencia de `th-wt` (`th-worktree`)

`th-wt` (`skills/th-worktree/scripts/th-wt`) es el script del skill `th-worktree`. Crea, abre (también un PR de GitHub), lista y cierra git worktrees del repositorio actual sin modificar el checkout principal.

> **Estado en v0.1:** están implementados `new`, `checkout`, `pr`, `list` y `close`. También instalan las dependencias según el lockfile (#6). Quedan pendientes los enlaces y copias por repo `.conf` (#7), la configuración y raíz configurable (#8), la integración con `codegraph` (#9), el enlace de `th-wt` en `PATH` (#11) y `install.sh` / `verify.sh` (#12, #13). Hoy el script se invoca con su ruta completa: `"${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt"`.

---

## 1. Qué es y dónde vive cada cosa

### Layout en disco

Todos los worktrees se crean bajo una raíz fija en el directorio del usuario:

```text
~/.worktrees/<owner>/<repo>/<rama-normalizada>
```

- **`<rama-normalizada>`:** cada `/` del nombre de la rama se reemplaza por `-` en el nombre del directorio (`feature/login` → `feature-login`). La rama de git conserva su nombre original (`feature/login`).
- **PRs (`pr`):** `~/.worktrees/<owner>/<repo>/pr-reviews/pr-<n>/code`, en la rama local `review/pr-<n>`. Los demás archivos de `pr-reviews/pr-<n>/` (por ejemplo `report.md`) son tuyos: `pr` y `close` no los tocan. `pr-reviews` es un nombre reservado: `new` y `checkout` rechazan con código `2` una rama cuyo nombre normalizado sea `pr-reviews` (`pr-reviews`, `pr/reviews`).
- **Checkout principal intacto:** `th-wt` no cambia la rama activa, el índice ni los archivos versionados del checkout principal. Dentro de `.git` solo modifica los metadatos propios de git: el registro de worktrees, las ramas locales (`refs/heads/<rama>`), la sección `branch.<rama>` en `.git/config` y las refs remotas `refs/remotes/origin/<rama>` al hacer fetch.

### Cómo se deriva `<owner>/<repo>` de `origin`

`th-wt` lee `remote.origin.url` con `git config --get remote.origin.url`. Solo acepta los formatos `git@<host>:<ruta>` y `https://<host>/<ruta>` (o `http://`), y extrae `<owner>/<repo>` quitando el prefijo del host y el sufijo opcional `.git`:

| Formato de `remote.origin.url` | `<owner>/<repo>` resultante |
|---|---|
| `git@github.com:acme/demo.git` | `acme/demo` |
| `git@github-work:acme/demo` (alias SSH) | `acme/demo` |
| `https://github.com/acme/demo.git` | `acme/demo` |
| `https://github.com/acme/demo` | `acme/demo` |
| `git@gitlab.com:group/sub/repo.git` (subgrupos) | `group/sub/repo` |

Si no se está en un repositorio git, si no existe el remote `origin` o si la URL tiene cualquier otro formato (`ssh://...`, puerto explícito, barra final `https://host/acme/demo/`, rutas locales, segmentos `.` o `..`, o menos de dos segmentos), el comando aborta con código `4`.

### Ejecución desde el checkout principal o desde un worktree

`th-wt` se puede ejecutar indistintamente desde el checkout principal o desde dentro de cualquier worktree existente del repositorio: `remote.origin.url` y el registro de worktrees son compartidos por git. La única excepción es `close --yes`, que rechaza cerrar el worktree desde el que se está ejecutando (código `4`).

### Límites conocidos

Los siguientes casos están documentados en la sección «Ideas» del `README.md` y aún no se tratan en el código:

- **Colisión de nombres normalizados:** dos ramas distintas con el mismo nombre al reemplazar `/` por `-` (por ejemplo, `feature/a-b` y `feature-a/b` → `feature-a-b`) apuntan al mismo directorio. La segunda falla con código `4` (`destination already exists`) sin indicar qué rama ocupa esa ruta.
- **Rama local `review`:** una rama llamada `review` impide crear `review/pr-<n>` (git no admite las dos); `pr` sale con `1` y el error de git.
- **Raíz fija:** la raíz es siempre `$HOME/.worktrees`; la configuración mediante `TH_WORKTREES_ROOT` y `~/.config/th-worktools/config` está pendiente (#8).
- **Symlinks y capitalización en la raíz:** `list` y `close` comparan el prefijo `$HOME/.worktrees/<owner>/<repo>/` literalmente con las rutas que devuelve `git worktree list --porcelain` (donde git resuelve symlinks). Si `$HOME` o `~/.worktrees` son symlinks, si `$HOME` termina en `/` o si cambia la capitalización de la URL de `origin` en un sistema de archivos insensible a mayúsculas (como APFS), `list` devuelve la lista vacía y `close` sale con `4` (`no worktree for branch`).

---

## 2. Subcomandos disponibles

Sintaxis exacta según `th-wt --help`:

```text
Usage: th-wt new <branch> [--base <branch>] [--json]
       th-wt checkout <branch> [--remote] [--json]
       th-wt list [--remote] [--json]
       th-wt pr <n> [--json]
       th-wt close <branch> [--remote] [--yes] [--force] [--json]
       th-wt [new|checkout|list|pr|close] -h | --help
```

- `-h` y `--help` (en `th-wt` o en cualquier subcomando) imprimen la ayuda en stdout y salen con `0`.

### `new`

```text
th-wt new <branch> [--base <branch>] [--json]
```

Crea un worktree en `~/.worktrees/<owner>/<repo>/<rama-normalizada>` con una rama nueva `<branch>` creada a partir de `origin/<base>` (por defecto, la rama por defecto de `origin`). `<branch>` debe ir como primer argumento, antes de las opciones.

La rama nueva se crea con `--no-track` para que no siga a `origin/<base>` como upstream. Sin `--json`, `new` no imprime nada en caso de éxito (salvo lo que escriba el gestor de paquetes, ver «Instalación de dependencias»).

**Flags:**

| Flag | Efecto |
|---|---|
| `--base <branch>` | Crea la rama desde `origin/<branch>` en lugar de la rama por defecto de `origin`. Debe ser un nombre de rama válido en `origin` (sin el prefijo `origin/`, tags, SHAs ni expresiones como `main~1`). |
| `--json` | Escribe en stdout un objeto JSON con `path`, `branch`, `repo` y `deps`. |

**Ejemplos:**

```bash
# Crear feature/login desde la rama por defecto de origin
th-wt new feature/login

# Crear fix/token desde origin/release/1.2 con salida JSON
th-wt new fix/token --base release/1.2 --json
```

**Errores relevantes:**

- Falta `<branch>`, una opción aparece antes de `<branch>`, `--base` no recibe valor, hay opciones o argumentos desconocidos, `<branch>` es `HEAD`, o `<branch>` / `--base` no son nombres de rama válidos (`git check-ref-format`) → código `2` (sin tocar la red).
- El directorio destino ya existe en disco → código `4` (`destination already exists: <ruta>`).
- La rama ya existe en local o en `origin` → código `4` (`branch already exists: <branch>`).
- `origin` es inaccesible → código `4` (`cannot read origin (unreachable or no access)`).
- `origin` no tiene `HEAD` simbólico y no se indicó `--base` → código `4` (`cannot determine origin's default branch (pass --base)`).
- La rama `--base` no existe en `origin` o falla el `git fetch` → código `4` (`base branch not found on origin (or fetch failed): <base>`).
- Falla `git worktree add` (por ejemplo, conflicto de jerarquía de refs como crear `conf` cuando ya existe `conf/x`, o falta de permisos en disco) → código `1` (`git worktree add failed`).

---

### `checkout`

```text
th-wt checkout <branch> [--remote] [--json]
```

Crea un worktree en `~/.worktrees/<owner>/<repo>/<rama-normalizada>` para una rama existente. `<branch>` debe ir como primer argumento.

- **Si `<branch>` ya existe como rama local (`refs/heads/<branch>`):** abre el worktree directamente en ese commit local, sin mover la rama y sin usar la red salvo para instalar las dependencias (ver «Instalación de dependencias») (aunque se pase `--remote` y `origin/<branch>` haya avanzado).
- **Si `<branch>` no existe en local:** busca `refs/remotes/origin/<branch>` (con `--remote`, antes verifica que exista en `origin` y hace fetch de esa rama). Crea la rama local en ese commit y configura su upstream a `origin/<branch>` (`branch.<branch>.remote = origin` y `branch.<branch>.merge = refs/heads/<branch>`).

Sin `--json`, `checkout` no imprime nada en caso de éxito.

**Flags:**

| Flag | Efecto |
|---|---|
| `--remote` | Si la rama no existe en local, la consulta y descarga de `origin` antes de crear el worktree. Si la rama ya existe en local, no tiene efecto. |
| `--json` | Escribe en stdout un objeto JSON con `path`, `branch`, `repo` y `deps`. |

**Ejemplos:**

```bash
# Abrir una rama que ya existe en local (o cuya ref origin/<rama> ya fue traída)
th-wt checkout feature/login

# Traer de origin una rama remota que aún no existe en local
th-wt checkout feature/remote-work --remote --json
```

**Errores relevantes:**

- Falta `<branch>`, una opción va antes de `<branch>`, hay opciones o argumentos desconocidos, o `<branch>` es `HEAD` / inválido → código `2`.
- El directorio destino ya existe → código `4` (`destination already exists: <ruta>`, se comprueba antes de usar la red).
- La rama ya está abierta en el checkout principal o en otro worktree → código `4` (`branch <branch> is already checked out in <ruta>`).
- Sin `--remote`, la rama no existe ni en `refs/heads/<branch>` ni en `refs/remotes/origin/<branch>` → código `4` (`branch not found: <branch> (try --remote)`).
- Con `--remote` (cuando la rama no es local): `origin` inaccesible (`cannot read origin`), la rama no existe en `origin` (`branch not found on origin: <branch>`) o falla el fetch (`fetch of origin/<branch> failed`) → código `4`.
- Falla `git worktree add` → código `1` (`git worktree add failed`). Si se había creado la rama local a partir de `origin/<branch>`, se revierte (`git branch -D`) para no dejar una rama local sin upstream.

---

### `pr`

```text
th-wt pr <n> [--json]
```

Abre el PR `<n>` de GitHub del repo (también uno abierto desde un fork) en `~/.worktrees/<owner>/<repo>/pr-reviews/pr-<n>/code`, en una rama local `review/pr-<n>` con el último commit del PR y sin upstream. Actualiza `origin/<base>` para poder ver el diff. No toca el checkout principal ni tus ramas.

**Orden de las comprobaciones:** primero las locales (sin red): `<n>` entero positivo sin ceros a la izquierda (código `2`), la ruta `pr-reviews/pr-<n>/code` libre y la rama `review/pr-<n>` inexistente (código `4`) y `gh` instalado (código `3`). Luego la red: `gh pr view`, `git fetch origin refs/pull/<n>/head` (solo `FETCH_HEAD`, no escribe refs) y el fetch de `origin/<base>`. El commit traído debe coincidir con el `headRefOid` que informa `gh` (`FETCH_HEAD` es estado compartido y el PR puede recibir un push entre las dos llamadas); si no, sale con `4` y conviene repetir. Si algo falla no se crea nada.

Si `pr-reviews/pr-<n>/` ya existe con otros archivos (por ejemplo `report.md`) pero sin `code`, se abre igual.

**Dependencias:** tras crear el worktree instala las dependencias como `new`, pero **sin ejecutar código del repo** (`pnpm install --frozen-lockfile --ignore-scripts --ignore-pnpmfile` / `npm ci --ignore-scripts`: ni scripts de ciclo de vida ni `.pnpmfile.cjs`), porque el PR puede ser código de un tercero. Los paquetes que necesitan `postinstall` (por ejemplo `esbuild` o binarios nativos) pueden no funcionar; si confías en el PR, repite la instalación a mano en el worktree.

**Salida:** con `--json`, el objeto de `new` más `pr`; sin `--json`, ruta, PR (número y título), rama del PR y base por stderr, con los caracteres de control del título y de las ramas (que escribe el autor del PR) sustituidos por espacios. Para actualizar un worktree de PR cuando recibe commits nuevos, ciérralo y vuelve a abrirlo.

**Errores relevantes:**

- `<n>` ausente o que no es un entero positivo → código `2`.
- Falta `gh` → código `3` (`missing dependency: gh`).
- La ruta o la rama ya existen → código `4` (`destination already exists` / `branch already exists`).
- `gh pr view` falla (PR inexistente, sin autenticar o sin acceso) o devuelve algo inesperado, `origin` inaccesible, el PR sin `refs/pull/<n>/head` la base ausente de `origin` o un commit traído distinto del `headRefOid` de `gh` → código `4`.

---

### `list`

```text
th-wt list [--remote] [--json]
```

Lista los worktrees del repositorio actual ubicados bajo `~/.worktrees/<owner>/<repo>/` (omite el checkout principal y cualquier worktree fuera de esa raíz).

Para cada worktree informa la rama (o `(detached)`), si el directorio falta (`missing`), si tiene cambios locales (`dirty`, comprobado con `git --no-optional-locks status --porcelain --untracked-files=normal` para no bloquear ni modificar el índice) y si está contenida en la rama por defecto de `origin` (`merged`). Sin `--json`, toda la salida de texto va a **stderr**; si no hay worktrees bajo la raíz, imprime `no worktrees under ~/.worktrees/<owner>/<repo>/`.

**Flags:**

| Flag | Efecto |
|---|---|
| `--remote` | Consulta en `origin` cuál es la rama por defecto, hace fetch de `refs/remotes/origin/<default>` (sin tocar `origin/HEAD`) y consulta los 100 PRs más recientes en GitHub con `gh pr list`. Añade a cada worktree la información de su PR (`pr`). |
| `--json` | Escribe en stdout un único objeto `{repo, worktrees}`. |

Con `--remote`, si `gh` devuelve 100 PRs (el límite de la consulta) y queda alguna rama no contenida sin PR asociado, `list` emite un aviso en stderr:
`th-wt: only the 100 most recent PRs were checked; branches without a PR here may have an older one`.

**Ejemplos:**

```bash
# Listar worktrees con datos locales (offline)
th-wt list

# Listar worktrees actualizando origin/<default> y cruzando con PRs de GitHub en JSON
th-wt list --remote --json
```

**Errores relevantes:**

- Opción o argumento desconocido → código `2`.
- Con `--remote` y sin `gh` en `PATH` → código `3` (`missing dependency: gh`).
- Con `--remote`: `origin` inaccesible (`cannot read origin`), `origin` sin rama por defecto (`cannot determine origin's default branch`), fallo del fetch (`fetch of origin/<base> failed`), fallo de `gh pr list` (`gh pr list failed ...`) o respuesta de `gh` que no sea un array JSON de objetos (`unexpected output from gh pr list`) → código `4` (no hay fallback a lista local).

---

### `close`

```text
th-wt close <branch> [--remote] [--yes] [--force] [--json]
```

Muestra el plan de cierre (dry-run por defecto) o cierra (con `--yes`) el worktree de `<branch>` bajo `~/.worktrees/<owner>/<repo>/`, y borra la rama local si su trabajo ya está integrado.

**Reglas de bloqueo y borrado de rama:**

1. **Bloqueo del worktree (`delete.worktree = false`):** sin `--force`, el cierre se bloquea si el worktree tiene cambios sin commitear (`dirty: true`), si `git status` falla existiendo el directorio (`dirty: null` con `missing: false`), o si la rama tiene commits que no están en ninguna ref `refs/remotes/origin/*` (`unpushed > 0`) y no están cubiertos por un PR mergeado.
2. **Borrado de la rama (`delete.branch = true`):** cuando el worktree se puede borrar, la rama también se borra si está contenida en la rama por defecto (`merged: true`) o cubierta por un PR mergeado (`--remote` con `pr.state == "MERGED"` y `pr.ahead == false`), siempre que no sea la rama por defecto de `origin` y no esté abierta en otro worktree. En cualquier otro caso, se elimina el directorio del worktree pero se conserva la rama local e informa el motivo (`kept`).
3. **Borrado seguro del ref:** `close --yes` lee el OID de `refs/heads/<branch>` al empezar y borra la rama con `git update-ref -d refs/heads/<branch> <oid>` (limpiando también la sección `branch.<branch>` en git config). Si la rama recibió un commit nuevo mientras corría `close`, `update-ref` falla, la rama se conserva con el commit intacto y el comando termina con `0` avisando `kept: it moved while closing`.
4. **Archivos ignorados (`ignored`):** el plan lista los nombres de archivos y directorios ignorados por git en el worktree (con directorios colapsados como `build/`, sin mostrar nunca su contenido). Se eliminan con el directorio del worktree y nunca bloquean el cierre.

**Worktrees de PR (`pr-reviews/pr-<n>/code`):** `close review/pr-<n>` aplica reglas propias. Un worktree es de PR si su rama es `review/pr-<n>` y está en `pr-reviews/pr-<n>/code` con la misma `<n>`; cualquier otra combinación (una rama `review/…` creada con `new`, o otra rama activada dentro de `pr-reviews/pr-<n>/code`) se cierra con las reglas normales.

- La rama `review/pr-<n>` se borra (es solo una copia local del PR): no se mira `merged` ni `unpushed`. El plan lo dice. Excepción: con `--force` y `after_pr` distinto de `0` (o `null`) se cierra el worktree pero se conserva la rama, porque puede tener commits tuyos que nada más contiene (`kept: it may have commits of yours after the PR`). Bórrala tú con `git branch -D review/pr-<n>`; mientras exista, `pr <n>` sale con `4`.
- Bloquean sin `--force`: cambios sin commitear (`dirty`) y commits tuyos posteriores al PR (`after_pr > 0`). Se cuentan desde la creación de la rama (primera entrada de su reflog), sin los que ya están en alguna rama de `origin` (un merge de la base dentro del worktree solo cuenta tu commit de merge; lo que pusheaste deja de contar). Los commits que traigas a mano (por ejemplo las novedades de un PR de fork con `git pull origin pull/<n>/head`) nunca llegan a `origin/*` y cuentan como tuyos: el cierre se bloquea y hace falta `--force`, que en ese caso conserva la rama; sin reflog, o si la primera entrada ya no es la de creación, `after_pr` es `null` y también bloquea. En vez de `unpushed`, el plan muestra esos commits (hasta 10).
- Tras `git worktree remove` se borra `pr-reviews/pr-<n>/` solo si quedó vacío (`rmdir`, nunca `rm -r`). El plan y el `--json` listan en `kept` los nombres que se conservan.

**Flags:**

| Flag | Efecto |
|---|---|
| `--remote` | Actualiza `origin/<default>` y consulta con `gh` los PRs de `<branch>` (hasta 1000). Si el PR más reciente del mismo repo está `MERGED` y `ahead: false`, los commits sin push cuentan como integrados en el PR (no bloquean) y la rama se borra al cerrar. |
| `--yes` | Ejecuta el cierre. Sin `--yes`, `close` actúa en modo dry-run: no modifica nada y sale con `0`. |
| `--force` | Permite cerrar aunque haya cambios sin commitear, commits sin push o estado de git ilegible, y pasa `--force` a `git worktree remove`. La rama no integrada se sigue conservando; los cambios sin commitear y archivos ignorados del directorio se pierden. |
| `--json` | Escribe en stdout un objeto JSON con el estado y lo que se borra (o se borraría). |

**Ejemplos:**

```bash
# Ver el plan de cierre sin borrar nada (dry-run)
th-wt close feature/login

# Ejecutar el cierre tras revisar el plan
th-wt close feature/login --yes

# Cerrar una rama integrada mediante squash merge en GitHub
th-wt close feature/squash --remote --yes

# Forzar el cierre descartando cambios sin commitear o commits sin push
th-wt close feature/wip --yes --force
```

**Errores relevantes:**

- Falta `<branch>`, se pasa más de una rama, opción desconocida o nombre de rama inválido → código `2`.
- Con `--remote` y sin `gh` en `PATH` → código `3` (`missing dependency: gh`).
- La rama no existe, es huérfana sin commits, tiene el `HEAD` desacoplado o su worktree no está bajo `~/.worktrees/<owner>/<repo>/` → código `4` (`no worktree for branch <branch> under <root>`).
- Con `--remote`: errores de acceso a `origin` o a `gh` (mismas causas que `list --remote`) → código `4` (sin borrar nada).
- Con `--yes` ejecutado desde dentro del directorio del worktree a cerrar (o un subdirectorio suyo) → código `4` (`cannot close <path> from inside it: run close from another directory`).
- Con `--yes` y sin `--force` cuando el cierre está bloqueado (`dirty: true`, `unpushed > 0` no cubiertos, o `git status` ilegible) → código `4` (`<motivo> (use --force to close anyway)`).
- Con `--yes` cuando `git worktree remove` falla (por ejemplo, worktree bloqueado con `git worktree lock` o con submódulos) → código `4` (`git could not remove <path> (see git's message above)`).

---

## 3. Red

El acceso a la red es explícito:

| Subcomando | ¿Cuándo usa la red? | Operaciones de red | ¿Requiere `gh`? |
|---|---|---|---|
| `new` | **Siempre** | `git ls-remote --symref origin HEAD`, `git ls-remote --heads origin refs/heads/<branch>` y `git fetch -q --no-tags origin +refs/heads/<base>:refs/remotes/origin/<base>` | No |
| `checkout` | **Solo con `--remote`** y solo si la rama no existe en local (`refs/heads/<branch>`) | `git ls-remote --heads origin refs/heads/<branch>` y `git fetch -q --no-tags origin +refs/heads/<branch>:refs/remotes/origin/<branch>` | No |
| `list` | **Solo con `--remote`** | `git ls-remote --symref origin HEAD`, `git fetch -q --no-tags origin +refs/heads/<default>:refs/remotes/origin/<default>` y `gh pr list -R <owner>/<repo> --state all --limit 100 ...` | Sí (con `--remote`) |
| `pr` | **Siempre** | `gh pr view <n> -R <owner>/<repo> --json number,title,headRefName,baseRefName,headRefOid`, `git fetch -q --no-tags origin refs/pull/<n>/head` y `git fetch -q --no-tags origin +refs/heads/<base>:refs/remotes/origin/<base>` | Sí |
| `close` | **Solo con `--remote`** | Igual que `list --remote`, pero filtrando en `gh pr list` con `--limit 1000 --head <branch>` | Sí (con `--remote`) |

### Instalación de dependencias

`new`, `checkout` y `pr` instalan las dependencias del worktree con `pnpm` o `npm`, que usan la red (registro de paquetes) aunque el subcomando no la use por otra vía. Es la única red que usa `checkout` sin `--remote`. Estas llamadas no escriben ninguna ref de git.

### Refs que escribe

- Todos los `fetch` usan `--no-tags` y, salvo el del PR, el refspec explícito `+refs/heads/<rama>:refs/remotes/origin/<rama>`. El fetch de `pr` a `refs/pull/<n>/head` solo escribe `FETCH_HEAD`.
- Aparte de `FETCH_HEAD` (contabilidad propia de git), la única ref escrita fuera del worktree es `refs/remotes/origin/<rama>` de la rama consultada (`<base>` en `new` y en `pr`, `<branch>` en `checkout --remote`, o la rama por defecto de `origin` en `list --remote` y `close --remote`).
- No descarga tags del remoto al repositorio local.
- **Nunca crea ni modifica `refs/remotes/origin/HEAD`**, ni siquiera cuando no existe en local o apunta a otra rama.

### `GIT_TERMINAL_PROMPT=0`

`th-wt` exporta `GIT_TERMINAL_PROMPT=0` al iniciar, antes de ejecutar cualquier comando `git`. Si `origin` requiere credenciales interactivas en la terminal, `git` falla de inmediato (y `th-wt` sale con código `4`) en lugar de quedar esperando entrada en una sesión sin TTY.

### Requisitos de `gh` en `pr`, `list --remote` y `close --remote`

- `gh` debe estar instalado (si falta, código `3`) y autenticado con acceso de lectura a `<owner>/<repo>` (si falla la autenticación o la red, código `4`).
- `th-wt` pasa siempre `-R <owner>/<repo>` sin host: `gh` consulta `github.com` por defecto, o el servidor definido en la variable de entorno `GH_HOST` (GitHub Enterprise).
- Solo se consideran PRs del mismo repositorio (`isCrossRepository: false`); los PRs abiertos desde forks con el mismo nombre de rama se ignoran.

---

## 4. Códigos de salida

| Código | Significado | Causas típicas por subcomando |
|---|---|---|
| `0` | OK | **Todos:** `-h` / `--help`.<br>**`new` / `checkout` / `pr`:** worktree creado.<br>**`list`:** listado completado (haya o no worktrees).<br>**`close`:** plan mostrado (sin `--yes`, incluso si está bloqueado) o worktree eliminado (con `--yes`, se haya borrado o conservado la rama). |
| `1` | Error de ejecución | **`new` / `checkout`:** falla `git worktree add` tras superar las validaciones previas (conflicto de refs como `conf` con `conf/x`, permisos de escritura en `~/.worktrees`, o rama en rebase/bisect en otro worktree con HEAD `detached`). |
| `2` | Uso incorrecto | **Todos:** sin subcomando, subcomando desconocido, opción desconocida o argumento posicional inesperado.<br>**`new`:** falta `<branch>`, opción antes de `<branch>`, `--base` vacío o sin argumento, `<branch>` es `HEAD` o formato inválido de `<branch>` / `--base` (p. ej. `main~1`, `bad..name`).<br>**`checkout`:** falta `<branch>`, opción antes de `<branch>`, `<branch>` es `HEAD` o formato de rama inválido.<br>**`new` / `checkout`:** además, una rama cuyo nombre normalizado es `pr-reviews`.<br>**`pr`:** `<n>` ausente o que no es un entero positivo sin ceros a la izquierda.<br>**`close`:** falta `<branch>`, más de un argumento posicional o formato de rama inválido. |
| `3` | Dependencia faltante | **Todos:** falta `git` o `jq` en `PATH`.<br>**`pr` / `list --remote` / `close --remote`:** falta `gh` en `PATH`. |
| `4` | Precondición no cumplida | **Todos:** fuera de un repositorio git, sin remote `origin` o URL de `origin` con formato no soportado.<br>**`new`:** destino ya existente, la rama ya existe en local o en `origin`, `origin` inaccesible, `origin` sin rama por defecto (sin `--base`), o `--base` no existe en `origin` / falla el fetch.<br>**`checkout`:** destino ya existente, rama ya abierta en el checkout principal o en otro worktree, rama inexistente en local y en `refs/remotes/origin/<branch>` (sin `--remote`), o con `--remote` `origin` inaccesible / rama inexistente en `origin` / fallo de fetch.<br>**`pr`:** la ruta `pr-reviews/pr-<n>/code` o la rama `review/pr-<n>` ya existen, `gh pr view` falla o devuelve algo inesperado, o falla un fetch de `origin` (PR sin `refs/pull/<n>/head`, `origin` inaccesible, base ausente), o el commit traído no es el `headRefOid` de `gh`.<br>**`list --remote`:** `origin` inaccesible, `origin` sin rama por defecto, fallo del fetch, fallo de `gh pr list` (sin autenticar o sin acceso) o salida JSON inesperada de `gh`.<br>**`close`:** la rama no tiene worktree bajo `~/.worktrees/<owner>/<repo>/` (o no existe / es huérfana / está en `detached`), errores de `--remote` (igual que `list --remote`), o con `--yes`: ejecutado desde dentro del worktree a cerrar, bloqueado por cambios sin commitear / commits sin push (en un worktree de PR, commits propios posteriores al PR o desconocidos) / `git status` ilegible (sin `--force`), o fallo de `git worktree remove` (p. ej. worktree bloqueado con `git worktree lock`). |

---

## 5. Salida `--json`

Con `--json`, todos los subcomandos escriben un único objeto JSON en **stdout** (generado con `jq`). Los avisos y errores siguen saliendo por **stderr**.

### `new --json` y `checkout --json`

Devuelven el mismo esquema:

| Campo | Tipo | Descripción |
|---|---|---|
| `path` | `string` | Ruta absoluta del worktree creado (`~/.worktrees/<owner>/<repo>/<rama-normalizada>`). |
| `branch` | `string` | Nombre real de la rama en git. |
| `repo` | `string` | `<owner>/<repo>` derivado de `origin`. |
| `deps` | `string` | Resultado de la instalación de dependencias: `"pnpm"`, `"npm"` (instaladas), `"skipped"` (sin lockfile, o el gestor no está en `PATH`) o `"failed"` (el gestor salió con error). |

```json
{
  "path": "/Users/alice/.worktrees/acme/demo/feature-login",
  "branch": "feature/login",
  "repo": "acme/demo",
  "deps": "pnpm"
}
```

#### Instalación de dependencias

Tras crear el worktree, `th-wt` busca un lockfile en su raíz (si hay `pnpm-lock.yaml` y `package-lock.json`, gana pnpm):

| Lockfile | Comando (en `new` y `checkout`) | En `pr` |
|---|---|---|
| `pnpm-lock.yaml` | `pnpm install --frozen-lockfile` | con `--ignore-scripts --ignore-pnpmfile` |
| `package-lock.json` | `npm ci` | con `--ignore-scripts` |
| otro / ninguno | no se instala (`deps: "skipped"`) | igual |

- El gestor se ejecuta con el worktree como directorio de trabajo, con su salida redirigida a **stderr** (stdout queda para el objeto `--json`) y con stdin cerrado (`/dev/null`), así que nunca espera una respuesta.
- Si el gestor sale con error, `th-wt` conserva el worktree, avisa por stderr y sale con `0`; `deps` vale `"failed"`. Se puede repetir la instalación a mano en el worktree.
- Si hay lockfile pero `pnpm` / `npm` no está en `PATH`, avisa por stderr, no instala y sale con `0`; `deps` vale `"skipped"`.
- Sin `--json`, el gestor escribe igualmente en stderr.

### `pr --json`

El objeto de `new --json` más `pr`:

| Campo | Tipo | Descripción |
|---|---|---|
| `path` | `string` | `~/.worktrees/<owner>/<repo>/pr-reviews/pr-<n>/code`. |
| `branch` | `string` | `review/pr-<n>`. |
| `repo` | `string` | `<owner>/<repo>` derivado de `origin`. |
| `deps` | `string` | Igual que en `new --json` (en `pr`, instalado sin scripts). |
| `pr` | `object` | `{number, title, head, base}`: número, título, rama del PR (`head`) y su base. |

### `list --json` y `list --remote --json`

Devuelven un objeto con `repo` (`string`) y `worktrees` (`array` de objetos; `[]` si no hay worktrees bajo la raíz).

| Campo en `worktrees[]` | Tipo | Descripción |
|---|---|---|
| `path` | `string` | Ruta absoluta del worktree. |
| `branch` | `string \| null` | Nombre de la rama local, o `null` si el `HEAD` está desacoplado. |
| `dirty` | `boolean \| null` | `true` si hay cambios en archivos seguidos o archivos sin seguimiento; `false` si está limpio (los ignorados no cuentan); `null` si no se pudo leer. |
| `merged` | `boolean \| null` | `true` si la rama (o `HEAD`) es ancestro de `origin/<default>`; `false` si no lo es; `null` si no se pudo determinar. |
| `missing` | `boolean` | `true` si el directorio del worktree ya no existe en disco; `false` si existe. |
| `pr` | `object \| null` | **Solo presente con `--remote`.** Objeto `{number, state, base, ahead}` del PR más reciente del mismo repo para esa rama, o `null`. |

Campos dentro de `pr` (cuando no es `null`):

| Campo en `pr` | Tipo | Descripción |
|---|---|---|
| `number` | `number` | Número del PR en GitHub. |
| `state` | `string` | Estado del PR: `"OPEN"`, `"CLOSED"` o `"MERGED"`. |
| `base` | `string` | Rama base del PR (`baseRefName`, p. ej. `"main"` o `"release/1.0"`). |
| `ahead` | `boolean \| null` | `false` si el commit local es ancestro del último commit del PR (`headRefOid`); `true` si hay commits locales posteriores al PR; `null` si el commit del PR no está en local o no vino en la respuesta. |

**Ejemplo de `list --json` (sin `--remote`):**

```json
{
  "repo": "acme/demo",
  "worktrees": [
    {
      "path": "/Users/alice/.worktrees/acme/demo/feature-login",
      "branch": "feature/login",
      "dirty": false,
      "merged": false,
      "missing": false
    }
  ]
}
```

**Ejemplo de `list --remote --json`:**

```json
{
  "repo": "acme/demo",
  "worktrees": [
    {
      "path": "/Users/alice/.worktrees/acme/demo/feature-login",
      "branch": "feature/login",
      "dirty": false,
      "merged": false,
      "missing": false,
      "pr": {
        "number": 42,
        "state": "MERGED",
        "base": "main",
        "ahead": false
      }
    }
  ]
}
```

### `close --json` y `close --remote --json`

Devuelven el mismo esquema en dry-run (sin `--yes`) y al ejecutar (con `--yes`):

| Campo | Tipo | Descripción |
|---|---|---|
| `path` | `string` | Ruta absoluta del worktree. |
| `branch` | `string` | Nombre de la rama. |
| `merged` | `boolean \| null` | Igual que en `list`. |
| `dirty` | `boolean \| null` | Igual que en `list`. |
| `missing` | `boolean` | Igual que en `list`. |
| `ignored` | `string[] \| null` | Nombres de archivos y directorios ignorados por git en el worktree (directorios colapsados con `/` final); `[]` si no hay ninguno o si `missing` es `true`; `null` si falló `git status`. |
| `unpushed` | `number` | Cantidad de commits de la rama que no están en ninguna ref `refs/remotes/origin/*`. |
| `delete.worktree` | `boolean` | `true` si el worktree se borra (o se puede borrar); `false` si está bloqueado en el dry-run. |
| `delete.branch` | `boolean` | `true` si la rama se borra (o se borraría); `false` si se conserva. |
| `pr` | `object \| null` | **Solo presente con `--remote`.** Mismo formato `{number, state, base, ahead}` que en `list --remote`, o `null`. |

**Ejemplo de `close --json` (sin `--remote`):**

```json
{
  "path": "/Users/alice/.worktrees/acme/demo/feature-login",
  "branch": "feature/login",
  "merged": true,
  "dirty": false,
  "missing": false,
  "ignored": [
    ".env",
    "build/"
  ],
  "unpushed": 0,
  "delete": {
    "worktree": true,
    "branch": true
  }
}
```

**Ejemplo de `close --remote --json`:**

```json
{
  "path": "/Users/alice/.worktrees/acme/demo/feature-login",
  "branch": "feature/login",
  "merged": false,
  "dirty": false,
  "missing": false,
  "ignored": [],
  "unpushed": 2,
  "delete": {
    "worktree": true,
    "branch": true
  },
  "pr": {
    "number": 42,
    "state": "MERGED",
    "base": "main",
    "ahead": false
  }
}
```

**En un worktree de PR** (`pr-reviews/pr-<n>/code`), `unpushed` no aparece y se añaden:

| Campo | Tipo | Descripción |
|---|---|---|
| `after_pr` | `integer \| null` | Commits tuyos posteriores al PR (desde la creación de la rama) que no están en ninguna rama de `origin`. `null` = no se pudo saber (sin reflog, o expiró la entrada de creación); bloquea sin `--force`. |
| `kept` | `string[]` | Nombres de los archivos de `pr-reviews/pr-<n>/` que se conservan (por ejemplo `["report.md"]`). |

`delete.branch` es `true` si el worktree se puede borrar y `after_pr` es `0`; con `--force` y `after_pr` distinto de `0` (o `null`) es `false`.

### Significado de cada `null` y de `missing`

- **`branch: null`** (en `list`): el worktree tiene el `HEAD` desacoplado (`detached`), por ejemplo tras hacer checkout de un commit o durante un `git rebase` / `git bisect`. En `close` no aparece porque `close` exige un worktree asociado a `<branch>`.
- **`dirty: null`**: no se pudo determinar si el árbol de trabajo está limpio, ya sea porque el directorio no existe (`missing: true`) o porque `git status` falló en ese directorio (por ejemplo, un archivo `.git` dañado). No equivale a limpio: si `missing` es `false`, `dirty: null` bloquea `close --yes` salvo que se use `--force`.
- **`merged: null`**: no se pudo comprobar la contención contra la rama por defecto de `origin`. Ocurre cuando sin `--remote` falta `refs/remotes/origin/HEAD` o apunta a una ref remota inexistente (se corrige con `git remote set-head origin -a`), o cuando la rama es huérfana y no tiene commits. Con `merged: null` (y sin PR mergeado que cubra la rama vía `--remote`), `close` conserva la rama (`delete.branch: false`).
- **`pr: null`** (con `--remote`):
  - Si `merged` es `true` (o `branch` es `null` en `list`): **no se consultó el PR** para esa fila porque la rama ya está contenida en `origin/<default>` (en la salida de texto de `close --remote` se muestra `not checked (already contained in <default>)`).
  - Si `merged` es `false` o `null`: la rama no tiene PR en el mismo repositorio (los PRs desde forks se ignoran), o su PR quedó fuera del límite consultado (`100` más recientes del repo en `list --remote`, `1000` de esa rama en `close --remote`).
- **`pr.ahead: null`** (con `--remote`): existe un PR para la rama, pero no se pudo comprobar si `HEAD` es ancestro de `headRefOid` porque ese commit no está descargado en el repositorio local (por ejemplo, si se actualizó la rama desde GitHub antes del merge) o porque `gh` no devolvió `headRefOid`. Con `ahead: null`, un PR `MERGED` no desbloquea commits sin push ni autoriza borrar la rama en `close --remote`.
- **`after_pr: null`** (en `close` de un worktree de PR): no se pudo contar los commits propios porque la rama no tiene reflog o su primera entrada ya no es la de creación. Bloquea `close --yes` salvo con `--force`.
- **`ignored: null`** (en `close`): el directorio del worktree existe (`missing: false`), pero `git status --ignored` falló y no se pudo obtener la lista de archivos ignorados. Cuando `missing` es `true`, `ignored` vale `[]`, no `null`.
- **`missing`** (`true` / `false`): vale `true` cuando el directorio del worktree bajo `~/.worktrees/<owner>/<repo>/` fue eliminado del disco pero sigue registrado en git. Cuando `missing` es `true`, `dirty` vale `null` e `ignored` vale `[]`; `close --yes` no bloquea por `dirty: null` y limpia el registro del worktree en git (y borra la rama si corresponde).
