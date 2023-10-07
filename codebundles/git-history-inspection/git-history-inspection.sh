#!/bin/bash
# ======================================================================================
# Synopsis:
# - A informative formatted summary of recent commit messages, their short-shas, and timestamps from GitHub or GitLab URLs
# - A list of commits/timestamps/short-shas who's filenames or commit messages match a regex (eg: so it can be configured to pull info for everything related to a backend microservice) and provide some stats such as: X backend files changed in last 6 hours
# - If possible, reconstruct the git URLs for the detected files (gitlab or github) and provide those URLs in the raised issues if the regex finds matches

REPO_OWNER=""
REPO_NAME=""
GITHUB=0
GITLAB=1

function git_hist_inspec_help(){
    echo "
    git-hist-inspec help

    Usage: git-hist-inspec <URL> <regex> [duration]

    Duration format:
    - 'd' for days (e.g. '3d' for 3 days)
    - 'h' for hours (e.g. '6h' for 6 hours)
    - 'm' for minutes (e.g. '15m' for 15 minutes)
    - Combine days, hours, and minutes (e.g. '2d3h15m' for 2 days, 3 hours, and 15 minutes)

    Authentication:
    To avoid rate limits and access private repositories, you can set authentication tokens.
    For GitHub: Export GITHUB_TOKEN environment variable.
    For GitLab: Export GITLAB_TOKEN environment variable.

    Examples:
        git-hist-inspec https://github.com/username/repo A_File\.txt 6h
        git-hist-inspec https://github.com/username/repo A_File\.txt 2d3h15m
    "
}



function extract_repo_info(){
    local url_type="$1"
    
    # Using local variables within the function
    local owner=""
    local repo=""
    
    if [[ $url_type -eq $GITHUB ]]; then
        # GitHub
        owner=$(echo "$URL" | sed -n 's/.*github.com\/\([^\/]*\)\/\([^\/]*\).*/\1/p')
        repo=$(echo "$URL" | sed -n 's/.*github.com\/\([^\/]*\)\/\([^\/]*\).*/\2/p')
        elif [[ $url_type -eq $GITLAB ]]; then
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
        return $GITHUB
        elif [[ "$1" =~ ^(http|https)://gitlab.com/.*$ ]]; then
        return $GITLAB
    else
        echo "Invalid URL"
        exit 1
    fi
}

function is_valid_json() {
    echo "$1" | jq . >/dev/null 2>&1
}

function check_github_commits_rate_limit() {
    local response="$1"
    
    # Check if null
    if [ "$response" == "null" ]; then
        echo "Received null response from GitHub. Please check if the repository exists."
        exit 1
    fi
    
    # Check if valid JSON
    if ! is_valid_json "$response"; then
        echo "Received invalid JSON response from GitHub."
        exit 1
    fi
    
    if echo "$response" | jq -e '.[] | select(.message != null) | .message | contains("API rate limit exceeded")' >/dev/null; then
        echo "Rate limit exceeded for GitHub commits. Please try again later or authenticate your requests."
        exit 1
    fi
}

function check_github_files_rate_limit() {
    local response="$1"
    
    # Check if null
    if [ "$response" == "null" ]; then
        echo "No files data received."
        exit 1
    fi
    
    # Check if valid JSON
    if ! is_valid_json "$response"; then
        echo "Received invalid JSON response from GitHub for files."
        exit 1
    fi
    
    # Check for rate limit exceeded in object format
    if echo "$response" | jq -e 'select(.message != null) | .message | contains("API rate limit exceeded")' >/dev/null; then
        echo "Rate limit exceeded for GitHub files. Please try again later or authenticate your requests."
        exit 1
    fi
}


function check_gitlab_rate_limit() {
    local response="$1"
    # Assuming a "message" field in response, this might need adjustment
    if echo "$response" | jq -e '.message | contains("Rate limit exceeded")' >/dev/null; then
        echo "Rate limit exceeded for GitLab. Please try again later or authenticate your requests."
        exit 1
    fi
}

function check_github_token() {
    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo "GITHUB_TOKEN environment variable not set. Please set it to proceed."
        exit 1
    fi
}

function check_gitlab_token() {
    if [[ -z "$GITLAB_TOKEN" ]]; then
        echo "GITLAB_TOKEN environment variable not set. Please set it to proceed."
        exit 1
    fi
}

function print_commits_summary() {
    local commits_data="$1"
    local url_type="$2"
    
    echo "Summary of recent commits:"
    if [[ $url_type -eq $GITHUB ]]; then
        # GitHub
        echo "$commits_data" | jq -r '.[0:5] | .[] | "\(.sha[0:8]) - \(.commit.committer.date) - \(.commit.message)"'
        elif [[ $url_type -eq $GITLAB ]]; then
        # GitLab
        echo "$commits_data" | jq -r '.[0:5] | .[] | "\(.short_id) - \(.committed_date) - \(.title)"'
    fi
}

function fetch_github_commits() {
    check_github_token
    local response
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/commits")
    check_github_commits_rate_limit "$response"
    
    # Validate JSON
    if ! is_valid_json "$response"; then
        echo "Received invalid JSON response from GitHub."
        exit 1
    fi
    
    echo "$response"
}

function fetch_github_commit_files() {
    check_github_token
    local commit_sha="$1"
    local response
    
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/commits/$commit_sha")
    check_github_files_rate_limit "$response"
    
    echo "$response"
}

function fetch_gitlab_commits() {
    check_gitlab_token
    local response
    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "https://gitlab.com/api/v4/projects/$REPO_OWNER%2F$REPO_NAME/repository/commits")
    # check_gitlab_rate_limit "$response"
    
    # Save JSON
    # echo "$response" > jsons/gitlab_commits.json
    
    echo "$response"
}

function fetch_gitlab_commit_files(){
    check_gitlab_token
    local commit_sha="$1"
    local response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "https://gitlab.com/api/v4/projects/$REPO_OWNER%2F$REPO_NAME/repository/commits/$commit_sha/diff")
    
    # Check if response is valid JSON
    if ! is_valid_json "$response"; then
        echo "Received invalid JSON response from GitLab."
        exit 1
    fi
    
    echo "$response"
}


