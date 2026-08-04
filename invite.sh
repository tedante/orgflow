#!/bin/bash

# ==========================================
# GitHub Organization Invitation Script
# ==========================================
# Usage: bash invite.sh [--dry-run]
# Config: edit orgflow.conf (see orgflow.conf.example)
#   --dry-run  print the invitation plan without calling the GitHub API

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

# Convert plain-string lists to arrays (conf format: no quotes, space/newline-separated)
# Safe: GitHub username charset is [a-zA-Z0-9-], no glob characters possible
USERS_ARR=($USERS)
USERS=("${USERS_ARR[@]}")

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

# ------------------------------------------
# Dry-run: print plan, execute nothing
# ------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
    echo "=========================================="
    echo "DRY-RUN: Invitation plan for $ORG"
    echo "=========================================="
    echo "Team:     $TEAM_NAME (created as 'secret' if missing)"
    echo "Invitees: ${#USERS[@]} users as direct_member, linked to team:"
    for USER in "${USERS[@]}"; do
        echo "  - $USER"
    done
    echo "------------------------------------------"
    echo "No GitHub API calls will be made."
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

if ! gh auth status -h github.com 2>&1 | grep -q "admin:org"; then
    echo "Error: Missing 'admin:org' scope."
    echo "Run 'gh auth refresh -h github.com -s admin:org'."
    exit 1
fi

echo "=========================================="
echo "Inviting Users to Organization: $ORG"
echo "Target Team: $TEAM_NAME"
echo "=========================================="

# ------------------------------------------
# Step 1: Ensure the team exists
# ------------------------------------------
echo "Checking if team '$TEAM_NAME' exists in '$ORG'..."
TEAM_ID=$(gh api "orgs/$ORG/teams/$TEAM_NAME" -q '.id' 2>/dev/null || true)

if [[ "$TEAM_ID" =~ ^[0-9]+$ ]]; then
    echo "Team '$TEAM_NAME' already exists (ID: $TEAM_ID)."
else
    echo "Team '$TEAM_NAME' does not exist. Creating it..."
    TEAM_ID=$(gh api -X POST "orgs/$ORG/teams" \
        -f name="$TEAM_NAME" \
        -f privacy="secret" \
        -q '.id' 2>/dev/null || true)

    if ! [[ "$TEAM_ID" =~ ^[0-9]+$ ]]; then
        echo "Error: Failed to create team '$TEAM_NAME'. Aborting."
        exit 1
    fi
    echo "Team '$TEAM_NAME' created successfully (ID: $TEAM_ID)."
fi

# ------------------------------------------
# Step 2: Invite users to the org & team
# ------------------------------------------
for USER in "${USERS[@]}"; do
    echo "------------------------------------------"
    echo "Inviting $USER to organization '$ORG'..."

    USER_ID=$(gh api "users/$USER" -q '.id' 2>/dev/null)
    if [ -z "$USER_ID" ]; then
        echo "Error: Could not find GitHub user ID for '$USER'. Skipping."
        continue
    fi

    gh api -X POST "orgs/$ORG/invitations" \
        -F invitee_id="$USER_ID" \
        -f role="direct_member" \
        -F "team_ids[]=$TEAM_ID" --silent \
        && echo "Invitation sent to $USER (added to team '$TEAM_NAME')." \
        || echo "Notice: $USER is likely already in the organization or invitation is pending."
done

echo "=========================================="
echo "All invitations processed!"
echo "=========================================="
