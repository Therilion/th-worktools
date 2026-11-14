# th-worktools

Kit personal de skills y scripts para agentes de código, compatible con **Claude Code** y **Antigravity CLI**. Sigue el estándar Agent Skills (`SKILL.md`) y funciona en macOS y Linux.

> **Estado:** v0.1 completa. `th-worktree` funciona con `new`, `checkout`, `pr`, `list` y `close` desde Claude Code, Antigravity CLI y la terminal; `install.sh` instala el kit y `verify.sh` comprueba la instalación. Probado en uso real en macOS.

## Principios

- **No escribe en tus repos.** Todo vive en el kit, en `~/.config/th-worktools/` o en `~/.worktrees/`.
- **Dry-run por defecto.** Las acciones con efectos secundarios solo muestran el plan; `--yes` las ejecuta.
- **Herramientas externas opcionales.** Se usan si están instaladas y se omiten si no.
- **Secretos protegidos.** Los archivos `.env*` solo se tocan si lo configuras, y los scripts nunca imprimen su contenido.

## Instalación en tres pasos

1. Instala las dependencias de [Requisitos](#requisitos): `git`, `jq` y bash 3.2 o superior; `gh` solo si usas `pr`, `list --remote` o `close --remote`.
2. Clona el repo y ejecuta `install.sh` desde la raíz del clon:

   ```sh
   git clone https://github.com/Therilion/th-worktools.git
   cd th-worktools
   ./install.sh --link-here --yes
   ```

3. Ejecuta `./verify.sh`. Sale con `0` si todo está bien. Después, en Claude Code o Antigravity CLI, escribe `/th-worktree list` desde un repo git con remote `origin` (fuera de un repo o sin `origin`, `th-wt` sale con `4`): funciona sin más configuración. Sin los [permisos sugeridos](#permisos-sugeridos), que son opcionales, el agente te pide confirmación antes de ejecutarlo.

Detalle del paso 2 (`install.sh`):

- Ejecútalo desde la raíz del clon principal, no desde un worktree (al cerrarlo, el enlace quedaría colgando).
- Sin `--yes` solo muestra el plan; con `--yes` lo aplica:

  ```sh
  ./install.sh --link-here        # muestra el plan, no cambia nada
  ./install.sh --link-here --yes  # lo aplica
  ```

- Enlaza `~/.local/share/th-worktools` (la ruta fija que usa el `SKILL.md`) al clon, cada `skills/th-*/` en los agentes y `th-wt` en `~/.local/bin/`.
- Por defecto instala en los agentes cuyo binario está en el `PATH`: `claude` (`~/.claude/skills/`) y `agy` (`~/.gemini/config/skills/`). `--agents claude` (o `claude,agy`) elige cuáles.
- Nunca toca una ruta que no sea del kit: la deja, instala el resto y sale con `4`. Repetirlo es seguro: lo que ya está bien sale como `ok`.
- `th-wt` desde la terminal exige que `~/.local/bin` esté en el `PATH`.

Detalle del paso 3 (`verify.sh`):

- Úsalo con el mismo `--agents`, si lo usaste en `install.sh`, para comprobar que cada agente ve los skills.
- Solo lee. Sale con `0` si todo está bien, con `2` si el uso es incorrecto o el agente no está soportado, con `3` si falta en el `PATH` `git`, `jq` o un agente de `--agents`, y con `4` si algo está roto.

## Versiones

Cada versión tiene su tag, su release en [GitHub](https://github.com/Therilion/th-worktools/releases) y su entrada en [`CHANGELOG.md`](CHANGELOG.md), generados con release-please a partir de los commits. Para instalar una versión concreta, en el paso 2 añade `--branch vX.Y.Z` al `git clone` (con la versión de la lista de releases) y sigue igual el resto de los pasos 2 y 3:

```sh
git clone --branch vX.Y.Z https://github.com/Therilion/th-worktools.git
```

- SemVer 0.x con un solo versionado para todo el kit. Antes de 1.0, `feat` y `fix` suben el patch y un breaking change sube el minor.
- El minor de cada versión de la [hoja de ruta](#hoja-de-ruta) se fija con el footer `Release-As: X.Y.Z`, que va al final del cuerpo del commit squash, como último párrafo y tras una línea en blanco (si va antes de la lista de commits, se ignora).

## Requisitos

Versiones probadas en macOS (Darwin 25); CI corre en macOS y Ubuntu. Instálalas con el gestor de paquetes de tu sistema.

| Grupo                                        | Herramienta | Versión probada         |
| -------------------------------------------- | ----------- | ----------------------- |
| Requerida                                    | `git`       | 2.50.1                  |
| Requerida                                    | `jq`        | 1.7.1                   |
| Requerida                                    | bash        | 3.2.57 (3.2 o superior) |
| Para `pr`, `list --remote`, `close --remote` | `gh`        | 2.103.3                 |
| Opcional (indexa los worktrees nuevos)       | `codegraph` | 1.6.2                   |

Agentes (al menos uno): Claude Code 2.1.311 y Antigravity CLI (`agy`) 1.5.3.

## Permisos sugeridos

Opcionales. `install.sh` no los escribe: cópialos tú en la configuración de cada agente, **fusionados** con lo que el archivo ya tenga (no lo reemplaces). Hacen que `list` corra sin pedir permiso, que `close … --yes` lo pida siempre (en agy, mientras no añadas un `allow` que cubra `th-wt` por el PATH; ver las notas) y, en Claude Code, que leer un `.env*` quede bloqueado.

**Claude Code** (`~/.claude/settings.json`):

```json
{
  "permissions": {
    "allow": ["Bash(*/.local/share/th-worktools/skills/th-worktree/scripts/th-wt list*)"],
    "ask": ["Bash(*th-wt close*--yes*)"],
    "deny": ["Read(**/.env*)"]
  }
}
```

**Antigravity CLI** (`~/.gemini/antigravity-cli/settings.json`):

```json
{
  "permissions": {
    "allow": ["command(regex:\"\\$HOME/\\.local/share/th-worktools/skills/th-worktree/scripts/th-wt\" list( --(json|remote))*)"],
    "ask": ["command(regex:.*th-wt\"? close .*--yes.*)"]
  }
}
```

- Un comando encadenado (`th-wt list && otro`) siempre pide permiso.
- `./tools/th-wt list` (un `th-wt` que traiga un repo) pide permiso en los dos agentes.
- agy: el `allow` solo acepta la forma exacta que escribe el `SKILL.md` (`"$HOME/…/th-wt" list`, con `$HOME` literal y comillas), con `--json` y `--remote` como únicas opciones. Bloquea pipes, `;`, `$(…)` y la ruta como argumento de otro comando. `th-wt list` por el PATH pide permiso.
- Claude Code: el `allow` lleva un `*` inicial, así que un comando que contenga la ruta del kit como argumento (p. ej. `rm -rf ~ …/.local/share/th-worktools/skills/th-worktree/scripts/th-wt list`) coincide con el `allow` y podría pasar sin pedir permiso. `;`, `|` y `$(…)` sí piden permiso. Si no aceptas ese riesgo, no añadas el `allow` de Claude Code.
- En Claude Code el `ask` gana a cualquier `allow`. En agy, un `allow` que cubra `th-wt` por el PATH (p. ej. `command(regex:.*th-wt.*)`) gana al `ask` en `th-wt close … --yes`: no añadas uno.
- `Read(**/.env*)` también bloquea `.env.example`, `.env.sample` y `.envrc`.
- El `deny` de Claude Code solo cubre la herramienta de lectura de archivos, no un `cat .env` por la shell. En agy no se probó un bloqueo equivalente.
- Comprobado en macOS con Claude Code 2.1.311 y agy 1.5.3; el `allow` de `list` y el `ask` de `close --yes`, también con agy 1.5.8. Detalle en [`docs/plan-v0.1.md`](docs/plan-v0.1.md) §13.

## v0.1: `th-worktree`

Crea, abre, lista y cierra git worktrees en `~/.worktrees/<owner>/<repo>/<rama>`, para trabajar en paralelo sin tocar el checkout principal.

| Subcomando                                             | Qué hace                                                                                                 | Estado     |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- | ---------- |
| `new <branch> [--base <branch>] [--json]`              | Worktree con una rama nueva                                                                              | disponible |
| `checkout <branch> [--remote] [--json]`                | Worktree de una rama existente, local o de `origin` (`--remote` la trae)                                 | disponible |
| `pr <n> [--json]`                                      | Worktree de un PR de GitHub (también de un fork) en `pr-reviews/pr-<n>/code`, en la rama `review/pr-<n>` | disponible |
| `list [--remote] [--json]`                             | Worktrees del repo actual, con su estado (`--remote` consulta `origin` y los PRs de GitHub)              | disponible |
| `close <branch\|path> [--remote] [--yes] [--force] [--json]` | Cierra el worktree por rama o por ruta (también con `HEAD` desacoplado); requiere `--yes`. Para un PR: `close review/pr-<n>` | disponible |
| `link <branch> [--json]` | Re-aplica el `.conf` a un worktree ya abierto: crea los enlaces que faltan | disponible |

Hoy, al crear un worktree con `new` o `checkout` se crean el worktree y la rama, se enlazan los archivos ignorados que declares por repo en `~/.config/th-worktools/repos/<owner>/<repo>.conf` (por ejemplo, `link .wiki` o `link .env`, y `deps-prefix <comando>` para anteponer un ejecutable del `PATH` al comando de instalación; ver [`examples/config/repos/mi-org/mi-repo.conf`](examples/config/repos/mi-org/mi-repo.conf)) y se instalan las dependencias según el lockfile: `pnpm-lock.yaml` → `pnpm install --frozen-lockfile`, `package-lock.json` → `npm ci`. `pr` nunca enlaza ni instala dependencias: el código del PR es de un tercero (con las dependencias, avisa con el comando para hacerlo a mano). Si agregas una línea al `.conf` después, `th-wt link <rama>` la re-aplica a un worktree ya abierto: crea los enlaces que faltan, con las mismas validaciones, y no borra nada.

La raíz de worktrees (`TH_WORKTREES_ROOT`, por defecto `~/.worktrees`), la instalación de dependencias (`TH_INSTALL_DEPS=0` la apaga), el índice de codegraph (`TH_CODEGRAPH=off` lo apaga) y el límite de PRs en `list --remote` (`TH_PR_LIMIT`, por defecto `500`) se configuran con variables de entorno o con `~/.config/th-worktools/config` (ver [`examples/config/config`](examples/config/config)); el entorno gana al archivo. Una configuración inválida sale con `4` sin crear nada.

Si `codegraph` está instalado, `new`, `checkout` y `pr` ejecutan `codegraph init -y` en el worktree (después de las dependencias; indexar es análisis estático y no ejecuta el código de un PR) y `close --yes` borra el índice (`.codegraph/`) sin ejecutar `codegraph`. Si el worktree ya trae un `.codegraph` (un symlink, o un índice que viene en un PR) no lo indexa y avisa: nunca usa un índice ajeno. Un `git status` manual muestra `?? .codegraph/` salvo que agregues `.codegraph/` a tu gitignore global (`git config --global core.excludesFile`); `th-wt list` y `close` no cuentan como cambio lo que genera codegraph, pero sí los archivos que el repo versiona bajo `.codegraph/`.

Hoy funciona desde Claude Code y Antigravity CLI (`/th-worktree new feature/login`; en los dos hay que escribir `/th-worktree`, el skill no se activa solo) y desde la terminal: con el enlace que crea `install.sh`, `th-wt <subcomando>` funciona desde un repo o un worktree (`th-wt --help` muestra el uso); la ruta completa del script sigue valiendo.

La referencia completa (subcomandos, red, códigos de salida y `--json`) está en [`docs/th-worktree.md`](docs/th-worktree.md).

## Hoja de ruta

| Versión | Contenido                                                                 |
| ------- | ------------------------------------------------------------------------- |
| v0.1    | `th-worktree`, instalación y CI                                           |
| v0.2    | `th-repo-context`: índice de la documentación del repo, generado al vuelo |
| v0.3    | `th-pr-review`: revisión de PRs con mutation testing limitado al diff     |
| v0.4    | `th-integration-context`: contexto compartido entre repos                 |

Cada versión de la tabla es una línea de releases: la v0.2 empieza en `v0.2.0` (fijada con `Release-As`, ver [Versiones](#versiones)) y las mejoras y correcciones que salgan antes van como `v0.1.x`.

El detalle de las decisiones está en [`docs/plan-v0.1.md`](docs/plan-v0.1.md) y la guía de desarrollo y tests en [`docs/desarrollo.md`](docs/desarrollo.md).

Las ramas de cada historia se integran en `main` con un merge commit hasta la historia 5; a partir de la historia 6 se integran con squash.

## Ideas

Ideas que quedan fuera de la versión en curso.

- `th-wt link <ruta>`: re-aplicar el `.conf` por ruta, también a un worktree con `HEAD` desacoplado (rebase o bisect a medias); hoy `link` solo acepta una rama y ese worktree sale con `no worktree for branch`.
- `th-wt list --remote`: con 100 PRs o más, el aviso del límite de PRs sale siempre si hay un worktree `review/pr-<n>` abierto, porque esa rama no tiene PR con ese nombre de origen; tratar `review/pr-<n>` como rama de PR en `list` (mostrar su número de PR).
- Derivar `<owner>/<repo>` también de remotes `ssh://`, con puerto o con barra final (hoy solo `git@host:` y `https://`).
- Que `--base` acepte tags y SHAs (hoy es siempre `origin/<rama>`).
- Instalar dependencias de otros gestores al crear un worktree (hoy, en #6, solo pnpm y npm): yarn (`--immutable` en Yarn 2+, `--frozen-lockfile` en Yarn 1; distinguir la versión con `.yarnrc.yml` o `packageManager`), bun (`bun.lock`/`bun.lockb`), Rust (`Cargo.lock` → `cargo fetch --locked`, que no ejecuta `build.rs`; no vale para `pr`: lee el `.cargo/config.toml` del PR) y Python (`uv.lock` → `uv sync --locked`; `poetry.lock` → `poetry install`). `requirements.txt` no es un lockfile: omitirlo. Verificar los flags en las versiones instaladas.
- Instalar dependencias solo si se pide, con un flag (p. ej. `--deps`) en todo comando que crea un worktree (`new`, `checkout`, `pr`), en vez de instalar por defecto. En `pr` (hoy nunca instala: el `.npmrc` y el `packageManager` del PR controlan el gestor), quizá solo para PRs del mismo repo o dentro de un contenedor.
- Investigar si se puede detectar un riesgo antes de instalar (p. ej. revisar `.npmrc`, `packageManager`, `.pnpmfile.cjs`, scripts de ciclo de vida o dependencias de git, o usar herramientas de auditoría de paquetes), sabiendo que ninguna comprobación cubre los vectores que aparezcan después.
- Configuración multinivel: reglas comunes a una organización (`repos/<owner>.conf`) que se combinan con las del repo (`repos/<owner>/<repo>.conf`), p. ej. `link .wiki` o `link .openspec` en todos los repos de una organización. Necesita enlaces opcionales («solo si existe»): hoy un `link` sin origen falla y deshace el worktree.
- Verificar el aviso de descarga de corepack con stdin en `/dev/null` (`new`/`checkout`): si bloquea, fijar `COREPACK_ENABLE_DOWNLOAD_PROMPT`.
- `.conf`: admitir rutas con espacios (hoy `link` toma una sola palabra; cambia el formato de la línea).
- `.conf`: rechazar `node_modules` no cubre un `link` a un directorio que es a su vez un paquete del workspace (p. ej. un `packages/local` ignorado con su propio `package.json`): `pnpm install` crearía su `node_modules` a través del symlink en el checkout principal. Opciones: rechazar el enlace de directorios que contengan un `package.json`, o no instalar cuando hay enlaces a directorios.
- Versionar cada skill por separado con release-please cuando haya dos o más skills: un paquete por skill en `release-please-config.json` (tag `<skill>-vX.Y.Z` y changelog propio) y `exclude-paths` en el paquete raíz. Mientras `install.sh` instale el kit completo, esa versión solo informa.
- `th-wt new`/`checkout`: ramas distintas con el mismo nombre normalizado (`feature/a-b` y `feature-a/b` → `feature-a-b`) chocan; la segunda sale con «destination already exists» sin decir qué rama ocupa la ruta.
- Unir las consultas a `origin` (`ls-remote`) en una sola llamada con el estado comprobado.
- Lint de skills más estricto: `description`, `disable-model-invocation` en los skills con efectos secundarios e invocaciones de scripts sin la ruta completa.
- `install.sh`: soportar más agentes: Pi y GitHub Copilot (hoy solo `claude` y `agy`).
- `install.sh --link-here` desde un worktree: detectarlo (`git rev-parse --git-dir` distinto de `--git-common-dir`) y salir con `4`; hoy solo lo advierte el README.
- Un instalador que descargue el proyecto y copie solo lo necesario, en vez de enlazar un clon (hoy `install.sh --link-here` deja el kit atado al clon).
- `install.sh`: ofrecer instalar codegraph si no está instalado, con un flag explícito (p. ej. `--with-codegraph`), sin prompts y sin volverlo obligatorio: el kit sigue funcionando sin él.
- Registro de la base de cada worktree (en `~/.worktrees/<owner>/<repo>/`) para soportar ramas apiladas sin PR y mostrar el árbol del stack en `list`.
- `th-wt list`: con `$HOME` como repo de dotfiles, un worktree sin `.git` informa el estado de ese repo (`git status` sube por los directorios padre) en lugar de `dirty: null`.
- `th-wt list --remote`: cruzar PRs por rama sin límite, con una sola consulta GraphQL que busque cada rama.
- Varias cuentas o hosts de GitHub: hoy `list --remote` consulta `gh` con `owner/repo` (github.com, o `GH_HOST` para Enterprise) y no entiende alias SSH. Idea: un configurador propio de multicuentas (una o varias keys por cuenta) en el directorio de configuración, que resuelva cuenta y host por repo (#8).
- `th-wt list --remote` con un fork como `origin` (los PRs viven en el repo `upstream`): hoy todas las ramas salen con `pr: null` y sin aviso. Resolverlo consultando también `upstream`.
- `th-wt close <rama>` de una rama que se está rebasando en otro worktree: ese worktree sale `detached` en el porcelain, así que `close` no lo cuenta y puede borrar la rama a mitad del rebase; detectarlo (`rebase-merge/head-name` o `rebase-apply/head-name` del worktree) y conservarla.
- `th-wt close`: si la rama recibe un commit entre la lectura del `oid` y `list_rows`, el plan puede describir `merged` del commit nuevo y `unpushed` del anterior (el borrado sigue protegido por `update-ref`). Calcular `merged` sobre el `oid`.
- `th-wt close`: ejecuta `git status` dos veces en el worktree (para `dirty` y para `ignored`); sacar los dos de una sola pasada con `--ignored`.
- `th-wt close`: el plan no ve worktrees bloqueados (`git worktree lock`) ni con submódulos; promete borrar y `--yes` sale con 4 (con lock, `--force` tampoco basta: git pide `-f -f`). Leer `locked` del porcelain en `list_rows` y mostrarlo en el plan.
- `th-wt close` de una rama huérfana sin commits (`worktree add --orphan`): sale con 4 «no worktree» aunque `list` la muestra.
- `th-wt close --remote`: hace `ls-remote`, `fetch` y `gh pr list` antes de comprobar que la rama tiene un worktree bajo la raíz; una rama que existe sin worktree gasta la red y, sin red o sin `gh`, falla con ese error en vez de «no worktree». Comprobar el worktree primero.
- `th-wt close`: lee `git worktree list --porcelain` dos veces (en `list_rows` y para saber si la rama está en otro worktree); devolverlo desde `list_rows` en una sola pasada.
- `th-wt list --remote`: `ahead` sale `null` cuando el último commit del PR no está en local, algo común si se usó «Update branch» o se aceptó una sugerencia de review en GitHub antes del merge. Resolverlo trayendo `refs/pull/<n>/head` (solo objetos) para esas ramas.
- `th-wt list --remote`: el texto «PR head not fetched» también sale cuando el PR no trae su último commit (`headRefOid` ausente); usar un mensaje que no sugiera hacer fetch.
- `th-wt list --remote`: `ls-remote`, `fetch` y `gh pr list` son independientes y hoy corren en serie; lanzar `gh pr list` en segundo plano mientras se hace el fetch.
- Desactivar también los credential helpers interactivos (p. ej. `GCM_INTERACTIVE=never` para Git Credential Manager), que pueden abrir el navegador aunque `GIT_TERMINAL_PROMPT=0`.
- Resolver el comando ssh por proceso `git` (p. ej. un wrapper en `GIT_SSH_COMMAND` que lea `core.sshCommand` del directorio actual y añada `BatchMode=yes`), en vez de fijar el valor del repo para toda la ejecución: así los `git` que lanzan `pnpm` / `npm` conservan su propia configuración.
- `th-wt list`: un proceso `jq` por worktree; unirlos en una sola llamada si hay decenas de worktrees. Con `--remote` suma otros dos por rama no contenida y el aviso del límite relee todas las filas: armar un mapa rama → PR más reciente con una sola llamada a `jq` antes del bucle.
- `th-wt list --remote` y `close --remote`: solo informan el PR más reciente de cada rama, así que un PR nuevo mergeado puede ocultar otro abierto de la misma rama contra otra base. Mostrar los PRs abiertos aunque haya uno más reciente mergeado.
- `th-wt list --remote`: consulta `origin` y GitHub aunque no haya worktrees bajo la raíz (y falla con 4 si las credenciales son malas). Comprobar antes si hay filas.
- CI: shellcheck usa la versión que trae `ubuntu-latest` (0.9) y en local la 0.11; fijar la versión (binario descargado con checksum) si un aviso nuevo hace diferir ambos.
- Test de `list --remote` con el fetch fallando: fuerza el fallo con un archivo `.lock`, que solo bloquea con el backend de refs `files`. Cuando `reftable` sea el predeterminado de git, condicionarlo con `git rev-parse --show-ref-format` o buscar otra forma de hacer fallar el fetch.
- `th-wt list` y mayúsculas: el prefijo de la raíz distingue mayúsculas, pero APFS no; un cambio de capitalización en la URL de `origin` oculta worktrees existentes. Resolverlo canonicalizando la capitalización de la raíz y de la URL.
- Secretos en los worktrees: #7 solo enlaza (también `.env`) y `pr` no aplica el `.conf`, así que un worktree no puede tener valores propios (otro puerto, otra base de datos). Buscar una forma segura de gestionarlos y compartirlos entre worktrees (p. ej. un gestor de secretos que inyecte las variables al ejecutar), sin multiplicar copias en disco ni exponerlas al agente.
- `copy` en el `.conf` del repo (#7 solo tiene `link`), para archivos que necesitan valores propios por worktree, prohibiendo `.env*` y una lista de nombres de secretos (`*.pem`, `*.key`, `id_rsa*`, `*.p12`, `.netrc`, `.npmrc`, `credentials*`…). Solo si aparece un caso de uso que no sea un secreto; la lista nunca está completa.
- MCP de documentación: un servidor MCP al que se le enlaza la documentación local (p. ej. `.wiki`) y que responde preguntas sobre ella con otro modelo o agente, para ahorrar tokens del modelo principal. Podría reemplazar o complementar `th-repo-context` (v0.2).
- `th-wt checkout` de una rama abierta en un worktree «prunable» (directorio borrado a mano): sale con 4 y da una ruta que ya no existe; sugerir `git worktree prune`.
- `th-wt checkout`: una rama en rebase o bisect en otro worktree sale `detached` en el porcelain, así que pasa la comprobación y `git worktree add` falla con 1; detectarla y salir con 4 y la ruta.
- `th-wt checkout --remote`: hace `ls-remote` y luego `fetch` (dos conexiones a `origin`); probar primero el fetch y usar `ls-remote` solo si falla, para distinguir «no existe» de «inaccesible».
- Cinco lecturas del porcelain de `git worktree list` (`check_root_overlap`, `read_repo_conf` y `list_rows` en `lib.sh`, `close` y `find_worktree_for_branch` de `checkout`): unificarlas en un helper de `lib.sh` que salga con 1 y `git worktree list failed` si git falla. Hoy solo lo hacen `check_root_overlap` y `list_rows`; si git falla entre una llamada y otra, `close --yes` cuenta 0 worktrees con la rama (`|| true`) y la borra aunque siga abierta en otro worktree, `read_repo_conf` sale con 128 sin mensaje `th-wt:` (antes de crear nada) y `checkout` sale con 128 sin mensaje `th-wt:`.
- `th-wt list`/`close`: `default` es el nombre corto `origin/<rama>` (ambiguo si existe una rama o tag local con ese nombre); usar `refs/remotes/origin/<rama>` como ya hacen `new` y `checkout`.
- `th-wt close` conserva la rama por defecto de `origin`, pero no otras de larga vida (`develop`, `release/*`), que borra si están contenidas; declararlas por repo en la configuración (#8).
- Skill `th-pair-lead` (nombre tentativo): el agente principal hace de TL y delega cada ciclo TDD a un subagente «driver» (definido en `.claude/agents/`, con modelo y esfuerzo propios). Aprendizajes de la story 3, donde se probó a mano:
  - Haiku sirve para refactors mecánicos con la spec cerrada; Sonnet, para TDD con casos de borde y criterio propio.
  - Un commit por paso, nunca pedir varios pasos en tanda: si no, el refactor se mezcla con el fix y no se puede separar.
  - Exigir que el test se escriba antes que el código: el RED obtenido corriendo el test contra el código viejo es un TDD menos estricto.
  - Incluir en la lista de tests inicial los casos de borde (directorio borrado, estado desconocido, archivos ignorados, rama en dos worktrees); en la story 3 aparecieron recién en los reviews y costaron dos rondas extra.
  - Tras cada review, mostrar el triage (corregir ahora o mandar a Ideas) y esperar la aprobación del usuario antes de delegar los fixes.
  - Los subagentes son una extensión de Claude Code: el skill debe seguir funcionando en Antigravity si la ignora (§4 del plan), por ejemplo haciendo el ciclo el propio agente.
