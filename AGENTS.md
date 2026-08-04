# AGENTS.md

## What This Repo Is

GitHub Organization automation toolkit for Hacktiv8 lectures. Two standalone bash scripts + config files + README guide. No application code, no dependencies, no tests.

## Stack

- **Bash** scripts (run with `bash <script>.sh [--dry-run]`, not executable-triggered)
- **`gh` CLI** (GitHub CLI) — sole external dependency, authenticated with `admin:org` scope
- No package manager, no lockfile, no build step

## Repo Map

| File | Purpose |
|---|---|
| `README.md` | Instructor guide: prerequisites (`gh auth login`, `gh auth refresh -h github.com -s admin:org`), dry-run + usage flow |
| `invite.sh` | Onboard students: ensure org team exists (secret privacy), invite users as `direct_member` linked to team |
| `create-repo.sh` | Bulk provisioning: create private per-student repos from template, isolated write access, reviewers, milestone + issue w/ deadline, feedback PR |
| `clone-repos.sh` | Clone all cohort repos: for each `TEMPLATES` entry, clone `TEAM_NAME-<template>-<user>` repos into `./<template>/<repo>/`, only for `USERS` and only if the repo exists in the org. Only needs read access — no `admin:org` |
| `orgflow.conf` (git-ignored) | Shared config for both scripts — `USERS`, `ORG`, `TEAM_NAME`, `REVIEWERS`, `TEMPLATES` |
| `orgflow.conf.example` | Committed template; copy to `orgflow.conf` and edit |

## Config Conventions

- Single shared config: `orgflow.conf` at repo root, `source`d by both scripts. **Git-ignored** — cohort data is local, never committed.
- `CONFIG_FILE` env var overrides the config path (used for testing/previews).
- `USERS=()` students (both scripts), `ORG` target org (invite.sh only — create-repo.sh derives org from `TEMPLATES[0]`), `TEAM_NAME` cohort id (both; prefixes repo names), `REVIEWERS=()` instructors/TA (create-repo.sh only), `TEMPLATES=()` with `org/repo|YYYY-MM-DD HH:MM` deadline format (create-repo.sh only).
- `clone-repos.sh` does not use `REVIEWERS` — it derives repo names from `TEAM_NAME` + `TEMPLATES` + `USERS`. Only requires existing org access — no `admin:org` scope check, matching its read-only contract.

## CLI Contract

- `bash <script>.sh --dry-run` prints the execution plan and exits 0 — **zero `gh` API calls**. Keep dry-run as an early-exit summary block, not a `gh` wrapper (wrapping breaks `$(gh api -q ...)` substitution and triggers false errors).
- Real mode exits non-zero on: missing config file, empty required vars (`USERS`/`ORG`/`TEAM_NAME`/`REVIEWERS`/`TEMPLATES`), malformed deadline (regex `YYYY-MM-DD HH:MM`), or missing auth (`gh` not installed / no `admin:org` scope). Missing/null deadline is a warning, not an error — milestone/issue creation is skipped, matching legacy behavior.
- New validation must run before the dry-run exit block so dry-run never sees invalid config.

## Critical Invariants (do not break)

1. **Repo isolation is intentional.** Students get `write` (push) only to their own repo. Reviewers get `maintain`. Team membership is **never** granted repo access (see `# 🔒 REMOVED STEP 2c ENTIRELY` comment in `create-repo.sh`).
2. **Idempotency / self-healing** — scripts must be safe to re-run: membership checked before invite, team existence checked before create, duplicate invite treated as notice not error.
3. **GitHub API timing** — `sleep 5` after repo/team creation exists because GitHub indexes asynchronously. Don't remove without evidence.
4. **Variable bleed protection** — `create-repo.sh` resets `NEW_REPO`/`SHA`/`MILESTONE_NUMBER` etc. per iteration. Preserve this pattern in any new per-user loop.
5. **Deadline format** — `YYYY-MM-DD HH:MM` converted to ISO `T...:00+07:00` (WIB) for milestone `due_on`. Keep the `+07:00` offset.

## Common Operations

- New cohort: `cp orgflow.conf.example orgflow.conf`, edit, then `bash <script>.sh --dry-run` → `bash <script>.sh`
- Re-run after partial failure: safe — scripts skip what already exists
- Check script syntax: `bash -n <script>.sh`

## Security Notes

- Scripts call GitHub API with caller's authenticated identity — requires `admin:org` permission. Don't downgrade silently.
- Usernames in config files are **intentional config**, not secrets. Configs are git-ignored to keep cohort data out of history anyway.
- Scripts contain no secrets. Never add tokens/keys to these files; they go in `gh` auth, not the repo.

## Coding Rules

- Match existing style: uppercase config vars, `echo` banner sections, `gh api` over raw curl, `--silent` on mutation calls, if-blocks with explicit `exit 1` (no `set -e`).
- Bootstrap pattern: `DRY_RUN` flag from `$1`, `SCRIPT_DIR`/`CONFIG_FILE` resolution (own-dir first), `source "$CONFIG_FILE"`, pre-flight validation, dry-run block, auth checks, then the original flow untouched.
- New mutation flow must keep isolation invariant (#1), idempotency (#2), and the auth/pre-flight gate.
- Skip steps as warnings inside the loop (matching the milestone-skip path) — don't hard-fail mid-loop.
- New deadline logic must keep the `+07:00` WIB format and the documented regex validation.