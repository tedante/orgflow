#!/bin/bash

# ==========================================
# GitHub Cohort Repo Cloner
# ==========================================
# Usage: bash clone-repos.sh [--dry-run]
# Config: edit orgflow.conf (see orgflow.conf.example)
# For each template in TEMPLATES, clones every student repo
# (TEAM_NAME-<template>-<user>) into ./<template>/<repo>/.
# Only clones repos for users listed in USERS, and only if the
# repo actually exists in the org.
# Needs read access to the repos (reviewer/owner) — no admin:org.
#   --dry-run  print the clone plan without calling the GitHub API

DRY_RUN=0
[ "$1" = "--dry-run" ] && DRY_RUN=1

# Load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/orgflow.conf}"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file '$CONFIG_FILE' not found."
    echo "Copy orgflow.conf.example to orgflow.conf and edit it before running."
    exit 1
fi
source "$CONFIG_FILE"

# ------------------------------------------
# Pre-flight validation
# ------------------------------------------
if [ -z "$ORG" ]; then
    echo "Error: ORG is not set in $CONFIG_FILE."
    exit 1
fi

if [ -z "$TEAM_NAME" ]; then
    echo "Error: TEAM_NAME is not set in $CONFIG_FILE."
    exit 1
fi

if [ "${#USERS[@]}" -eq 0 ]; then
    echo "Error: USERS is empty in $CONFIG_FILE."
    exit 1
fi

if [ "${#TEMPLATES[@]}" -eq 0 ]; then
    echo "Error: TEMPLATES is empty in $CONFIG_FILE."
    exit 1
fi

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
        case "$ITEM" in
            *"|"*)
                TEMPLATE_REPO=$(echo "$ITEM" | cut -d'|' -f1)
                ;;
            *)
                TEMPLATE_REPO="$ITEM"
                ;;
        esac
        REPO_BASENAME=$(echo "$TEMPLATE_REPO" | cut -d'/' -f2)
        CLEAN_REPO_NAME=$(echo "$REPO_BASENAME" | sed -E 's/(^|[-_])template([-_]|$)/\1/g; s/^[-_]//; s/[-_]$//')
        echo "Template: $TEMPLATE_REPO -> ./$CLEAN_REPO_NAME/"
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
if ! command -v gh >/dev/null 2>&1; then
    echo "Error: GitHub CLI ('gh') not found. Install: https://cli.github.com"
    exit 1
fi

if ! gh auth status -h github.com >/dev/null 2>&1; then
    echo "Error: Not authenticated with GitHub CLI. Run 'gh auth login' first."
    exit 1
fi

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
# Clone per template into ./<template>/<repo>/
# (Idempotent: already-cloned folders are skipped)
# ------------------------------------------
for ITEM in "${TEMPLATES[@]}"; do
    case "$ITEM" in
        *"|"*)
            TEMPLATE_REPO=$(echo "$ITEM" | cut -d'|' -f1)
            ;;
        *)
            TEMPLATE_REPO="$ITEM"
            ;;
    esac
    REPO_BASENAME=$(echo "$TEMPLATE_REPO" | cut -d'/' -f2)
    CLEAN_REPO_NAME=$(echo "$REPO_BASENAME" | sed -E 's/(^|[-_])template([-_]|$)/\1/g; s/^[-_]//; s/[-_]$//')

    echo "------------------------------------------"
    echo "Cloning '$TEMPLATE_REPO' assignments into ./$CLEAN_REPO_NAME/"
    mkdir -p "$CLEAN_REPO_NAME"

    for USER in "${USERS[@]}"; do
        REPO_NAME="${TEAM_NAME}-${CLEAN_REPO_NAME}-${USER}"
        if ! echo "$EXISTING" | grep -qx "$REPO_NAME"; then
            echo "  - $REPO_NAME not found in org, skipping"
            continue
        fi
        if [ -d "$CLEAN_REPO_NAME/$REPO_NAME" ]; then
            echo "  - $REPO_NAME already exists, skipping"
            continue
        fi
        echo "  - cloning $ORG/$REPO_NAME"
        gh repo clone "$ORG/$REPO_NAME" "$CLEAN_REPO_NAME/$REPO_NAME" -- --quiet \
            || echo "  Error cloning $ORG/$REPO_NAME (check access or network)"
    done
done

echo "Done. Cloned repos are in $(pwd)"