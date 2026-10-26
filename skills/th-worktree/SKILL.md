---
name: th-worktree
description: Crea un git worktree para una rama nueva en ~/.worktrees, sin tocar el checkout principal. Úsalo solo cuando el usuario pida explícitamente crear un worktree.
disable-model-invocation: true
---

# th-worktree

Ejecuta el script siempre con la ruta completa de la tabla: no está en el PATH y el comando corre desde el repo del usuario, no desde la carpeta de este SKILL.md.

## Subcomandos

| Pedido del usuario | Comando |
|---|---|
| Crear rama nueva | `"${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt" new <rama> [--base <rama>] --json` |

Argumentos recibidos: $ARGUMENTS

## Reglas

- Al terminar `new`: informar la ruta y sugerir abrir una sesión nueva del agente ahí.
- Código de salida `3`: informar qué dependencia falta y detenerse.
- Código de salida `4`: mostrar el motivo y preguntar al usuario cómo seguir.
- Cualquier otro código (`1`, `2`…): mostrar el stderr al usuario y detenerse; no reintentar.
