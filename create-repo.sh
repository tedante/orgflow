#!/bin/bash

# ==========================================
# GitHub Repository Provisioning Script (SECURE & ISOLATED)
# ==========================================
# Please configure the variables below before running the script.

# Array of GitHub usernames
# Separate with spaces
USERS=(
    "fadildi60"
    "nickzadpratama"
    "afifchandrabayuaji"
    "Okabe-15"
    "i-adharul"
    "ariefrizkyrc"
)

# Reviewers (Format: ("user1" "user2"))
REVIEWERS=(
    "willyhardian" 
    "smfriady"
)

# Team Name for grouping everyone (e.g., "Batch-001")
TEAM_NAME="FSJS-STUDENTS"

# Template repositories and their respective deadlines
# Format: "organization/repository|YYYY-MM-DD HH:MM"
TEMPLATES=(
    "H8-P0-S1/fsjs-p0-v1-uc8|2026-07-19 23:59"
    "H8-P0-S1/fsjs-p0-v1-uc9|2026-07-19 23:59"
)

# ==========================================

# Extract Organization from first template (assuming all in same org)
ORG=$(echo "${TEMPLATES[0]}" | cut -d'/' -f1)

echo "=========================================="
echo "Synchronizing Team Memberships: $TEAM_NAME"
echo "=========================================="

# Ensure team exists and get its ID
TEAM_ID=$(gh api "orgs/$ORG/teams/$TEAM_NAME" -q '.id' 2>/dev/null || true)
if ! [[ "$TEAM_ID" =~ ^[0-9]+$ ]]; then
    echo "Team $TEAM_NAME does not exist. Creating it..."
    TEAM_ID=$(gh api -X POST "orgs/$ORG/teams" -f name="$TEAM_NAME" -f privacy="closed" -q '.id')
    echo "Waiting for GitHub to initialize and index the new team..."
    sleep 5
fi

# ----------------------------------------------------------------------
# 0. Self-Healing Access Control: Check Membership and Add/Invite
# ----------------------------------------------------------------------
ALL_MEMBERS=($(echo "${USERS[@]}" "${REVIEWERS[@]}" | tr ' ' '\n' | sort -u))

for MEMBER in "${ALL_MEMBERS[@]}"; do
    echo "------------------------------------------"
    echo "Processing Organization/Team access for $MEMBER..."
    
    IS_MEMBER=$(gh api "orgs/$ORG/members/$MEMBER" --silent -I 2>/dev/null && echo "yes" || echo "no")
    
    if [ "$IS_MEMBER" = "yes" ]; then
        echo "$MEMBER is already an organization member. Adding directly to team..."
        gh api -X PUT "orgs/$ORG/teams/$TEAM_NAME/memberships/$MEMBER" --silent
    else
        echo "$MEMBER is not in the org. Sending fresh invitation linked to team..."
        USER_ID=$(gh api "users/$MEMBER" -q '.id' 2>/dev/null)
        if [ -n "$USER_ID" ]; then
            gh api -X POST "orgs/$ORG/invitations" \
                -F invitee_id="$USER_ID" \
                -f role="direct_member" \
                -F "team_ids[]=$TEAM_ID" --silent || echo "Notice: Invitation pending or cache locked for $MEMBER."
        else
            echo "Error: Could not find GitHub user ID for $MEMBER"
        fi
    fi
done

echo "=========================================="
echo "Starting Bulk Repository Provisioning"
echo "Users: ${USERS[*]}"
echo "Reviewers: ${REVIEWERS[*]}"
echo "=========================================="

