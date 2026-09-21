#!/bin/bash

# ==========================================
# GitHub Repository Provisioning Script (SECURE & ISOLATED)
# ==========================================
# Usage: bash create-repo.sh [--dry-run]
# Config: edit orgflow.conf (see orgflow.conf.example)
#   --dry-run  print the provisioning plan without calling the GitHub API

# Load shared helpers (config bootstrap, validation, auth, team setup)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_FILE="$SCRIPT_DIR/lib/common.sh"
if [ ! -f "$LIB_FILE" ]; then
    echo "Error: '$LIB_FILE' not found. Run create-repo.sh from a full orgflow checkout."
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
orgflow_require_count "${#TEMPLATES[@]}" "TEMPLATES"

for ITEM in "${TEMPLATES[@]}"; do
    if ! split_template "$ITEM"; then
        echo "Warning: TEMPLATES entry '$ITEM' has no deadline '|' separator."
        echo "  Milestone/issue creation will be skipped for this template."
        echo "  Expected format: \"repository|YYYY-MM-DD HH:MM\""
        continue
    fi
    if [ -z "$DEADLINE" ]; then
        echo "Warning: TEMPLATES entry '$ITEM' has no deadline."
        echo "  Milestone/issue creation will be skipped for this template."
        echo "  Expected format: \"repository|YYYY-MM-DD HH:MM\""
        continue
    fi
    if ! [[ "$DEADLINE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]; then
        echo "Error: Invalid deadline '$DEADLINE' in TEMPLATES entry '$ITEM'."
        echo "Expected format: \"repository|YYYY-MM-DD HH:MM\""
        exit 1
    fi
done

# ------------------------------------------
# Dry-run: print plan, execute nothing
# ------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
    echo "=========================================="
    echo "DRY-RUN: Provisioning plan"
    echo "=========================================="
    ALL_MEMBERS=($(echo "${USERS[@]}" "${REVIEWERS[@]}" | tr ' ' '\n' | sort -u))
    echo "Team:      $TEAM_NAME (created as '$ORGFLOW_TEAM_PRIVACY' if missing)"
    echo "Org sync:  ${#ALL_MEMBERS[@]} unique members (students + reviewers) added to team"
    echo ""
    for ITEM in "${TEMPLATES[@]}"; do
        split_template "$ITEM" || true
        CLEAN_REPO_NAME=$(clean_repo_name "$TEMPLATE_REPO")
        echo "Template: $TEMPLATE_REPO (deadline: ${DEADLINE:-none})"
        echo "  Would create ${#USERS[@]} private repos (write: student, maintain: reviewers):"
        for USER in "${USERS[@]}"; do
            echo "    - ${ORG}/${TEAM_NAME}-${CLEAN_REPO_NAME}-${USER}"
        done
        echo "  Per repo: deadline description, milestone + issue 'Assignment Deadline', feedback PR + .github/FEEDBACK_HINT.md"
        echo ""
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

# ==========================================

echo "=========================================="
echo "Synchronizing Team Memberships: $TEAM_NAME"
echo "=========================================="

# Ensure team exists and get its ID
ensure_team

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
  split_template "$ITEM" || true
  CLEAN_REPO_NAME=$(clean_repo_name "$TEMPLATE_REPO")

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
    gh repo create "$NEW_REPO" --template "$ORG/$TEMPLATE_REPO" --private

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
    if [ -n "$DEADLINE" ]; then
      DEADLINE_ISO=$(echo "$DEADLINE" | sed 's/ /T/')":00+07:00"
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

    REVIEWERS_STR=$(
      IFS=,
      echo "${REVIEWERS[*]}"
    )
    if [ -n "$REVIEWERS_STR" ]; then
      gh pr create \
        --repo "$NEW_REPO" \
        --title "Feedback" \
        --body "Hi @$USER, this Pull Request is created for your feedback and grading. Please do not close this PR." \
        --base "feedback" \
        --head "$DEFAULT_BRANCH" \
        --reviewer "$REVIEWERS_STR"
    else
      gh pr create \
        --repo "$NEW_REPO" \
        --title "Feedback" \
        --body "Hi @$USER, this Pull Request is created for your feedback and grading. Please do not close this PR." \
        --base "feedback" \
        --head "$DEFAULT_BRANCH"
    fi

    echo "Successfully provisioned for $USER"
    echo "------------------------------------------"
  done
done

echo "All tasks completed!"
