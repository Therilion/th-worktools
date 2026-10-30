# th-worktools

Kit personal de skills y scripts para agentes de código, compatible con **Claude Code** y **Antigravity CLI**. Sigue el estándar Agent Skills (`SKILL.md`) y funciona en macOS y Linux.

> **Estado:** en desarrollo, hacia la v0.1. Todavía no hay nada instalable.

## Principios

- **No escribe en tus repos.** Todo vive en el kit, en `~/.config/th-worktools/` o en `~/.worktrees/`.
- **Dry-run por defecto.** Las acciones con efectos secundarios solo muestran el plan; `--yes` las ejecuta.
- **Herramientas externas opcionales.** Se usan si están instaladas y se omiten si no.
- **Secretos protegidos.** Los archivos `.env*` solo se tocan si lo configuras, y los scripts nunca imprimen su contenido.

## v0.1: `th-worktree`

Crea, lista y cierra git worktrees en `~/.worktrees/<owner>/<repo>/<rama>`, para trabajar en paralelo sin tocar el checkout principal.

| Subcomando | Qué hace |
|---|---|
| `new <rama> [--base <rama>]` | Worktree con una rama nueva |
| `checkout <rama>` | Worktree de una rama existente, local o remota |
| `pr <n>` | Worktree de un PR de GitHub en `pr-reviews/pr-<n>/code` |
| `list` | Worktrees del repo actual, con su estado |
| `close <rama\|pr-<n>>` | Cierra el worktree; requiere `--yes` |

Al crear un worktree:

- instala las dependencias según el lockfile (pnpm o npm);
- enlaza o copia los archivos ignorados que declares por repo (por ejemplo, `.wiki` o `.env`);
- inicializa codegraph si está instalado.

Se usa desde Claude Code (`/th-worktree new feature/login`), desde Antigravity en lenguaje natural o desde la terminal con `th-wt`.

## Requisitos

- Requeridos: `git`, `jq`, bash 3.2 o superior.
- Para PRs: `gh`.
- Opcional: `codegraph`.

## Hoja de ruta

| Versión | Contenido |
|---|---|
| v0.1 | `th-worktree`, instalación y CI |
| v0.2 | `th-repo-context`: índice de la documentación del repo, generado al vuelo |
| v0.3 | `th-pr-review`: revisión de PRs con mutation testing limitado al diff |
| v0.4 | `th-integration-context`: contexto compartido entre repos |

El detalle de las decisiones está en [`docs/plan-v0.1.md`](docs/plan-v0.1.md).

Las ramas de cada historia se integran en `main` con un merge commit hasta la historia 5; a partir de la historia 6 (`#6` del backlog) se integran con squash.

## Ideas

Ideas que quedan fuera de la versión en curso.