function get_file_url() {
    local repo_type="$1"
    local commit_sha="$2"
    local file_path="$3"
    
    if [[ $repo_type -eq $GITHUB ]]; then
        echo "https://github.com/$REPO_OWNER/$REPO_NAME/blob/$commit_sha/$file_path"
        elif [[ $repo_type -eq $GITLAB ]]; then
        echo "https://gitlab.com/$REPO_OWNER/$REPO_NAME/-/blob/$commit_sha/$file_path"
    fi
}


function get_duration_in_seconds() {
    local duration="$1"
    local total_seconds=0
    
    # Match days, hours, and minutes
    if [[ $duration =~ ([0-9]+d)?([0-9]+h)?([0-9]+m)? ]]; then
        local days=${BASH_REMATCH[1]//d}
        local hours=${BASH_REMATCH[2]//h}
        local minutes=${BASH_REMATCH[3]//m}
        
        # Convert everything to seconds and sum them up
        total_seconds=$(( (days*86400) + (hours*3600) + (minutes*60) ))
        
        if [[ $total_seconds -eq 0 ]]; then
            echo "Invalid duration format"
            git_hist_inspec_help
            exit 1
        fi
        echo "$total_seconds"
    else
        echo "Invalid duration format"
        git_hist_inspec_help
        exit 1
    fi
}

function get_readable_duration() {
    local total_seconds="$1"
    local days=$((total_seconds / 86400))
    local hours=$(( (total_seconds % 86400) / 3600 ))
    local minutes=$(( (total_seconds % 3600) / 60 ))
    local seconds=$((total_seconds % 60))
    
    local readable_duration=""
    
    [[ $days -gt 0 ]] && readable_duration="${days}d "
    [[ $hours -gt 0 || $days -gt 0 ]] && readable_duration+="${hours}h "
    [[ $minutes -gt 0 || $hours -gt 0 || $days -gt 0 ]] && readable_duration+="${minutes}m "
    readable_duration+="${seconds}s"
    
    echo "$readable_duration"
}

function iso_to_epoch() {
    date --date="$1" +%s
}

function filter_commits() {
    local commits_data="$1"
    local regex="$2"
    local url_type="$3"
    local duration_seconds="$4"
    local matched_commits=0
    
    local duration_ago=$(date -d "@$(($(date +%s) - $duration_seconds))" --iso-8601=seconds | sed 's/+.*//')
    
    local readable_duration=$(get_readable_duration "$duration_seconds")
    
    echo -e "\nCommits matching the regex \"$regex\" within the duration of $readable_duration:\n"
    
    if [ "$commits_data" == "null" ] || [ -z "$commits_data" ]; then
        echo "No commits data received."
        return
    fi
    
    if [[ $url_type -eq $GITHUB ]]; then
        for row in $(echo "${commits_data}" | jq -r '.[] | @base64'); do
            _jq() {
                echo ${row} | base64 --decode | jq -r ${1}
            }
            
            local commit_msg=$(_jq '.commit.message')
            local commit_date=$(_jq '.commit.committer.date')
            local commit_sha=$(_jq '.sha')
            
            if [[ $commit_msg =~ $regex ]] && [[ $commit_date > $duration_ago ]]; then
                echo "${commit_sha:0:8} - $commit_date - $commit_msg"
                matched_commits=$((matched_commits+1))
            else
                local files=$(fetch_github_commit_files "$commit_sha")
                if [[ $files =~ $regex ]] && [[ $commit_date > $duration_ago ]]; then
                    echo "${commit_sha:0:8} - $commit_date - $commit_msg URL: $(get_file_url $GITHUB "$commit_sha" "$regex")"
                    matched_commits=$((matched_commits+1))
                fi
            fi
        done
        elif [[ $url_type -eq $GITLAB ]]; then
        for row in $(echo "${commits_data}" | jq -r '.[] | @base64'); do
            _jq() {
                echo ${row} | base64 --decode | jq -r ${1}
            }
            
            local commit_msg=$(_jq '.title')
            local commit_date=$(_jq '.committed_date')
            local commit_sha=$(_jq '.id')
            
            if [[ $commit_msg =~ $regex ]] && [[ $commit_date > $duration_ago ]]; then
                echo "${commit_sha:0:8} - $commit_date - $commit_msg"
                matched_commits=$((matched_commits+1))
            else
                local files=$(fetch_gitlab_commit_files "$commit_sha")
                if [[ $files =~ $regex ]] && [[ $commit_date > $duration_ago ]]; then
                    local file_url=$(get_file_url $GITLAB "$commit_sha" "$regex")
                    echo "${commit_sha:0:8} - $commit_date - $commit_msg URL: $file_url"
                    matched_commits=$((matched_commits+1))
                fi
                
            fi
        done
    fi
    
    echo -e "\nTotal commits matched: $matched_commits within the duration of $readable_duration for file $regex"
}



function main (){
    
    # Check if help
    if [[ "$1" == "help" ]]; then
        git_hist_inspec_help
        exit 0
    fi
    
    # Check if arguments are provided
    if [[ "$#" -lt 1 ]]; then
        echo "No URL provided"
        git_hist_inspec_help
        exit 1
    fi
    
    # Validate URL
    URL="$1"
    check_valid_url "$URL"
    repo_type=$?
    if [[ $repo_type -eq $GITHUB ]]; then
        echo "GitHub URL detected"
        check_github_token
        elif [[ $repo_type -eq $GITLAB ]]; then
        echo "GitLab URL detected"
        check_gitlab_token
    fi
    
    # Check for valid regex
    if [[ "$#" -gt 1 ]]; then
        regex="$2"
    fi
    
    # Extract repo name and owner
    extract_repo_info "$repo_type"
    
    # Check for valid duration (if provided)
    if [[ "$#" -gt 2 ]]; then
        duration_seconds=$(get_duration_in_seconds "$3")
    else
        duration_seconds=$(get_duration_in_seconds "1d")  # default to 1 day if not provided
    fi
    
    # Get commits
    if [[ $repo_type -eq $GITHUB ]]; then
        COMMITS=$(fetch_github_commits)
        elif [[ $repo_type -eq $GITLAB ]]; then
        COMMITS=$(fetch_gitlab_commits)
    fi
    
    
    # Filter commits based on regex (only if regex provided)
    if [[ -n "$regex" ]]; then
        filter_commits "$COMMITS" "$regex" "$repo_type" "$duration_seconds"
    fi
    
    # Print commits summary
    print_commits_summary "$COMMITS" "$repo_type"
    
}
main "$@"


