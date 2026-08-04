# 🛠️ Instructor Guide: GitHub Organization & Repository Automation

This guide covers the prerequisites and step-by-step instructions for running the automation scripts to onboard students and provision private repository environments.

## 📋 Prerequisites (Do this First)

Before running either script, the instructor's local machine must have the GitHub CLI installed and authenticated with administrative organization access.

1. **Install GitHub CLI**:
   Open your terminal and install the CLI tool:
   ```bash
   brew install gh
   ```

2. **Authenticate with GitHub**:
   Link your GitHub account by running:
   ```bash
   gh auth login
   ```
   *Follow the interactive terminal prompts to log in via your browser.*

3. **Elevate Organization Permissions**:
   Explicitly grant the tool permission to manage organization resources:
   ```bash
   gh auth refresh -h github.com -s admin:org
   ```

---

## ⚙️ Configuration

Both scripts share one config file. It is git-ignored — copy the example and edit:

```bash
cp orgflow.conf.example orgflow.conf
```

| Variable | Used by | Purpose |
|---|---|---|
| `USERS` | both | Student GitHub usernames, space separated |
| `ORG` | `invite.sh` | Target GitHub Organization (`create-repo.sh` derives the org from `TEMPLATES`) |
| `TEAM_NAME` | both | Cohort identifier (e.g. `hck-99`). Prefixes repo names in `create-repo.sh` |
| `REVIEWERS` | `create-repo.sh` | Instructor/TA usernames |
| `TEMPLATES` | `create-repo.sh` | `organization/repository\|YYYY-MM-DD HH:MM` — template + deadline (WIB). Deadline optional; without it, milestone/issue steps are skipped |

> Config files are git-ignored on purpose. Cohort data stays local — scripts stay generic.

---

## 👤 Step 1: Onboarding Students (`invite.sh`)

Ensures the cohort team exists, then invites students to the org as direct members linked to that team.

### 1. Dry-run (recommended)
```bash
bash invite.sh --dry-run
```
Prints the invitation plan (team, invitees) **without calling the GitHub API**.

### 2. Execute
```bash
bash invite.sh
```
Safe to re-run — existing memberships are detected and not re-invited.

---

## 🚀 Step 2: Bulk Assignment Provisioning (`create-repo.sh`)

Creates private per-student repos from a template, grants isolated write access to the student only, assigns reviewers, schedules a milestone with deadline, and opens a feedback PR.

### 1. Configuration
Edit `TEMPLATES` in `orgflow.conf`. Example with deadline:

```
TEMPLATES=(
    "H8-P1-S2/fsjs-p1-v2-c3|2026-08-31 23:59"
)
```

### 2. Dry-run (recommended)
```bash
bash create-repo.sh --dry-run
```
Prints the full provisioning plan: team, member sync, every repo name, per-repo actions. **No API calls.**

### 3. Execute
```bash
bash create-repo.sh
```
Safe to re-run after partial failure — existing repos/teams/invitations are skipped or treated as notices.

---

## 📥 Bonus: Cloning All Cohort Repos (`clone-repos.sh`)

For each template in `TEMPLATES`, clones every student repo (`TEAM_NAME-<template>-<user>`) into `./<template>/<repo>/` — only for users listed in `USERS`, only if the repo actually exists. Handy for reviewing/grading all assignments at once. Needs only read access to the repos (reviewer/owner) — no `admin:org`.

```bash
# from a fresh grading directory
cd ~/grading
bash clone-repos.sh --dry-run   # verify plan: folders + repo names
bash clone-repos.sh             # clone all repos into ./fsjs-p1-v2-c3/
```

Result:
```
grading/
└── fsjs-p1-v2-c3/
    ├── hck-99-fsjs-p1-v2-c3-michaelarteta-design/
    ├── hck-99-fsjs-p1-v2-c3-fadil0711/
    └── ...
```

Re-running skips already-cloned folders. Repos for users not provisioned yet are reported and skipped.