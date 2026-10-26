---
name: th-worktree
description: Crea un git worktree para una rama nueva en ~/.worktrees, sin tocar el checkout principal. Úsalo solo cuando el usuario pida explícitamente crear un worktree.
disable-model-invocation: true
---

# th-worktree

Script (ruta relativa a la carpeta de este SKILL.md, no al repo actual):

`"${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/th-worktree}/scripts/th-wt"`

## Subcomandos

| Pedido del usuario | Comando |
|---|---|
| Crear rama nueva | `th-wt new <rama> [--base <ref>] --json` |

Argumentos recibidos: $ARGUMENTS

## Reglas

- Al terminar `new`: informar la ruta y sugerir abrir una sesión nueva del agente ahí.
- Código de salida `3`: informar qué dependencia falta y detenerse.
- Código de salida `4`: mostrar el motivo y preguntar al usuario cómo seguir.
