#!/bin/bash

# ==========================================
# GitHub Organization Invitation Script
# ==========================================
# Usage: bash invite.sh [--dry-run]
# Config: edit orgflow.conf (see orgflow.conf.example)
#   --dry-run  print the invitation plan without calling the GitHub API

# Load shared helpers (config bootstrap, validation, auth, team setup)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_FILE="$SCRIPT_DIR/lib/common.sh"
if [ ! -f "$LIB_FILE" ]; then
    echo "Error: '$LIB_FILE' not found. Run invite.sh from a full orgflow checkout."
    exit 1
fi
source "$LIB_FILE"

orgflow_bootstrap "$@"

# ------------------------------------------
# Pre-flight validation
# ------------------------------------------
orgflow_require_set "$ORG" "ORG"
orgflow_require_set "$TEAM_NAME" "TEAM_NAME"
orgflow_require_count "${#USERS[@]}" "USERS"

# ------------------------------------------
# Dry-run: print plan, execute nothing
# ------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
    echo "=========================================="
    echo "DRY-RUN: Invitation plan for $ORG"
    echo "=========================================="
    echo "Team:     $TEAM_NAME (created as '$ORGFLOW_TEAM_PRIVACY' if missing)"
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
orgflow_check_gh
orgflow_check_admin_org

echo "=========================================="
echo "Inviting Users to Organization: $ORG"
echo "Target Team: $TEAM_NAME"
echo "=========================================="

# ------------------------------------------
# Step 1: Ensure the team exists
# ------------------------------------------
ensure_team

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
