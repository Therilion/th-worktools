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

Hoy, al crear un worktree con `new` o `checkout` se crean el worktree y la rama, se enlazan los archivos ignorados que declares por repo en `~/.config/th-worktools/repos/<owner>/<repo>.conf` y, para todos los repos de una organización, en `~/.config/th-worktools/repos/<owner>.conf` (se lee primero; por ejemplo, `link .wiki` o `link .env`, `link? .wiki` para enlazar solo si existe y ni el checkout principal ni la rama la versionan, `deps-prefix <comando>` para anteponer un ejecutable del `PATH` al comando de instalación y `keep <rama>` para que `close` conserve ramas de larga vida como `develop` o `release/*`; ver [`examples/config/repos/mi-org/mi-repo.conf`](examples/config/repos/mi-org/mi-repo.conf) y [`examples/config/repos/mi-org.conf`](examples/config/repos/mi-org.conf)) y se instalan las dependencias según el lockfile: `pnpm-lock.yaml` → `pnpm install --frozen-lockfile`, `package-lock.json` → `npm ci`. `pr` nunca enlaza ni instala dependencias: el código del PR es de un tercero (con las dependencias, avisa con el comando para hacerlo a mano). Si agregas una línea a un `.conf` después, `th-wt link <rama>` la re-aplica a un worktree ya abierto: crea los enlaces que faltan, con las mismas validaciones, y no borra nada.

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

El detalle de las decisiones está en [`docs/plan-v0.1.md`](docs/plan-v0.1.md) y la guía de desarrollo y tests en [`docs/desarrollo.md`](docs/desarrollo.md). Las ideas que quedan fuera de la versión en curso están en [`docs/ideas.md`](docs/ideas.md).

Las ramas de cada historia se integran en `main` con un merge commit hasta la historia 5; a partir de la historia 6 se integran con squash.
