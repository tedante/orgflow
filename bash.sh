#!/bin/bash

# 1. Configuration
ORG_NAME="H8-P0-S2"
TEAM_SLUG="all-students" # Just use the exact text name of your team!

# Your list of student usernames
STUDENTS="whardian"

# 2. Operational Loop
IFS=',' read -ra ADDR <<< "$STUDENTS"

for username in "${ADDR[@]}"; do
  # Clean up whitespace
  username=$(echo "$username" | xargs)
  [ -z "$username" ] && continue

  echo "Processing: $username..."

  # STEP 1: Try to add them to the team directly (Assumes they are already in the org)
  # We send stderr to /dev/null to hide the ugly error if it fails
  TEAM_ADD=$(gh api --method PUT /orgs/$ORG_NAME/teams/$TEAM_SLUG/memberships/$username -f role="member" --silent 2>/dev/null)
  
  if [ $? -eq 0 ]; then
    echo "✅ Success: $username was already in the Org and is now in the team!"
  else
    # STEP 2: If Step 1 fails, it means they are brand new. Send an Organization Invitation!
    
    # First, get the numerical Team ID dynamically so you don't have to look it up!
    TEAM_ID=$(gh api orgs/$ORG_NAME/teams/$TEAM_SLUG --jq '.id')
    
    gh api --method POST /orgs/$ORG_NAME/invitations \
      -f invitee_username="$username" \
      -F "team_ids[]=$TEAM_ID" \
      --silent
      
    if [ $? -eq 0 ]; then
      echo "📩 Success: Org Invitation sent to $username (Team pre-assigned)"
    else
      echo "❌ Error: Could not invite or add $username. Check spelling."
    fi
  fi
  echo "-------------------------------------"
done