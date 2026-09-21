#!/bin/bash

# ==========================================
# GitHub Cohort Repo Cloner
# ==========================================
# Usage: bash clone-repos.sh [--dry-run]
# Config: edit orgflow.conf (see orgflow.conf.example)
# For each template in TEMPLATES, clones every student repo
# (TEAM_NAME-<template>-<user>) into $CLONE_DIR/<template>/<repo>/.
# CLONE_DIR (optional, default: current dir) sets the base folder.
# Only clones repos for users listed in USERS, and only if the
# repo actually exists in the org.
# Needs read access to the repos (reviewer/owner) — no admin:org.
#   --dry-run  print the clone plan without calling the GitHub API

# Load shared helpers (config bootstrap, validation, auth)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_FILE="$SCRIPT_DIR/lib/common.sh"
if [ ! -f "$LIB_FILE" ]; then
    echo "Error: '$LIB_FILE' not found. Run clone-repos.sh from a full orgflow checkout."
    exit 1
fi
source "$LIB_FILE"

orgflow_bootstrap "$@"

# Clone base directory (clone-repos.sh only) — repos land in $CLONE_DIR/<template>/
CLONE_DIR="${CLONE_DIR:-.}"

# ------------------------------------------
# Pre-flight validation
# ------------------------------------------
orgflow_require_set "$ORG" "ORG"
orgflow_require_set "$TEAM_NAME" "TEAM_NAME"
orgflow_require_count "${#USERS[@]}" "USERS"
orgflow_require_count "${#TEMPLATES[@]}" "TEMPLATES"

# ------------------------------------------
# Dry-run: print plan, execute nothing
# ------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
    echo "=========================================="
    echo "DRY-RUN: Clone plan"
    echo "=========================================="
    echo "Org:  $ORG"
    echo "Team: $TEAM_NAME"
    for ITEM in "${TEMPLATES[@]}"; do
        split_template "$ITEM" || true
        CLEAN_REPO_NAME=$(clean_repo_name "$TEMPLATE_REPO")
        echo "Template: $TEMPLATE_REPO -> $CLONE_DIR/$CLEAN_REPO_NAME/"
        for USER in "${USERS[@]}"; do
            echo "  - ${TEAM_NAME}-${CLEAN_REPO_NAME}-${USER}/"
        done
    done
    echo "------------------------------------------"
    echo "No GitHub API calls will be made."
    echo "Repos that do not exist in the org are skipped at runtime."
    echo "Re-run without --dry-run to execute."
    exit 0
fi

# ------------------------------------------
# GitHub CLI auth check (real mode only)
# ------------------------------------------
orgflow_check_gh

# ------------------------------------------
# List existing cohort repos once
# ------------------------------------------
EXISTING=$(gh repo list "$ORG" --limit 500 --json name -q '.[].name' | grep "^${TEAM_NAME}-" || true)

if [ -z "$EXISTING" ]; then
    echo "No repos matching '$ORG/${TEAM_NAME}-*' found."
    echo "Has provisioning (create-repo.sh) been run for this cohort?"
    exit 1
fi

# ------------------------------------------
# Clone per template into $CLONE_DIR/<template>/<repo>/
# (Idempotent: already-cloned folders are skipped)
# ------------------------------------------
for ITEM in "${TEMPLATES[@]}"; do
    split_template "$ITEM" || true
    CLEAN_REPO_NAME=$(clean_repo_name "$TEMPLATE_REPO")

    echo "------------------------------------------"
    echo "Cloning '$TEMPLATE_REPO' assignments into $CLONE_DIR/$CLEAN_REPO_NAME/"
    mkdir -p "$CLONE_DIR/$CLEAN_REPO_NAME"

    for USER in "${USERS[@]}"; do
        REPO_NAME="${TEAM_NAME}-${CLEAN_REPO_NAME}-${USER}"
        if ! echo "$EXISTING" | grep -qx "$REPO_NAME"; then
            echo "  - $REPO_NAME not found in org, skipping"
            continue
        fi
        if [ -d "$CLONE_DIR/$CLEAN_REPO_NAME/$REPO_NAME" ]; then
            echo "  - $REPO_NAME already exists, skipping"
            continue
        fi
        echo "  - cloning $ORG/$REPO_NAME"
        gh repo clone "$ORG/$REPO_NAME" "$CLONE_DIR/$CLEAN_REPO_NAME/$REPO_NAME" -- --quiet \
            || echo "  Error cloning $ORG/$REPO_NAME (check access or network)"
    done
done

echo "Done. Cloned repos are in $CLONE_DIR"
