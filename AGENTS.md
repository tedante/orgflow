# AGENTS.md

## What This Repo Is

GitHub Organization automation toolkit for Hacktiv8 lectures. Three bash scripts (the engines) sharing `lib/common.sh` + a Node/Ink TUI front-end that runs them + config files + README guide. No tests.

## Stack

- **Bash** scripts (run with `bash <script>.sh [--dry-run]`, not executable-triggered). Shared helpers live in `lib/common.sh`, sourced by all three — the scripts are no longer standalone files.
- **`gh` CLI** (GitHub CLI) — sole external dependency for the scripts, authenticated with `admin:org` scope
- **Node.js** (>= 18) + **Ink** (React-based TUI) — `src/` front-end; spawned via `tsx` loader, no build step
- npm for JS deps (`package.json` + lockfile)

## Repo Map

| File | Purpose |
|---|---|
| `README.md` | Instructor guide: prerequisites (`gh auth login`, `gh auth refresh -h github.com -s admin:org`), dry-run + usage flow |
| `invite.sh` | Onboard students: ensure org team exists (secret privacy), invite users as `direct_member` linked to team |
| `create-repo.sh` | Bulk provisioning: create private per-student repos from template, isolated write access, reviewers, milestone + issue w/ deadline, feedback PR |
| `clone-repos.sh` | Clone all cohort repos: for each `TEMPLATES` entry, clone `TEAM_NAME-<template>-<user>` repos into `$CLONE_DIR/<template>/<repo>/` (`CLONE_DIR` optional, default current dir), only for `USERS` and only if the repo exists in the org. Only needs read access — no `admin:org` |
| `lib/common.sh` | Shared helpers sourced by all three scripts: `orgflow_bootstrap` (args/config/list→array/`ORGFLOW_TEMPLATES`), `orgflow_require_set`/`orgflow_require_count`, `orgflow_check_gh`/`orgflow_check_admin_org`, `split_template`, `clean_repo_name`, `ensure_team`. Also holds `ORGFLOW_TEAM_PRIVACY` (single source of truth for team visibility) |
| `orgflow.conf` (git-ignored) | Shared config for all three scripts — `USERS`, `ORG`, `TEAM_NAME`, `REVIEWERS`, `TEMPLATES`, `CLONE_DIR` |
| `orgflow.conf.example` | Committed template; copy to `orgflow.conf` and edit |
| `src/index.jsx` | TUI entry: fullscreen bordered frame (sized to the terminal), status bar (config + `gh` auth), centered action menu, template picker, streamed `--dry-run` preview → `y`/`n` confirm → run view |
| `src/config.js` | Parses `orgflow.conf` (bash `KEY="value"` + `KEY=(...)` array format) for display |
| `src/runner.js` | `spawn` wrapper: runs bash scripts / `gh`, streams stdout+stderr lines, resolves `{code, lines}` |

## Config Conventions

- Single shared config: `orgflow.conf` at repo root, `source`d by `orgflow_bootstrap` (lib/common.sh). **Git-ignored** — cohort data is local, never committed.
- `CONFIG_FILE` env var overrides the config path (used for testing/previews).
- `USERS` and `REVIEWERS` are **plain strings** (space/newline-separated, no quotes — paste as-is). `orgflow_bootstrap` converts them to arrays right after `source` (`USERS_ARR=($USERS); USERS=("${USERS_ARR[@]}")`). Safe because GitHub username charset is `[a-zA-Z0-9-]` — no glob characters.
- `ORG` target org (all three scripts — invite.sh, create-repo.sh, clone-repos.sh), `TEAM_NAME` cohort id (both; prefixes repo names), `TEMPLATES=()` with `repo|YYYY-MM-DD HH:MM` deadline format (create-repo.sh only) — the org is taken from `ORG`, so templates list only the repo name. `TEMPLATES` must stay an array — each entry contains a space (`|` separator).
- `clone-repos.sh` does not use `REVIEWERS` — it derives repo names from `TEAM_NAME` + `TEMPLATES` + `USERS`. Only requires existing org access — no `admin:org` scope check, matching its read-only contract.

## CLI Contract

- `bash <script>.sh --dry-run` prints the execution plan and exits 0 — **zero `gh` API calls**. Keep dry-run as an early-exit summary block, not a `gh` wrapper (wrapping breaks `$(gh api -q ...)` substitution and triggers false errors).
- `ORGFLOW_TEMPLATES` env var (create-repo.sh + clone-repos.sh): semicolon-separated template entries that **replace** `TEMPLATES` right after `source` — lets the TUI filter which templates run. Semicolon separator because entries contain spaces (deadline). Optional — unset = process all templates.
- Real mode exits non-zero on: missing config file, empty required vars (`USERS`/`ORG`/`TEAM_NAME`/`TEMPLATES`), malformed deadline (regex `YYYY-MM-DD HH:MM`), or missing auth (`gh` not installed / no `admin:org` scope). `REVIEWERS` is **optional** — empty means no reviewers are assigned. Missing/null deadline is a warning, not an error — milestone/issue creation is skipped, matching legacy behavior.
- New validation must run before the dry-run exit block so dry-run never sees invalid config.