- Derivar `<owner>/<repo>` también de remotes `ssh://`, con puerto o con barra final (hoy solo `git@host:` y `https://`).
- Que `--base` acepte tags y SHAs (hoy es siempre `origin/<rama>`).
- Resumen legible de `new` en la terminal, sin necesidad de `--json`.
- Evitar prompts interactivos de git en la terminal (`GIT_TERMINAL_PROMPT=0`) sin pisar el `core.sshCommand` del usuario.
- Unir las consultas a `origin` (`ls-remote`) en una sola llamada con el estado comprobado.
- `th-wt new --help` y `th-wt list --help` (hoy salen con código 2) y mensajes de uso que nombren el argumento erróneo.
- Lint de skills más estricto: `description`, `disable-model-invocation` en los skills con efectos secundarios e invocaciones de scripts sin la ruta completa.
- Registro de la base de cada worktree (en `~/.worktrees/<owner>/<repo>/`) para soportar ramas apiladas sin PR y mostrar el árbol del stack en `list`.
- `th-wt list` y symlinks: la raíz se compara con las rutas reales de git sin resolver symlinks; si `~/.worktrees` o `$HOME` son symlinks (o `$HOME` termina en `/`), la lista sale vacía sin aviso. Canonicalizar ambos lados al hacer la raíz configurable (#8).
- `th-wt list`: con `$HOME` como repo de dotfiles, un worktree sin `.git` informa el estado de ese repo (`git status` sube por los directorios padre) en lugar de `dirty: null`.
- `th-wt list --remote`: límite de PRs consultados configurable (hoy fijo en 100), al implementar la configuración (#8).
- `th-wt list --remote`: cruzar PRs por rama sin límite, con una sola consulta GraphQL que busque cada rama.
- Varias cuentas o hosts de GitHub: hoy `list --remote` consulta `gh` con `owner/repo` (github.com, o `GH_HOST` para Enterprise) y no entiende alias SSH. Idea: un configurador propio de multicuentas (una o varias keys por cuenta) en el directorio de configuración, que resuelva cuenta y host por repo (#8).
- Unificar el código de salida de los errores de red entre subcomandos: hoy `new` sale con `1` si no puede leer `origin` y `list --remote` con `4`.
- `th-wt list --remote` con un fork como `origin` (los PRs viven en el repo `upstream`): hoy todas las ramas salen con `pr: null` y sin aviso. Resolverlo consultando también `upstream`.
- `th-wt close` de un worktree con HEAD desacoplado (rebase o bisect a medias): hoy sale con 4 «no worktree», porque `close` busca por rama. Permitir cerrarlo por ruta.
- `th-wt close`: si la rama recibe un commit entre la lectura del `oid` y `list_rows`, el plan puede describir `merged` del commit nuevo y `unpushed` del anterior (el borrado sigue protegido por `update-ref`). Calcular `merged` sobre el `oid`.
- `th-wt close`: ejecuta `git status` dos veces en el worktree (para `dirty` y para `ignored`); sacar los dos de una sola pasada con `--ignored`.
- `th-wt close`: el plan no ve worktrees bloqueados (`git worktree lock`) ni con submódulos; promete borrar y `--yes` sale con 4 (con lock, `--force` tampoco basta: git pide `-f -f`). Leer `locked` del porcelain en `list_rows` y mostrarlo en el plan.
- `th-wt close` de una rama huérfana sin commits (`worktree add --orphan`): sale con 4 «no worktree» aunque `list` la muestra.
- `th-wt close`: lee `git worktree list --porcelain` dos veces (en `list_rows` y para saber si la rama está en otro worktree); devolverlo desde `list_rows` en una sola pasada.
- `th-wt list --remote`: `ahead` sale `null` cuando el último commit del PR no está en local, algo común si se usó «Update branch» o se aceptó una sugerencia de review en GitHub antes del merge. Resolverlo trayendo `refs/pull/<n>/head` (solo objetos) para esas ramas.
- `th-wt list --remote`: el texto «PR head not fetched» también sale cuando el PR no trae su último commit (`headRefOid` ausente); usar un mensaje que no sugiera hacer fetch.
- `th-wt list --remote`: `ls-remote`, `fetch` y `gh pr list` son independientes y hoy corren en serie; lanzar `gh pr list` en segundo plano mientras se hace el fetch.
- `th-wt list`: si `git worktree list` falla, el script sale con el código crudo de git (128) y sin mensaje `th-wt:`; debería salir con 1.
- `th-wt list`: un proceso `jq` por worktree; unirlos en una sola llamada si hay decenas de worktrees. Con `--remote` suma otros dos por rama no contenida y el aviso del límite relee todas las filas: armar un mapa rama → PR más reciente con una sola llamada a `jq` antes del bucle.
- `th-wt list --remote`: solo informa el PR más reciente de cada rama, así que un PR nuevo mergeado puede ocultar otro abierto de la misma rama contra otra base. Mostrar los PRs abiertos aunque haya uno más reciente mergeado.
- `th-wt list --remote`: consulta `origin` y GitHub aunque no haya worktrees bajo la raíz (y falla con 4 si las credenciales son malas). Comprobar antes si hay filas.
- Test de `list --remote` con el fetch fallando: fuerza el fallo con un archivo `.lock`, que solo bloquea con el backend de refs `files`. Cuando `reftable` sea el predeterminado de git, condicionarlo con `git rev-parse --show-ref-format` o buscar otra forma de hacer fallar el fetch.
- `th-wt list` en la terminal (#11): el texto va solo a stderr, así que `th-wt list | grep` no recibe nada; mandar las filas a stdout y dejar solo los avisos en stderr.
- `th-wt list` y mayúsculas: el prefijo de la raíz distingue mayúsculas, pero APFS no; un cambio de capitalización en la URL de `origin` oculta worktrees existentes. Resolverlo junto con los symlinks (#8).
- `th-wt list` y archivos ignorados: `dirty` no cuenta los ignorados por git; decidir qué significa «limpio» cuando `new` copie `.env` (#7).
- Skill `th-pair-lead` (nombre tentativo): el agente principal hace de TL y delega cada ciclo TDD a un subagente «driver» (definido en `.claude/agents/`, con modelo y esfuerzo propios). Aprendizajes de la story 3, donde se probó a mano:
  - Haiku sirve para refactors mecánicos con la spec cerrada; Sonnet, para TDD con casos de borde y criterio propio.
  - Un commit por paso, nunca pedir varios pasos en tanda: si no, el refactor se mezcla con el fix y no se puede separar.
  - Exigir que el test se escriba antes que el código: el RED obtenido corriendo el test contra el código viejo es un TDD menos estricto.
  - Incluir en la lista de tests inicial los casos de borde (directorio borrado, estado desconocido, archivos ignorados, rama en dos worktrees); en la story 3 aparecieron recién en los reviews y costaron dos rondas extra.
  - Tras cada review, mostrar el triage (corregir ahora o mandar a Ideas) y esperar la aprobación del usuario antes de delegar los fixes.
  - Los subagentes son una extensión de Claude Code: el skill debe seguir funcionando en Antigravity si la ignora (§4 del plan), por ejemplo haciendo el ciclo el propio agente.
