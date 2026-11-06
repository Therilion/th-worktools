# th-worktools — agent instructions

Public kit of skills (`SKILL.md` standard) and scripts for Claude Code and Antigravity CLI. Current version: v0.1, with the `th-worktree` skill plus `install.sh`, `verify.sh` and CI.

- Before changing anything, read `docs/plan-v0.1.md`. The decisions live there; don't reopen them without asking.
- Pending work: `BACKLOG.md` (temporary, deleted when v0.1 closes).

## Stack

- Bash 3.2 compatible, portable between macOS (BSD) and Linux (GNU). Constraints in §6 of the plan.
- Required dependencies: `git`, `jq`. `gh` only for GitHub features. `codegraph` is optional: used if installed, skipped if not.
- CI: GitHub Actions with a `macos-latest` + `ubuntu-latest` matrix.

## Rules

- Before calling anything done: run `shellcheck` on the scripts, `tests/lint-skills.sh` and `tests/smoke.sh`.
- CI runs shellcheck 0.9.0, which flags things a newer local version may not (e.g. SC2015 on `A && B || C`; write `{ A && B; } || C`). Write for 0.9.0, and if the local version differs, don't treat a local pass as proof.
- Never add real work data (organizations, repos, paths, tickets). The repo is public; `examples/config/` holds only fictitious values.
- Nothing is written to the repos where the kit is used: everything lives in the kit, in `~/.config/th-worktools/` or in `~/.worktrees/`.
- Scripts: `set -euo pipefail`, no interactive prompts, dry-run by default and `--yes` to execute. Messages go to stderr; `--json` writes a single object to stdout. Exit codes per §5 of the plan.
- Network access is opt-in: subcommands stay offline (no `git fetch` or `ls-remote`, no `gh`) unless a flag like `--remote` asks for it. Exception: `new` and `pr` always read origin, since `new` creates the branch from `origin/<base>` and `pr` fetches the PR head and its base. Besides git's own fetch bookkeeping (`FETCH_HEAD`), the only refs written outside the kit are the `refs/remotes/origin/<branch>` that those fetches update; never touch `origin/HEAD`. Installing dependencies (`pnpm`/`npm`) in `new`, `checkout` and `pr` also uses the network, so `checkout` without `--remote` is not fully offline.
- Never print the contents of `.env*` files or sensitive config; only file names. Config is parsed line by line, never with `source`.
- Bash 3.2 trap: never put `case … esac` inside `$( … )` (3.2 mis-parses the `)` of the patterns); move it to a function.
- Script paths in `SKILL.md`: always with `${CLAUDE_SKILL_DIR:-$HOME/.local/share/th-worktools/skills/<skill>}`, never bare relative paths.
- Language: script messages (stderr, `--help`) and commit messages in English; `SKILL.md`, README, docs and test names in Spanish.
- Skills don't share files with each other.
- Scope: only what the current version's DoD requires. New ideas go to the "Ideas" section of the README, not to the code.

## Git conventions

- Don't commit or push on your own initiative; only when asked.
- Commit messages follow Conventional Commits (`feat`, `fix`, `refactor`, `docs`, `test`, `chore`), in English, with a subject of 72 characters max.
- Story branches are merged into `main` with a merge commit up to story 5; from story 6 (backlog #6) on, with squash (so keep the PR title in Conventional Commits format).
- Never add `Co-Authored-By` or any AI attribution, in commits or PRs.
