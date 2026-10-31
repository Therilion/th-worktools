---
name: th-worktree
description: Crea un git worktree para una rama nueva en ~/.worktrees, sin tocar el checkout principal, lista los worktrees del repo con su estado, también contra origin y los PRs de GitHub, y cierra un worktree mostrando antes qué se borra. Úsalo solo cuando el usuario pida explícitamente crear, listar o cerrar worktrees.
disable-model-invocation: true
---

# th-worktree

Ejecuta el script siempre con la ruta completa de la tabla: no está en el PATH y el comando corre desde el repo del usuario, no desde la carpeta de este SKILL.md.

## Subcomandos

| Pedido del usuario | Comando |
|---|---|
| Crear rama nueva | `"${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt" new <rama> [--base <rama>] --json` |
| Ver worktrees | `"${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt" list --json` |
| Saber qué worktrees se pueden cerrar | `"${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt" list --remote --json` |
| Cerrar un worktree | `"${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt" close <rama> --json` (ver reglas) |
| Cerrar una rama mergeada con squash, o en otra base | `"${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt" close <rama> --remote --json` (ver reglas) |

Argumentos recibidos: $ARGUMENTS

## Reglas

- Al terminar `new`: informar la ruta y sugerir abrir una sesión nueva del agente ahí.
- `close`: ejecuta primero **sin** `--yes` y muestra el plan al usuario: ruta, rama, `merged`, `dirty`, `unpushed` (commits que no están en ninguna rama de `origin`) y qué se borra (`delete`). Repite el comando con `--yes` solo tras su confirmación explícita.
- `close --force` solo si el usuario lo pide: cierra aunque haya cambios sin commitear o commits sin push, que se pierden con el directorio (la rama no mergeada se conserva). Tras un merge con squash y la rama remota borrada, todos los commits salen como sin push: explícaselo antes de que decida forzar.
- `close --remote`: úsalo cuando `close` conserve la rama o bloquee por commits sin push tras un merge con squash, o cuando `list --remote` muestre un PR `MERGED` con `ahead: false`. Consulta el PR de esa rama (mismos requisitos y errores que `list --remote`: sin `gh` sale `3`, sin acceso `4`, y no se borra nada). Muestra siempre `pr` (número, estado y **base**) antes de pedir confirmación: si la base no es la rama por defecto, el trabajo llegó a otra rama y el usuario debe confirmarlo. Solo un PR `MERGED` con `ahead: false` cambia el plan: los commits sin push están en el PR y no bloquean, y la rama se borra. `dirty` sigue bloqueando. `pr: null` con `merged: true`: la rama ya está contenida y no se consultó el PR (el texto dice `not checked`); no es "sin PR". Con PR `OPEN`/`CLOSED`, sin PR, `ahead: true` o `ahead: null`, el plan es el de `close` sin `--remote`: explica por qué.
- `close`, campos que pueden no ser booleanos: `missing: true` = el directorio ya no existe, cerrar solo limpia el registro de git (no bloquea por `dirty`); `dirty: null` = no se pudo leer el estado, no lo presentes como limpio (bloquea sin `--force`); `merged: null` = desconocido (mismas causas que en `list`), la rama se conserva: transmite la sugerencia `git remote set-head origin -a`.
- `close`, `ignored`: archivos ignorados por git que se borran con el directorio (solo nombres; los directorios salen colapsados, p. ej. `build/`). Muéstraselos al usuario. Nunca bloquean, ni siquiera `.env`. Si incluyen `.env*` u otros archivos que parezcan trabajo local, secretos o configuración (no directorios regenerables como `node_modules/`, `dist/`, `build/`, `.venv/`), pregunta explícitamente por ellos antes de ejecutar `--yes`. `ignored: null` = no se pudieron listar: avisa al usuario de que pueden existir ignorados como `.env` y que `--force` los borraría.
- `close` con `--yes` desde dentro del worktree sale con `4`: repítelo desde el checkout principal.
- Al terminar `list`: mostrar por cada worktree la rama, la ruta, si tiene cambios sin commitear (`dirty`) y si está contenida en la rama por defecto de `origin` (`merged`). `branch: null` es un HEAD desacoplado (rebase, bisect o checkout de un commit); `missing: true` es un directorio borrado; `merged: null` es que no se pudo saber (falta `origin/HEAD` local, apunta a una rama que ya no existe —se arregla con `git remote set-head origin -a`— o la rama no tiene commits); `dirty: null` es que no se pudo leer el estado (`git status` falló o el directorio no existe), así que no lo des por limpio.
- Sin `--remote`, `list` usa solo datos locales: `merged` no ve merges con squash o rebase y puede estar desactualizado si no se hizo fetch. No lo presentes como confirmación de que se puede cerrar.
- Usa `--remote` cuando el usuario quiera saber qué puede cerrar. Hace fetch de la rama por defecto de `origin` (sin tocar `origin/HEAD`, así que `merged` se calcula aunque falte) y consulta con `gh` los PRs del repo. Necesita `gh` autenticado y acceso a `origin`; `gh` consulta github.com, o el host de la variable `GH_HOST` (GitHub Enterprise): si falta algo, sale con error y no hay lista local de respaldo; no reintentes sin `--remote` salvo que el usuario lo pida.
- Con `--remote`, `merged` sigue siendo solo contención en git (ya contra el `origin` actual). Cada worktree trae además `pr`, que se lee junto a `merged`:
  - `pr: null` en una rama contenida: no se consultó el PR, ya está integrada. En una rama no contenida: no tiene PR, o su PR es anterior a los 100 más recientes (en ese caso `list` avisa por stderr: repítelo al usuario).
  - `pr.state` `MERGED` con `ahead: false`: el PR se mergeó en la rama por defecto (con squash o rebase) y no hay trabajo local posterior; la rama se puede cerrar aunque `merged` sea `false`.
  - `pr.state` `MERGED` con `pr.base` distinta de la rama por defecto (por ejemplo, una rama apilada): el trabajo llegó a esa base, no necesariamente a la rama por defecto. Dile al usuario en qué base se mergeó y no lo des por cerrable sin que lo confirme.
  - `pr.ahead: true`: la rama local tiene commits posteriores al último commit del PR; no cuenta como mergeada. Avisa al usuario antes de sugerir cerrarla.
  - `pr.ahead: null`: el último commit del PR no está en local, así que no se sabe; no la des por mergeada y avisa al usuario.
  - `pr.state` `OPEN` o `CLOSED`: no está mergeada.
  - Aun con el PR mergeado, mira `dirty` antes de sugerir cerrar.
- Código de salida `3`: informar qué dependencia falta y detenerse.
- Código de salida `4`: mostrar el motivo y preguntar al usuario cómo seguir.
- Cualquier otro código (`1`, `2`…): mostrar el stderr al usuario y detenerse; no reintentar.
