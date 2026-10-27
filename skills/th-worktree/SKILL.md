---
name: th-worktree
description: Crea un git worktree para una rama nueva en ~/.worktrees, sin tocar el checkout principal, y lista los worktrees del repo con su estado. Úsalo solo cuando el usuario pida explícitamente crear o listar worktrees.
disable-model-invocation: true
---

# th-worktree

Ejecuta el script siempre con la ruta completa de la tabla: no está en el PATH y el comando corre desde el repo del usuario, no desde la carpeta de este SKILL.md.

## Subcomandos

| Pedido del usuario | Comando |
|---|---|
| Crear rama nueva | `"${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt" new <rama> [--base <rama>] --json` |
| Ver worktrees | `"${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt" list --json` |

Argumentos recibidos: $ARGUMENTS

## Reglas

- Al terminar `new`: informar la ruta y sugerir abrir una sesión nueva del agente ahí.
- Al terminar `list`: mostrar por cada worktree la rama, la ruta, si tiene cambios sin commitear (`dirty`) y si está contenida en la rama por defecto de `origin` (`merged`). `missing: true` es un directorio borrado; `merged: null` es que no se pudo saber (falta `origin/HEAD` local).
- `merged` usa solo datos locales: no ve merges con squash o rebase y puede estar desactualizado si no se hizo fetch. No lo presentes como confirmación de que se puede cerrar.
- Código de salida `3`: informar qué dependencia falta y detenerse.
- Código de salida `4`: mostrar el motivo y preguntar al usuario cómo seguir.
- Cualquier otro código (`1`, `2`…): mostrar el stderr al usuario y detenerse; no reintentar.