## Critical Invariants (do not break)

1. **Repo isolation is intentional.** Students get `write` (push) only to their own repo. Reviewers get `maintain`. Team membership is **never** granted repo access (see `# 🔒 REMOVED STEP 2c ENTIRELY` comment in `create-repo.sh`).
2. **Idempotency / self-healing** — scripts must be safe to re-run: membership checked before invite, team existence checked before create, duplicate invite treated as notice not error. **Known gap:** `create-repo.sh` skips an existing repo wholesale (`continue`), so a run that died after repo creation but before the feedback PR is *not* healed on re-run — that repo's collaborators, milestone, and PR are never retried.
3. **GitHub API timing** — `sleep 5` after repo/team creation exists because GitHub indexes asynchronously. The team-side sleep lives in `ensure_team` (lib/common.sh). Don't remove without evidence.
4. **Variable bleed protection** — `create-repo.sh` resets `NEW_REPO`/`SHA`/`MILESTONE_NUMBER` etc. per iteration. Preserve this pattern in any new per-user loop.
5. **Deadline format** — `YYYY-MM-DD HH:MM` converted to ISO `T...:00+07:00` (WIB) for milestone `due_on`. Keep the `+07:00` offset.

## Common Operations

- New cohort: `cp orgflow.conf.example orgflow.conf`, edit, then `bash <script>.sh --dry-run` → `bash <script>.sh`
- TUI: `npm start` — three actions from one menu; every action auto-previews via `--dry-run` first, then asks for `y`/`n` confirmation before real execution
- Re-run after partial failure: safe — scripts skip what already exists
- Check script syntax: `bash -n <script>.sh`

## TUI Conventions

- `src/` is a **UI layer only** — it spawns the bash scripts via `runner.js`, never re-implements provisioning logic. Keep it that way: the scripts hold the GitHub API logic and its invariants.
- Run scripts with `cwd: PROJECT_ROOT` and inherited env so they resolve `orgflow.conf` themselves. Pass `CONFIG_FILE` env var for previews/tests.
- Real-mode execution must keep the `y`/`n` confirm gate before `startRun`. The flow is: select action → (optional) template picker → preview via `--dry-run` → `y` execute / `n` back. No separate DRY-RUN menu items.
- Create/Clone menu items route through a multi-select template picker (when `TEMPLATES` > 1); selection is passed to the script as `ORGFLOW_TEMPLATES` env (`;`-separated raw entries). Single template skips the picker.
- New bash config vars are picked up by `src/config.js` — extend the parser there if the format changes.

## Security Notes

- Scripts call GitHub API with caller's authenticated identity — requires `admin:org` permission. Don't downgrade silently.
- Usernames in config files are **intentional config**, not secrets. Configs are git-ignored to keep cohort data out of history anyway.
- Scripts contain no secrets. Never add tokens/keys to these files; they go in `gh` auth, not the repo.

## Coding Rules

- Match existing style: uppercase config vars, `echo` banner sections, `gh api` over raw curl, `--silent` on mutation calls, if-blocks with explicit `exit 1` (no `set -e`).
- Bootstrap pattern lives in `lib/common.sh`: each script sets `SCRIPT_DIR`, guards `lib/common.sh` exists, sources it, then calls `orgflow_bootstrap "$@"` (arg parse → `CONFIG_FILE` resolution own-dir-first → `source` → list→array → `ORGFLOW_TEMPLATES`). After that: per-script pre-flight validation → dry-run block → `orgflow_check_gh` / `orgflow_check_admin_org` → flow.
- **Single definition per rule.** Template parsing (`split_template`), repo-name cleaning (`clean_repo_name`), team creation (`ensure_team`), and auth checks exist only in `lib/common.sh` — never re-inline them. Duplicated copies previously drifted (team privacy `secret` vs `closed`; dry-run vs real repo-name parsing). `ORGFLOW_TEAM_PRIVACY` is the single source of truth for team visibility.
- The dry-run block stays per-script (each plan differs) — only bootstrap/validation/auth/parse helpers are shared.
- New mutation flow must keep isolation invariant (#1), idempotency (#2), and the auth/pre-flight gate.
- Skip steps as warnings inside the loop (matching the milestone-skip path) — don't hard-fail mid-loop.
- New deadline logic must keep the `+07:00` WIB format and the documented regex validation.