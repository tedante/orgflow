#!/bin/bash

# ==========================================
# GitHub Organization Invitation Script
# ==========================================
# Please configure the variables below before running the script.

# Array of GitHub usernames to invite
# Separate with spaces
USERS=(
    "michaelarteta-design"
    "fadil0711"
    "fadildi60"
    "nickzadpratama"
    "afifchandrabayuaji"
    "Okabe-15"
    "i-adharul"
    "ariefrizkyrc"
)

# Organization name
ORG="H8-P0-S1"

# Team name to add invited users to (required)
TEAM_NAME="hck-100"

# ==========================================

# Validate required configuration
if [ -z "$ORG" ]; then
    echo "Error: ORG is not set."
    exit 1
fi

if [ -z "$TEAM_NAME" ]; then
    echo "Error: TEAM_NAME is not set."
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
