#!/bin/bash

# ==========================================
# Orgflow shared helpers
# ==========================================
# Sourced by invite.sh, create-repo.sh, clone-repos.sh.
# Not a standalone script — do not execute it directly.
#
# The caller MUST set SCRIPT_DIR before sourcing (config resolution needs it).
# Targets bash 3.2+ (no namerefs, no associative arrays) so it runs on the
# stock macOS shell too.

# Single source of truth for cohort team visibility.
# 'secret' = visible only to team members and org owners.
ORGFLOW_TEAM_PRIVACY="secret"

# ------------------------------------------
# Bootstrap: args, config, list conversion, template filter
# ------------------------------------------
# Usage: orgflow_bootstrap "$@"
# Sets: DRY_RUN, CONFIG_FILE, USERS, REVIEWERS, TEMPLATES (arrays).
orgflow_bootstrap() {
    DRY_RUN=0
    [ "$1" = "--dry-run" ] && DRY_RUN=1

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
    REVIEWERS_ARR=($REVIEWERS)
    REVIEWERS=("${REVIEWERS_ARR[@]}")

    # Template filter (set by TUI): semicolon-separated entries replace TEMPLATES
    if [ -n "$ORGFLOW_TEMPLATES" ]; then
        IFS=';' read -ra TEMPLATES_OVERRIDE <<< "$ORGFLOW_TEMPLATES"
        TEMPLATES=("${TEMPLATES_OVERRIDE[@]}")
    fi
}

# ------------------------------------------
# Pre-flight validation helpers (exit 1 on failure)
# ------------------------------------------
orgflow_require_set() {
    # $1=value  $2=variable name (for the message)
    if [ -z "$1" ]; then
        echo "Error: $2 is not set in $CONFIG_FILE."
        exit 1
    fi
}

orgflow_require_count() {
    # $1=count  $2=variable name (for the message)
    if [ "$1" -eq 0 ]; then
        echo "Error: $2 is empty in $CONFIG_FILE."
        exit 1
    fi
}

# ------------------------------------------
# GitHub CLI auth helpers (exit 1 on failure)
# ------------------------------------------
orgflow_check_gh() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "Error: GitHub CLI ('gh') not found. Install: https://cli.github.com"
        exit 1
    fi

    if ! gh auth status -h github.com >/dev/null 2>&1; then
        echo "Error: Not authenticated with GitHub CLI. Run 'gh auth login' first."
        exit 1
    fi
}

orgflow_check_admin_org() {
    if ! gh auth status -h github.com 2>&1 | grep -q "admin:org"; then
        echo "Error: Missing 'admin:org' scope."
        echo "Run 'gh auth refresh -h github.com -s admin:org'."
        exit 1
    fi
}

# ------------------------------------------
# Template parsing
# ------------------------------------------
# Splits a TEMPLATES entry "repository|YYYY-MM-DD HH:MM" into the globals
# TEMPLATE_REPO and DEADLINE.
# Returns 0 when the '|' separator is present, 1 when it is not (DEADLINE is
# then empty). A trailing comma on the repo name is stripped here so dry-run
# and execution can never disagree on the resulting repo name.
split_template() {
    if [[ "$1" == *"|"* ]]; then
        TEMPLATE_REPO=$(printf '%s' "$1" | cut -d'|' -f1 | sed 's/,$//')
        DEADLINE=$(printf '%s' "$1" | cut -d'|' -f2)
        return 0
    fi
    TEMPLATE_REPO=$(printf '%s' "$1" | sed 's/,$//')
    DEADLINE=""
    return 1
}

# Strips the literal word 'template' from a repo name, plus any edge separators.
clean_repo_name() {
    printf '%s' "$1" | sed -E 's/(^|[-_])template([-_]|$)/\1/g; s/^[-_]//; s/[-_]$//'
}

# ------------------------------------------
# Team
# ------------------------------------------
# Ensures the cohort team exists and sets TEAM_ID.
# Creates it with ORGFLOW_TEAM_PRIVACY when missing, then waits for GitHub to
# index it — membership/invite calls fail on a freshly created team otherwise.
ensure_team() {
    TEAM_ID=$(gh api "orgs/$ORG/teams/$TEAM_NAME" -q '.id' 2>/dev/null || true)
    if [[ "$TEAM_ID" =~ ^[0-9]+$ ]]; then
        echo "Team '$TEAM_NAME' already exists (ID: $TEAM_ID)."
        return 0
    fi

    echo "Team '$TEAM_NAME' does not exist. Creating it..."
    TEAM_ID=$(gh api -X POST "orgs/$ORG/teams" \
        -f name="$TEAM_NAME" \
        -f privacy="$ORGFLOW_TEAM_PRIVACY" \
        -q '.id' 2>/dev/null || true)

    if ! [[ "$TEAM_ID" =~ ^[0-9]+$ ]]; then
        echo "Error: Failed to create team '$TEAM_NAME'. Aborting."
        exit 1
    fi

    echo "Team '$TEAM_NAME' created successfully (ID: $TEAM_ID)."
    echo "Waiting for GitHub to initialize and index the new team..."
    sleep 5
}
