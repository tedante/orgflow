# Orgflow: GitHub Organization & Repository Automation

Orgflow automates student onboarding and assignment provisioning for Hacktiv8 lectures. It has three features, one bash script each:

| Feature      | Script           | What it does                                                                                                                                                                         |
| ------------ | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Invite       | `invite.sh`      | Onboard students: make sure the cohort team exists, then invite students to the org as members linked to that team                                                                   |
| Create repos | `create-repo.sh` | Provision private per-student repos from a template, give each student isolated write access, assign reviewers, create a milestone and issue with a deadline, and open a feedback PR |
| Clone repos  | `clone-repos.sh` | Clone every cohort repo for grading and review                                                                                                                                       |

You can run all three from the TUI (`npm start`) or directly from the command line.

---

## Prerequisites (do this once)

GitHub CLI must be installed and authenticated with admin access to the organization.

### 1. Install GitHub CLI

See the official docs at [cli.github.com](https://cli.github.com/) for all install options. The common ones:

```bash
# macOS
brew install gh

# Linux (Debian/Ubuntu)
sudo apt install gh

# Windows (winget)
winget install --id GitHub.cli
```

Check the install:

```bash
gh --version
```

### 2. Authenticate with GitHub

Link your GitHub account:

```bash
gh auth login
```

Follow the interactive prompts and log in through the browser.

### 3. Grant admin access to the organization

Give the tool permission to manage organization resources:

```bash
gh auth refresh -h github.com -s admin:org
```

Why `admin:org`? The scripts create teams, invite members, and create repos inside the organization. All of that needs the `admin:org` scope. Without it, the scripts fail at the first step.

---

## Setup: copy and edit the config

All scripts share one config file, `orgflow.conf`. It is git-ignored, so cohort data never gets committed.

### 1. Copy from the template

```bash
cp orgflow.conf.example orgflow.conf
```

### 2. Edit `orgflow.conf`

Fill in the values for your cohort. These are the available variables:

| Variable    | Used by        | Purpose                                                                                                                                                                                                         |
| ----------- | -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `USERS`     | all            | Student GitHub usernames. Paste as-is, one per line, no quotes                                                                                                                                                  |
| `ORG`       | all            | Target organization name (used by invite, create, and clone)                                                                                                                                                    |
| `TEAM_NAME` | invite, create | Cohort id (for example `hck-99`). Prefixes repo names in `create-repo.sh`                                                                                                                                       |
| `REVIEWERS` | create         | Instructor or TA usernames, space or newline separated, no quotes. Optional. Leave empty to skip assigning reviewers                                                                                            |
| `TEMPLATES` | create, clone  | Template repo name plus deadline. Format `repository\|YYYY-MM-DD HH:MM` (WIB). The org comes from `ORG`, so list only the repo name. Deadline is optional; without it the milestone and issue steps are skipped |
| `CLONE_DIR` | clone          | Base folder for cloned repos (for example `cloneResult`). Optional, defaults to the current directory                                                                                                           |

Example `orgflow.conf`:

```bash
USERS="username-student-1
usernameStudent2
StudentUsername3"

ORG="H8-P1-S2"

TEAM_NAME="hck-99"

REVIEWERS="tedante nuninnih"   # leave empty for no reviewers

TEMPLATES=(
    "fsjs-p1-v2-c3|2026-08-31 23:59"
    "fsjs-p1-v2-c4"
)

CLONE_DIR="cloneResult"
```

Note on `TEMPLATES`: list only the repo name, without the `ORG/` prefix. The org is taken from the `ORG` variable. Deadlines use `YYYY-MM-DD HH:MM` (WIB).

---

## Dry-run vs execution

Every feature has two modes. This is the part people get confused about, so read it carefully.

|              | DRY-RUN                              | EXECUTION                                                 |
| ------------ | ------------------------------------ | --------------------------------------------------------- |
| Command      | `bash <script>.sh --dry-run`         | `bash <script>.sh`                                        |
| What it does | Prints the plan of what would happen | Actually makes the changes                                |
| GitHub API   | No API calls at all                  | Calls the API for real                                    |
| Effect       | No changes anywhere                  | Creates or changes org resources (team, repo, invite, PR) |
| When to use  | Always check before executing        | After you are sure the plan is right                      |

Recommended flow:

```
1. bash <script>.sh --dry-run   check the plan, make sure it is right
2. bash <script>.sh             run it for real
```

Why dry-run first? Execution makes permanent changes on GitHub (creates repos, sends invites, opens PRs) that cannot be undone. Dry-run shows exactly what would happen with no risk.

---

## Feature 1: Invite students (`invite.sh`)

Makes sure the cohort team exists, then invites students to the org as `direct_member` linked to that team.

### Dry-run

```bash
bash invite.sh --dry-run
```

Output: the team and who would be invited. No API calls.

### Execution

```bash
bash invite.sh
```

Safe to re-run. Existing members are detected and not invited again.

---

## Feature 2: Create repos (`create-repo.sh`)

Creates private per-student repos from a template, gives each student isolated write access, assigns reviewers, creates a milestone and issue with a deadline, and opens a feedback PR.

### Dry-run

```bash
bash create-repo.sh --dry-run
```

Output: the team, member sync, every repo name that would be created, and the per-repo actions. No API calls.

### Execution

```bash
bash create-repo.sh
```

Safe to re-run after a partial failure. Existing repos, teams, and invites are skipped or treated as notices.

---

## Feature 3: Clone repos (`clone-repos.sh`)

For each template in `TEMPLATES`, clones every student repo (`TEAM_NAME-<template>-<user>`) into `$CLONE_DIR/<template>/<repo>/`. It only clones repos for users in `USERS`, and only if the repo actually exists in the org. Useful for grading or reviewing all assignments at once.

It only needs read access to the repos (reviewer or owner). It does not need `admin:org`.

### Dry-run

```bash
bash clone-repos.sh --dry-run
```

Output: the folders and repo names that would be cloned. No API calls.

### Execution

```bash
bash clone-repos.sh
```

Result (with `CLONE_DIR="cloneResult"`):

```
grading/
└── cloneResult/
    └── fsjs-p1-v2-c3/
        ├── hck-99-fsjs-p1-v2-c3-michaelarteta-design/
        ├── hck-99-fsjs-p1-v2-c3-fadil0711/
        └── ...
```

Re-running skips folders that are already cloned. Repos for users that have not been provisioned are reported and skipped.

---

## TUI (recommended)

All three features run from one interactive menu (Node.js + Ink):

```bash
npm install   # once
npm start
```

The TUI shows the config and `gh` auth status, and splits the menu clearly between DRY-RUN and EXECUTION:

```
Orgflow TUI

▶ DRY-RUN (preview only, no changes)
    ▶ Invite students — preview invitations — no changes
      Create repos — preview repo plan — no changes
      Clone repos — preview clone plan — no changes
▶ EXECUTION (real GitHub changes)
      Invite students — send real org invitations
      Create repos — create real repos + feedback PRs
      Clone repos — clone real cohort repos
▶ OTHER
      Refresh status
      Check gh auth
      Quit
```

- DRY-RUN items run the script with `--dry-run`. They only show the plan, no changes.
- EXECUTION items run the script for real. They always ask for confirmation (`y`/`n`) before calling the GitHub API.
- When `TEMPLATES` has more than one entry, Create and Clone show a template picker first. Toggle which templates to process with space, then press Enter.

Navigation: `↑↓` to move, `Enter` to select, `q`/`Esc` to quit.

---

## Workflow summary

```
1. Setup:  cp orgflow.conf.example orgflow.conf   then edit
2. Check:  bash invite.sh --dry-run               then bash invite.sh
3. Check:  bash create-repo.sh --dry-run          then bash create-repo.sh
4. (optional) bash clone-repos.sh --dry-run       then bash clone-repos.sh
```

Or use the TUI: `npm start` runs every step from one menu.
