#!/bin/bash
# ======================================================================================
# Synopsis:
# - A informative formatted summary of recent commit messages, their short-shas, and timestamps from GitHub or GitLab URLs
# - A list of commits/timestamps/short-shas who's filenames or commit messages match a regex (eg: so it can be configured to pull info for everything related to a backend microservice) and provide some stats such as: X backend files changed in last 6 hours
# - If possible, reconstruct the git URLs for the detected files (gitlab or github) and provide those URLs in the raised issues if the regex finds matches

REPO_OWNER=""
REPO_NAME=""

function git_hist_inspec_help(){
    echo "
    git-hist-inspec help

    Usage: git-hist-inspec <URL>

    Examples:
        git-hist-inspec
    "
}


function extract_repo_info(){
    local url_type="$1"

    # Using local variables within the function
    local owner=""
    local repo=""

    if [[ $url_type -eq 0 ]]; then
        # GitHub
        owner=$(echo "$URL" | sed -n 's/.*github.com\/\([^\/]*\)\/\([^\/]*\).*/\1/p')
        repo=$(echo "$URL" | sed -n 's/.*github.com\/\([^\/]*\)\/\([^\/]*\).*/\2/p')
    elif [[ $url_type -eq 1 ]]; then
        # GitLab
        owner=$(echo "$URL" | sed -n 's/.*gitlab.com\/\([^\/]*\)\/\([^\/]*\).*/\1/p')
        repo=$(echo "$URL" | sed -n 's/.*gitlab.com\/\([^\/]*\)\/\([^\/]*\).*/\2/p')
    fi

    # Assign to global variables
    REPO_OWNER="$owner"
    REPO_NAME="$repo"
}

function check_valid_url(){
    if [[ "$1" =~ ^(http|https)://github.com/.*$ ]]; then
        return 0
    elif [[ "$1" =~ ^(http|https)://gitlab.com/.*$ ]]; then
        return 1
    else
        echo "Invalid URL"
        exit 1
    fi
}

function print_commits_summary() {
    local commits_data="$1"
    local url_type="$2"

    echo "Summary of recent commits:"
    if [[ $url_type -eq 0 ]]; then
        # GitHub
        echo "$commits_data" | jq -r '.[0:5] | .[] | "\(.sha[0:7]) - \(.commit.committer.date) - \(.commit.message)"'
    elif [[ $status -eq 1 ]]; then
        # GitLab
        echo "$commits_data" | jq -r '.[0:5] | .[] | "\(.short_id) - \(.committed_date) - \(.title)"'
    fi
}


function main (){

    # Check if help
    if [[ "$1" == "help" ]]; then
        git_hist_inspec_help
        exit 0
    fi

    # Check if URL provided
    if [[ "$1" == "" ]]; then
        echo "No URL provided"
        exit 1
    fi

    # Check if valid URL
    URL="$1"
    check_valid_url "$URL"
    status=$?
    if [[ $status -eq 0 ]]; then
        echo "GitHub URL detected"
    elif [[ $status -eq 1 ]]; then
        echo "GitLab URL detected"
    fi
    
    # Extract repo name and owner
    extract_repo_info "$status"


    # Get commits
    if [[ $status -eq 0 ]]; then
        COMMITS=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/commits" | jq '.')
    elif [[ $status -eq 1 ]]; then
        COMMITS=$(curl -s "https://gitlab.com/api/v4/projects/$REPO_OWNER%2F$REPO_NAME/repository/commits" | jq '.')
    fi

    # Print commits summary
    print_commits_summary "$COMMITS" "$status"


}
main "$@"


