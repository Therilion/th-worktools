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
- `th-wt list`: si `git status` falla en un worktree (`.git` borrado o índice dañado), hoy se muestra como `clean`; debería ser `dirty: null`. Con `$HOME` como repo de dotfiles, git podría informar el estado de ese repo.
- `th-wt list`: si `git worktree list` falla, el script sale con el código crudo de git (128) y sin mensaje `th-wt:`; debería salir con 1.
- `th-wt list`: un proceso `jq` por worktree; unirlos en una sola llamada si hay decenas de worktrees.
