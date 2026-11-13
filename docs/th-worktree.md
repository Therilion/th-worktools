# Referencia de `th-wt` (`th-worktree`)

`th-wt` (`skills/th-worktree/scripts/th-wt`) es el script del skill `th-worktree`. Crea, abre (también un PR de GitHub), lista y cierra git worktrees del repositorio actual sin modificar el checkout principal.

> **Estado en v0.1:** están implementados `new`, `checkout`, `pr`, `list` y `close`. `new` y `checkout` también enlazan los archivos ignorados del `.conf` del repo (#7) e instalan las dependencias según el lockfile (#6). La raíz de worktrees y la instalación de dependencias se configuran con un archivo o variables de entorno (#8, ver «Configuración»). Si `codegraph` está instalado, `new`, `checkout` y `pr` indexan el worktree y `close --yes` borra el índice (#9, ver «Configuración» y «Integración con codegraph»). Desde la terminal se puede invocar como `th-wt <subcomando>` si enlazas el script en el `PATH` (#11, ver el README); la ruta completa sigue valiendo: `"$HOME/.local/share/th-worktools/skills/th-worktree/scripts/th-wt"`. `install.sh` instala el kit (#12a) y `verify.sh` comprueba la instalación (#12b); la guía de instalación en tres pasos, con los requisitos y los permisos sugeridos, está en el README (#13).

---

## 1. Qué es y dónde vive cada cosa

### Layout en disco

Todos los worktrees se crean bajo la raíz de worktrees (`~/.worktrees` por defecto; ver «Configuración»):

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
- **Cambio de raíz:** al cambiar `TH_WORKTREES_ROOT`, `list` y `close` solo ven los worktrees de la raíz nueva; los creados bajo la anterior no se mueven ni se encuentran.
- **Capitalización en la raíz:** `list` y `close` comparan el prefijo de la raíz literalmente con las rutas de `git worktree list --porcelain`. Si cambia la capitalización de la URL de `origin` en un sistema de archivos insensible a mayúsculas (como APFS), `list` devuelve la lista vacía y `close` sale con `4` (`no worktree for branch`). Los symlinks en la raíz o en `$HOME` sí se resuelven.

---

### Configuración

`th-wt` lee `${XDG_CONFIG_HOME:-$HOME/.config}/th-worktools/config` (ejemplo en [`examples/config/config`](../examples/config/config)): una línea `CLAVE=valor`, sin `source`; `#` y las líneas vacías se ignoran, se tolera CRLF y, si una clave se repite, gana la última. **Precedencia:** variable de entorno no vacía > archivo > valor por defecto (una variable vacía cuenta como no definida).

| Clave | Por defecto | Efecto |
|---|---|---|
| `TH_WORKTREES_ROOT` | `~/.worktrees` | Raíz de los worktrees. Ruta absoluta o con `~/` al inicio (se expande a `$HOME`); sin segmentos `.`, `..` ni vacíos; una barra final se ignora; no se expanden `$VAR`. Se resuelven los symlinks de la parte que existe |
| `TH_INSTALL_DEPS` | `1` | `0` o `1`. Con `0`, `new` y `checkout` no instalan dependencias (`deps: "skipped"`); `pr` no cambia: nunca instala |
| `TH_CODEGRAPH` | `auto` | `auto` (indexar con `codegraph` si está instalado) u `off`. Afecta a la creación (`new`, `checkout` y `pr`), no a `close` |
| `TH_PR_LIMIT` | `500` | Límite de PRs consultados en `list --remote` (mínimo `100`) |

La configuración se carga al empezar cualquier subcomando, después de parsear sus argumentos (`--help` y los errores de uso, código `2`, no dependen de ella). Si el archivo o el entorno son inválidos, no se crea ni se borra nada y sale con código `4`:

```text
th-wt: <ruta del config>:<línea>: <motivo>
th-wt: <VAR> (environment): <motivo>
```

Motivos: `unknown key: <CLAVE>` (una clave que no está en mayúsculas sale como `invalid key (not shown)`), `expected KEY=value`, `TH_WORKTREES_ROOT must be an absolute path or start with ~/, without '.', '..' or empty segments: <valor>` `TH_INSTALL_DEPS must be 0 or 1: <valor>`, `TH_CODEGRAPH must be auto or off: <valor>`, `TH_PR_LIMIT must be an integer >= 100: <valor>`, `TH_WORKTREES_ROOT must not contain control characters`, `cannot resolve the worktrees root: <ruta>` (p. ej. un symlink roto o un ancestro sin permiso) y `worktrees root <raíz>/<owner>/<repo> overlaps the main checkout <ruta>` (la raíz del repo y el checkout principal no pueden contenerse uno a otro). Todos salen con `4` sin crear ni borrar nada. No hay subcomando para ver la configuración efectiva.

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

La rama nueva se crea con `--no-track` para que no siga a `origin/<base>` como upstream.

**Progreso:** siempre (con o sin `--json`), `new` escribe en stderr una línea justo antes de cada fase, para que se vea qué está haciendo mientras tarda:

| Línea | Cuándo sale |
|---|---|
| `th-wt: fetching origin/<rama>` | antes del fetch de la base (en `checkout`, solo con `--remote`; en `pr`, el de la base) |
| `th-wt: creating worktree <ruta> (branch <rama>)` | antes de `git worktree add` |
| `th-wt: applying repo config <ruta del .conf>` | solo si existe el `.conf` del repo; le siguen las líneas `th-wt: linked <ruta>` |
| `th-wt: installing dependencies (<gestor> <args>)` | solo si de verdad se ejecuta el gestor (hay lockfile soportado, `TH_INSTALL_DEPS` no es `0` y el gestor está en `PATH`) |
| `th-wt: indexing with codegraph (may take a few minutes)` | solo si de verdad se ejecuta `codegraph init` |

Ninguna línea imprime el contenido del `.conf` ni de los `.env*`. `list --remote` y `close --remote` no escriben líneas de progreso.

**Resumen:** sin `--json`, al terminar bien `new` escribe en stderr un resumen con las etiquetas alineadas, y stdout queda vacío. `linked` lista las rutas enlazadas separadas por `, ` (o `none`), `deps` es el valor de `deps` del JSON y `codegraph` es `indexed` o `not indexed`. El gestor de paquetes y `codegraph` también escriben en stderr (ver «Instalación de dependencias» e «Integración con codegraph»). Con `--json` no hay resumen: el objeto va a stdout y las líneas de progreso siguen en stderr.

```text
$ th-wt new feature/login
th-wt: fetching origin/main
th-wt: creating worktree ~/.worktrees/acme/demo/feature-login (branch feature/login)
th-wt: applying repo config ~/.config/th-worktools/repos/acme/demo.conf
th-wt: linked .wiki
th-wt: linked docs/local
th-wt: installing dependencies (pnpm install --frozen-lockfile)
…salida de pnpm…
th-wt: indexing with codegraph (may take a few minutes)
…salida de codegraph…
  path:      ~/.worktrees/acme/demo/feature-login
  branch:    feature/login
  linked:    .wiki, docs/local
  deps:      pnpm
  codegraph: indexed
```

(En la salida real las rutas van completas, sin `~`.)

**Flags:**

| Flag | Efecto |
|---|---|
| `--base <branch>` | Crea la rama desde `origin/<branch>` en lugar de la rama por defecto de `origin`. Debe ser un nombre de rama válido en `origin` (sin el prefijo `origin/`, tags, SHAs ni expresiones como `main~1`). |
| `--json` | Escribe en stdout un objeto JSON con `path`, `branch`, `repo`, `linked`, `deps` y `codegraph`. |

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

- **Si `<branch>` ya existe como rama local (`refs/heads/<branch>`):** abre el worktree directamente en ese commit local, sin consultar `origin` y sin mover la rama (aunque se pase `--remote` y `origin/<branch>` haya avanzado).
- **Si `<branch>` no existe en local:** busca `refs/remotes/origin/<branch>` (con `--remote`, antes verifica que exista en `origin` y hace fetch de esa rama). Crea la rama local en ese commit y configura su upstream a `origin/<branch>` (`branch.<branch>.remote = origin` y `branch.<branch>.merge = refs/heads/<branch>`).

Después aplica el `.conf` del repo (ver «Enlaces por repo») e instala las dependencias si hay lockfile (ver «Instalación de dependencias»), salvo en una rama `review/pr-*` (copia local de un PR, p. ej. conservada por `close review/pr-<n> --force`): se trata como `pr` y no enlaza ni instala (`linked: []`, `deps: "skipped"`, con el aviso del comando a mano); sí indexa con `codegraph`. `checkout` escribe en stderr las mismas líneas de progreso que `new` (`fetching origin/<rama>` solo con `--remote` y una rama que no es local; `applying repo config` e `installing dependencies` nunca en `review/pr-*`), lo que escriban el gestor de paquetes y `codegraph` y los avisos. Sin `--json`, al terminar bien escribe en stderr el mismo resumen de cinco líneas que `new` (`path`, `branch`, `linked`, `deps`, `codegraph`); en stdout no imprime nada.

**Flags:**

| Flag | Efecto |
|---|---|
| `--remote` | Si la rama no existe en local, la consulta y descarga de `origin` antes de crear el worktree. Si la rama ya existe en local, no tiene efecto. |
| `--json` | Escribe en stdout un objeto JSON con `path`, `branch`, `repo`, `linked`, `deps` y `codegraph`. |

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

**Dependencias:** `pr` **no instala dependencias** (`deps: "skipped"`): el PR puede ser código de un tercero y la instalación lo ejecutaría (el `.npmrc` y el `packageManager` del PR controlan el gestor, y además hay scripts de ciclo de vida y `.pnpmfile.cjs`; `--ignore-scripts` no basta). Si hay un lockfile soportado, avisa por stderr con el comando a ejecutar a mano en el worktree si confías en el PR (`pnpm install --frozen-lockfile` / `npm ci`).

**codegraph:** `pr` sí indexa el worktree (ver «Integración con codegraph»): es análisis estático y no ejecuta el código del PR. Si el PR trae su propio `.codegraph/` con un índice, no se indexa ni se usa.

**Progreso:** siempre (con o sin `--json`), `pr` escribe en stderr `th-wt: fetching origin refs/pull/<n>/head` antes del fetch del PR y, después, las líneas de `new` que le tocan: `fetching origin/<base>`, `creating worktree` e `indexing with codegraph` (nunca `applying repo config` ni `installing dependencies`).

**Salida:** con `--json`, el objeto de `new` más `pr`; sin `--json`, un resumen por stderr con los caracteres de control del título y de las ramas (que escribe el autor del PR) sustituidos por espacios:

```text
  path:      ~/.worktrees/acme/demo/pr-reviews/pr-7/code
  PR:        #7 Arreglar el login
  branch:    fix/login
  base:      main
  deps:      skipped
  codegraph: indexed
```

Para actualizar un worktree de PR cuando recibe commits nuevos, ciérralo y vuelve a abrirlo.

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

Para cada worktree informa la rama (o `(detached)`), si el directorio falta (`missing`), si tiene cambios locales (`dirty`, comprobado con `git --no-optional-locks status --porcelain --untracked-files=normal` para no bloquear ni modificar el índice; lo que genera codegraph no cuenta, así que un worktree indexado sale limpio; los cambios en archivos que git versiona bajo `.codegraph/` sí) y si está contenida en la rama por defecto de `origin` (`merged`). Sin `--json`, las filas (una por worktree) van a **stdout**, así que se pueden filtrar (`th-wt list | grep login`); los avisos (como el del límite de PRs) y `no worktrees under ~/.worktrees/<owner>/<repo>/` van a **stderr**.

**Flags:**

| Flag | Efecto |
|---|---|
| `--remote` | Consulta en `origin` cuál es la rama por defecto, hace fetch de `refs/remotes/origin/<default>` (sin tocar `origin/HEAD`) y consulta los PRs más recientes en GitHub con `gh pr list` (hasta `TH_PR_LIMIT`, 500 por defecto). Añade a cada worktree la información de su PR (`pr`). |
| `--json` | Escribe en stdout un único objeto `{repo, worktrees}`. |

Con `--remote`, si `gh` devuelve el total del límite consultado (`TH_PR_LIMIT`, 500 por defecto) y queda alguna rama no contenida sin PR asociado, `list` emite un aviso en stderr:
`th-wt: only the <N> most recent PRs were checked; branches without a PR here may have an older one`.

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
4. **Archivos ignorados (`ignored`):** el plan lista los nombres de archivos y directorios ignorados por git en el worktree (con directorios colapsados como `build/`, sin mostrar nunca su contenido; no lista los symlinks creados por `link`, ni un directorio que solo contiene symlinks, porque borrarlos no pierde datos; tampoco lista lo que genera codegraph en `.codegraph/`, que `close --yes` borra a propósito, ni lo cuenta como `dirty`; si el repo versiona archivos bajo `.codegraph/`, los cambios en ellos sí cuentan como `dirty` y bloquean el cierre sin `--force`). Se eliminan con el directorio del worktree y nunca bloquean el cierre.
5. **`.codegraph/` (con `--yes`):** si es un directorio real (no un symlink) y git no versiona nada dentro, `th-wt` borra `.codegraph/` él mismo justo antes de `git worktree remove`, sin ejecutar `codegraph` (no hace falta que esté instalado). No usa `codegraph uninit`: además de borrar la carpeta, quita los hooks de sincronización de git del `.git/hooks`, que comparten el checkout principal y todos los worktrees, y el kit no escribe en tu repo. Si git versiona algo bajo `.codegraph/`, `th-wt` no lo toca: `git worktree remove` se lleva el índice ignorado. `TH_CODEGRAPH=off` no afecta a `close`. El dry-run no toca nada.

   Limitación conocida: `.codegraph/` se borra justo antes de `git worktree remove`; si ese `remove` falla (p. ej. un worktree bloqueado), el worktree se queda sin su índice. Regéneralo con `codegraph init -y` dentro de él.

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
| `checkout` | **Con `--remote`** y solo si la rama no existe en local (`refs/heads/<branch>`) para consultar `origin`; **además, siempre que haya lockfile**, para instalar dependencias (acceso al registro de paquetes) | `git ls-remote --heads origin refs/heads/<branch>` y `git fetch -q --no-tags origin +refs/heads/<branch>:refs/remotes/origin/<branch>`; instalación con `pnpm` / `npm` | No |
| `list` | **Solo con `--remote`** | `git ls-remote --symref origin HEAD`, `git fetch -q --no-tags origin +refs/heads/<default>:refs/remotes/origin/<default>` y `gh pr list -R <owner>/<repo> --state all --limit <pr_limit> ...` | Sí (con `--remote`) |
| `pr` | **Siempre** | `gh pr view <n> -R <owner>/<repo> --json number,title,headRefName,baseRefName,headRefOid`, `git fetch -q --no-tags origin refs/pull/<n>/head` y `git fetch -q --no-tags origin +refs/heads/<base>:refs/remotes/origin/<base>` | Sí |
| `close` | **Solo con `--remote`** | Igual que `list --remote`, pero filtrando en `gh pr list` con `--limit 1000 --head <branch>` | Sí (con `--remote`) |

### Instalación de dependencias

`new` y `checkout` instalan las dependencias del worktree con `pnpm` o `npm`, que usan la red (registro de paquetes) aunque el subcomando no la use por otra vía. Es la única red que usa `checkout` sin `--remote`. Estas llamadas no escriben ninguna ref de git. `pr` no instala dependencias.

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
| `1` | Error de ejecución | **`new` / `checkout`:** falla `git worktree add` tras superar las validaciones previas (conflicto de refs como `conf` con `conf/x`, permisos de escritura en `~/.worktrees`, o rama en rebase/bisect en otro worktree con HEAD `detached`), o falla el enlace de una entrada ya validada del `.conf` (se deshace la creación). |
| `2` | Uso incorrecto | **Todos:** sin subcomando, subcomando desconocido, opción desconocida o argumento posicional inesperado.<br>**`new`:** falta `<branch>`, opción antes de `<branch>`, `--base` vacío o sin argumento, `<branch>` es `HEAD` o formato inválido de `<branch>` / `--base` (p. ej. `main~1`, `bad..name`).<br>**`checkout`:** falta `<branch>`, opción antes de `<branch>`, `<branch>` es `HEAD` o formato de rama inválido.<br>**`new` / `checkout`:** además, una rama cuyo nombre normalizado es `pr-reviews`.<br>**`pr`:** `<n>` ausente o que no es un entero positivo sin ceros a la izquierda.<br>**`close`:** falta `<branch>`, más de un argumento posicional o formato de rama inválido. |
| `3` | Dependencia faltante | **Todos:** falta `git` o `jq` en `PATH`.<br>**`pr` / `list --remote` / `close --remote`:** falta `gh` en `PATH`. |
| `4` | Precondición no cumplida | **Todos:** fuera de un repositorio git, sin remote `origin` o URL de `origin` con formato no soportado, o configuración inválida (archivo `config` o variables de entorno; ver «Configuración»).<br>**`new`:** destino ya existente, la rama ya existe en local o en `origin`, `origin` inaccesible, `origin` sin rama por defecto (sin `--base`), o `--base` no existe en `origin` / falla el fetch.<br>**`checkout`:** destino ya existente, rama ya abierta en el checkout principal o en otro worktree, rama inexistente en local y en `refs/remotes/origin/<branch>` (sin `--remote`), o con `--remote` `origin` inaccesible / rama inexistente en `origin` / fallo de fetch.<br>**`new` / `checkout`:** además, una entrada inválida del `.conf` del repo (`th-wt: <conf>:<línea>: <motivo>`; se deshace la creación).<br>**`pr`:** la ruta `pr-reviews/pr-<n>/code` o la rama `review/pr-<n>` ya existen, `gh pr view` falla o devuelve algo inesperado, o falla un fetch de `origin` (PR sin `refs/pull/<n>/head`, `origin` inaccesible, base ausente), o el commit traído no es el `headRefOid` de `gh`.<br>**`list --remote`:** `origin` inaccesible, `origin` sin rama por defecto, fallo del fetch, fallo de `gh pr list` (sin autenticar o sin acceso) o salida JSON inesperada de `gh`.<br>**`close`:** la rama no tiene worktree bajo `~/.worktrees/<owner>/<repo>/` (o no existe / es huérfana / está en `detached`), errores de `--remote` (igual que `list --remote`), o con `--yes`: ejecutado desde dentro del worktree a cerrar, bloqueado por cambios sin commitear / commits sin push (en un worktree de PR, commits propios posteriores al PR o desconocidos) / `git status` ilegible (sin `--force`), o fallo de `git worktree remove` (p. ej. worktree bloqueado con `git worktree lock`). |

---

## 5. Salida `--json`

Con `--json`, todos los subcomandos escriben un único objeto JSON en **stdout** (generado con `jq`). Los avisos y errores siguen saliendo por **stderr**. Sin `--json`, los mensajes para personas también van a stderr, salvo la ayuda de `--help`/`-h` y las filas de `list`, que van a stdout.

### `new --json` y `checkout --json`

Devuelven el mismo esquema:

| Campo | Tipo | Descripción |
|---|---|---|
| `path` | `string` | Ruta absoluta del worktree creado (`~/.worktrees/<owner>/<repo>/<rama-normalizada>`). |
| `branch` | `string` | Nombre real de la rama en git. |
| `repo` | `string` | `<owner>/<repo>` derivado de `origin`. |
| `linked` | `string[]` | Rutas enlazadas desde el `.conf` del repo, en el orden del archivo; `[]` si no hay `.conf` (ver «Enlaces por repo»). |
| `deps` | `string` | Resultado de la instalación de dependencias: `"pnpm"`, `"npm"` (instaladas), `"skipped"` (sin lockfile soportado, el gestor no está en `PATH`, o es `pr`) o `"failed"` (el gestor salió con error). |
| `codegraph` | `boolean` | `true` si `codegraph init` indexó el worktree; `false` si `codegraph` no está instalado, `TH_CODEGRAPH=off`, el worktree ya traía un `.codegraph` o el `init` falló (ver «Integración con codegraph»). |

```json
{
  "path": "/Users/alice/.worktrees/acme/demo/feature-login",
  "branch": "feature/login",
  "repo": "acme/demo",
  "linked": [".wiki", ".env"],
  "deps": "pnpm",
  "codegraph": true
}
```

#### Enlaces por repo (`.conf`)

Tras crear el worktree y antes de instalar las dependencias, `new` y `checkout` aplican `${XDG_CONFIG_HOME:-$HOME/.config}/th-worktools/repos/<owner>/<repo>.conf`. Sin ese archivo no se enlaza nada y no hay aviso. `pr` y `checkout` de una rama `review/pr-*` nunca lo aplican: el código del PR podría leer los `.env` enlazados. Ejemplo ficticio: `examples/config/repos/mi-org/mi-repo.conf`.

```text
# una entrada por línea; # y las líneas vacías se ignoran
link .wiki
link .env
link docs/local
```

El archivo se lee línea a línea, nunca con `source`. La única acción es `link <ruta>` (no hay `copy`). Cada enlace es un symlink con destino absoluto `<checkout principal>/<ruta>` (el checkout principal es la primera entrada de `git worktree list`); los directorios intermedios se crean en el worktree. Sin `--json`, informa `th-wt: linked <ruta>` por stderr, una línea por enlace.

**Validación:** se validan todas las líneas antes de enlazar nada. Cada `<ruta>` debe cumplir:

- Relativa, sin `/` inicial, sin segmentos `.`, `..` ni vacíos y sin barra final.
- Sin globs (`*`, `?`, `[`).
- Sin duplicados ni solapamientos con otra entrada (`docs` y `docs/local`).
- Existir en el checkout principal.
- Si algún padre de la ruta ya existe en el worktree, ser un directorio real (no un archivo versionado ni un symlink).
- Estar ignorada por git **en el worktree nuevo** (`git check-ignore`, con el `.gitignore` de la rama abierta). Git ve un symlink como un archivo, así que `.wiki/` con barra final no lo cubre: la entrada debe ir sin barra (`.wiki`) en el `.gitignore` o en el `.git/info/exclude` del repo, que es local y se comparte entre todos los worktrees. `th-wt` no escribe nunca en `.git/info/exclude`: lo añade el usuario. Una ruta versionada también se rechaza.

**Entrada inválida:** sale con código `4`, no deja nada creado (se elimina el worktree y, si la creó este comando y sigue en su commit de inicio, la rama; una rama local existente abierta con `checkout` se conserva) y escribe `th-wt: <ruta del .conf>:<línea>: <motivo>` en stderr. Motivos:

| Motivo | Causa |
|---|---|
| `unknown action '<a>' (only 'link' is supported)` | Acción distinta de `link` (incluida `copy`). |
| `expected 'link <path>'` | Falta la ruta o hay más de una (las rutas con espacios no se admiten). |
| `path must be relative, without '.', '..' or empty segments and without a trailing slash: <p>` | Ruta absoluta, con `.`, `..`, segmentos vacíos o barra final. |
| `globs are not supported: <p>` | La ruta contiene `*`, `?` o `[`. |
| `<p> overlaps <q> (line <n>)` | Duplicada o contenida en otra entrada. |
| `<p> does not exist in the main checkout (<main>)` | No existe en el checkout principal. |
| `<p>: parent <dir> in the worktree is not a directory` | Un padre existente en el worktree es un archivo o un symlink. |
| `<p> is ignored only as a directory ('<p>/'); git sees a symlink as a file, so ignore '<p>' without the trailing slash` | Ignorada con barra final. |
| `<p> is not ignored by git in the worktree (versioned, or missing from .gitignore)` | Versionada o ausente del `.gitignore` de la rama. |

Si el enlace falla después de validar (por ejemplo, por permisos), también se deshace la creación, pero sale con código `1`. Si `git worktree remove` no puede quitar el worktree al deshacer, la rama no se borra (evita dejar un worktree sobre una rama borrada) y stderr avisa `th-wt: warning: could not remove the worktree <ruta>; branch <rama> kept`; el comando sale igualmente con su código (`4` o `1`).

#### Instalación de dependencias

Tras crear el worktree, `th-wt` busca un lockfile en su raíz (si hay `pnpm-lock.yaml` y `package-lock.json`, gana pnpm):

| Lockfile | Comando (en `new` y `checkout`) | En `pr` |
|---|---|---|
| `pnpm-lock.yaml` | `pnpm install --frozen-lockfile` | no se ejecuta; el aviso lo sugiere para hacerlo a mano |
| `package-lock.json` | `npm ci` | no se ejecuta; el aviso lo sugiere para hacerlo a mano |
| `yarn.lock`, `bun.lock`, `bun.lockb`, `Cargo.lock`, `uv.lock`, `poetry.lock` | no se instala; avisa por stderr con el nombre del archivo (`deps: "skipped"`) | igual |
| ninguno | no se instala (`deps: "skipped"`) | igual |
| cualquiera, con `TH_INSTALL_DEPS=0` | no se instala (`deps: "skipped"`); stderr: `th-wt: dependency install disabled (TH_INSTALL_DEPS=0); dependencies not installed in <ruta>` | igual (nunca instala) |

En `checkout`, una rama `review/pr-*` sigue la columna «En `pr`».

- El gestor se ejecuta con el worktree como directorio de trabajo, con su salida redirigida a **stderr** (stdout queda para el objeto `--json`) y con stdin cerrado (`/dev/null`), así que nunca espera una respuesta.
- Si el gestor sale con error, `th-wt` conserva el worktree, avisa por stderr y sale con `0`; `deps` vale `"failed"`. Se puede repetir la instalación a mano en el worktree.
- Si hay lockfile pero `pnpm` / `npm` no está en `PATH`, avisa por stderr, no instala y sale con `0`; `deps` vale `"skipped"`.
- Sin `--json`, el gestor escribe igualmente en stderr.
- El `prepare` del proyecto corre con la instalación. Si configura hooks (p. ej. husky escribe `core.hooksPath = .husky/_`), lo escribe en la config compartida del repo; es una ruta relativa, así que cada worktree usa sus propios hooks, y suele ser el mismo valor que ya dejó la instalación en el checkout principal.
- La instalación puede tardar minutos; quien invoque `new` o `checkout` debe usar un timeout largo. Si se corta, el worktree ya existe: instala a mano dentro de él en vez de repetir el comando.

#### Integración con codegraph

Después de las dependencias, con `TH_CODEGRAPH=auto` y `codegraph` en `PATH`, `new`, `checkout` y `pr` (y `checkout` de `review/pr-*`) ejecutan `codegraph init -y <ruta del worktree>`: `-y` lo hace no interactivo (verificado con codegraph 1.6.2). La salida va a **stderr** y stdin es `/dev/null`. Se ejecuta con `CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_UPDATE_CHECK=1` (sin telemetría ni comprobación de actualizaciones) para que el subcomando no use la red, y con `CODEGRAPH_NO_WATCH=` y `CODEGRAPH_DIR=` vacías: con `CODEGRAPH_NO_WATCH=1` en tu entorno, `init -y` instalaría hooks de sincronización de git en el `.git/hooks` compartido por el checkout principal y todos los worktrees, que el kit no debe escribir; y `CODEGRAPH_DIR` movería el índice a una carpeta que el kit no comprueba. Indexar un PR es análisis estático: no ejecuta su código.

- Éxito: `codegraph: true`.
- `codegraph` no instalado o `TH_CODEGRAPH=off`: `codegraph: false`, sin mensaje.
- `.codegraph` ya existe en el worktree como symlink (p. ej. `link .codegraph` del `.conf`) o con algo más que un `.gitignore` que sea un archivo regular (p. ej. un PR que versiona su propio `.codegraph/codegraph.db`, o un `.gitignore` que es un symlink): no se ejecuta `init`, `codegraph: false`, sale con `0` y stderr avisa `th-wt: warning: .codegraph already exists in <ruta>; not indexed`. Un índice aportado por un PR nunca se usa. Un `.codegraph/` con solo un `.gitignore` regular versionado se indexa con normalidad.
- `init` falla: se conserva el worktree, sale con `0`, `codegraph: false` y stderr avisa `th-wt: warning: codegraph init failed in <ruta>; run 'codegraph init -y' there manually`.
- En un repo grande `init` puede tardar minutos: quien invoque `new`, `checkout` o `pr` debe usar un timeout largo. Si se corta, el worktree ya existe: ejecuta `codegraph init -y` a mano dentro de él.
- `list` y `close` ignoran lo que genera codegraph (el directorio `.codegraph/` sin seguimiento y sus archivos ignorados) al calcular `dirty` y `ignored`, así que un worktree indexado sale limpio. Si el repo versiona archivos bajo `.codegraph/`, los cambios en ellos sí cuentan como `dirty`. `th-wt` no toca el `.gitignore` propio de codegraph (`.codegraph/.gitignore`): un `git status` manual muestra `?? .codegraph/` salvo que agregues `.codegraph/` a tu gitignore global (`git config --global core.excludesFile`).
- `close --yes` borra el índice (ver `close`, punto 5). No se reindexan ni se indexan worktrees creados antes de #9.

### `pr --json`

El objeto de `new --json` más `pr`:

| Campo | Tipo | Descripción |
|---|---|---|
| `path` | `string` | `~/.worktrees/<owner>/<repo>/pr-reviews/pr-<n>/code`. |
| `branch` | `string` | `review/pr-<n>`. |
| `repo` | `string` | `<owner>/<repo>` derivado de `origin`. |
| `linked` | `string[]` | Siempre `[]`: `pr` no aplica el `.conf`. |
| `deps` | `string` | Igual que en `new --json` (en `pr`, siempre `"skipped"`). |
| `codegraph` | `boolean` | Igual que en `new --json` (`pr` sí indexa). |
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
| `ignored` | `string[] \| null` | Nombres de archivos y directorios ignorados por git en el worktree (directorios colapsados con `/` final; sin symlinks ni directorios que solo los contienen); `[]` si no hay ninguno o si `missing` es `true`; `null` si falló `git status`. |
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
