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
| `new <rama> [--base <ref>]` | Worktree con una rama nueva |
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
