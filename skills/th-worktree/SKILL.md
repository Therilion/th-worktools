---
name: th-worktree
description: Crea un git worktree para una rama nueva en ~/.worktrees, sin tocar el checkout principal, y lista los worktrees del repo con su estado, también contra origin y los PRs de GitHub. Úsalo solo cuando el usuario pida explícitamente crear o listar worktrees.
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

Argumentos recibidos: $ARGUMENTS

## Reglas

- Al terminar `new`: informar la ruta y sugerir abrir una sesión nueva del agente ahí.
- Al terminar `list`: mostrar por cada worktree la rama, la ruta, si tiene cambios sin commitear (`dirty`) y si está contenida en la rama por defecto de `origin` (`merged`). `branch: null` es un HEAD desacoplado (rebase, bisect o checkout de un commit); `missing: true` es un directorio borrado; `merged: null` es que no se pudo saber (falta `origin/HEAD` local, apunta a una rama que ya no existe —se arregla con `git remote set-head origin -a`— o la rama no tiene commits); `dirty: null` es que no se pudo leer el estado (`git status` falló o el directorio no existe), así que no lo des por limpio.
- Sin `--remote`, `list` usa solo datos locales: `merged` no ve merges con squash o rebase y puede estar desactualizado si no se hizo fetch. No lo presentes como confirmación de que se puede cerrar.
- Usa `--remote` cuando el usuario quiera saber qué puede cerrar. Hace fetch de la rama por defecto de `origin`, actualiza `origin/HEAD` local y consulta con `gh` los PRs del repo. Necesita `gh` autenticado y acceso a `origin`: si falta algo, sale con error y no hay lista local de respaldo; no reintentes sin `--remote` salvo que el usuario lo pida.
- Con `--remote`, `merged` sigue siendo solo contención en git (ya contra el `origin` actual). Cada worktree trae además `pr`, que se lee junto a `merged`:
  - `pr: null` en una rama contenida: no se consultó el PR, ya está integrada. En una rama no contenida: no tiene PR, o su PR es anterior a los 100 más recientes (en ese caso `list` avisa por stderr: repítelo al usuario).
  - `pr.state` `MERGED` con `ahead: false`: el PR se mergeó (con squash, rebase o contra otra base) y no hay trabajo local posterior; la rama se puede cerrar aunque `merged` sea `false`.
  - `pr.ahead: true`: la rama local tiene commits posteriores al último commit del PR; no cuenta como mergeada. Avisa al usuario antes de sugerir cerrarla.
  - `pr.ahead: null`: el último commit del PR no está en local, así que no se sabe; no la des por mergeada y avisa al usuario.
  - `pr.state` `OPEN` o `CLOSED`: no está mergeada.
  - Aun con el PR mergeado, mira `dirty` antes de sugerir cerrar.
- Código de salida `3`: informar qué dependencia falta y detenerse.
- Código de salida `4`: mostrar el motivo y preguntar al usuario cómo seguir.
- Cualquier otro código (`1`, `2`…): mostrar el stderr al usuario y detenerse; no reintentar.