for ITEM in "${TEMPLATES[@]}"; do
    TEMPLATE_REPO=$(echo "$ITEM" | cut -d'|' -f1 | sed 's/,$//')
    DEADLINE=$(echo "$ITEM" | cut -d'|' -f2 | sed 's/,$//')

    ORG=$(echo "$TEMPLATE_REPO" | cut -d'/' -f1)
    REPO_BASENAME=$(echo "$TEMPLATE_REPO" | cut -d'/' -f2)

    CLEAN_REPO_NAME=$(echo "$REPO_BASENAME" | sed -E 's/(^|[-_])template([-_]|$)/\1/g; s/^[-_]//; s/[-_]$//')
    DEADLINE_ISO=$(echo "$DEADLINE" | sed 's/ /T/')":00+07:00"

    echo "##########################################"
    echo "TEMPLATE: $TEMPLATE_REPO"
    echo "DEADLINE: $DEADLINE"
    echo "##########################################"

    for USER in "${USERS[@]}"; do
        # Clean resets to prevent variable bleed
        NEW_REPO=""
        DEFAULT_BRANCH=""
        SHA=""
        MILESTONE_NUMBER=""

        NEW_REPO="${ORG}/${TEAM_NAME}-${CLEAN_REPO_NAME}-${USER}"
        echo "------------------------------------------"
        echo "Processing user '$USER' for repo '$CLEAN_REPO_NAME'"
        echo "Creating repository: $NEW_REPO"
        
        # 1. Create Repository from Template
        gh repo create "$NEW_REPO" --template "$TEMPLATE_REPO" --private
        
        if [ $? -ne 0 ]; then
            echo "Error creating repository $NEW_REPO. Skipping to next user."
            continue
        fi
        
        echo "Waiting for repository initialization..."
        sleep 5
        
        # 2. Assign Direct Isolated Access to the Student Only
        echo "Assigning 'write' access to $USER..."
        gh api -X PUT "repos/$NEW_REPO/collaborators/$USER" -f permission=push --silent
        
        # 2b. Assign Access to Reviewers
        for REV in "${REVIEWERS[@]}"; do
            echo "Assigning 'maintain' access to reviewer: $REV..."
            gh api -X PUT "repos/$NEW_REPO/collaborators/$REV" -f permission=maintain --silent
        done

        # 🔒 REMOVED STEP 2c ENTIRELY: The repository is never exposed to the team.
        
        # 3. Update Repository Description with Deadline
        echo "Updating repository description..."
        gh repo edit "$NEW_REPO" --description "Assignment Repository for $USER. Deadline: $DEADLINE"
        
        # 4. Create a Milestone with the Deadline
        echo "Creating milestone 'Assignment Deadline'..."
        MILESTONE_NUMBER=$(gh api -X POST "repos/$NEW_REPO/milestones" \
            -f title="Assignment Deadline" \
            -f due_on="$DEADLINE_ISO" \
            -q '.number')
        
        sleep 2
        
        if [ -n "$MILESTONE_NUMBER" ] && [ "$MILESTONE_NUMBER" != "null" ]; then
            # 5. Create an Issue associated with the Milestone
            echo "Creating issue linked to milestone..."
            gh issue create \
                --repo "$NEW_REPO" \
                --title "Assignment Deadline" \
                --body "Hi @$USER, please be reminded that the deadline for this assignment is **$DEADLINE**." \
                --milestone "Assignment Deadline"
        else
            echo "Failed to create milestone for $NEW_REPO. Skipping issue creation."
        fi
        
        # 6. Create Feedback Pull Request
        echo "Creating Feedback Pull Request..."
        DEFAULT_BRANCH=$(gh repo view "$NEW_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
        
        SHA=$(gh api "repos/$NEW_REPO/git/ref/heads/$DEFAULT_BRANCH" -q '.object.sha')
        gh api -X POST "repos/$NEW_REPO/git/refs" -f ref="refs/heads/feedback" -f sha="$SHA" --silent
        
        gh api -X PUT "repos/$NEW_REPO/contents/.github/FEEDBACK_HINT.md" \
            -f message="Setup feedback PR" \
            -f content="$(echo "This Pull Request is created for feedback purposes." | base64)" \
            -f branch="$DEFAULT_BRANCH" --silent
        
        REVIEWERS_STR=$(IFS=,; echo "${REVIEWERS[*]}")
        gh pr create \
            --repo "$NEW_REPO" \
            --title "Feedback" \
            --body "Hi @$USER, this Pull Request is created for your feedback and grading. Please do not close this PR." \
            --base "feedback" \
            --head "$DEFAULT_BRANCH" \
            --reviewer "$REVIEWERS_STR"
        
        echo "Successfully provisioned for $USER"
        echo "------------------------------------------"
    done
done

echo "All tasks completed!"