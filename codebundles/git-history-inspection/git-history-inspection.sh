#!/bin/bash
# ======================================================================================
# Synopsis:
# - A informative formatted summary of recent commit messages, their short-shas, and timestamps from GitHub or GitLab URLs
# - A list of commits/timestamps/short-shas who's filenames or commit messages match a regex (eg: so it can be configured to pull info for everything related to a backend microservice) and provide some stats such as: X backend files changed in last 6 hours
# - If possible, reconstruct the git URLs for the detected files (gitlab or github) and provide those URLs in the raised issues if the regex finds matches
# @author: Zeke Critchlow

declare -g REPO_OWNER=""
declare -g GITHUB=0
declare -g REPO_NAME=""
declare -g GITLAB=1
declare -g COMMITS=""
declare -g URL=""
declare -g SEARCH_FILES=0


# Help function
# Usage: git-hist-inspec help
# Prints help message
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
    To avoid rate limits and access private repositories, you need to set authentication tokens.
    For GitHub: Export GITHUB_TOKEN environment variable.
    For GitLab: Export GITLAB_TOKEN environment variable.

    Examples:
        git-hist-inspec https://github.com/username/repo A_File\.txt 6h
        git-hist-inspec https://github.com/username/repo A_File\.txt 2d3h15m
    "
}


# Extracts repo owner and name from URL
# Usage: extract_repo_info <url_type>
# url_type: 0 for GitHub, 1 for GitLab
function extract_repo_info(){
    local url_type="$1"
    local owner=""
    local repo=""
    
    if [[ $url_type -eq $GITHUB ]]; then
        # GitHub
        REPO_OWNER=$(echo "$URL" | sed -n 's/.*github.com\/\([^\/]*\)\/\([^\/]*\).*/\1/p')
        REPO_NAME=$(echo "$URL" | sed -n 's/.*github.com\/\([^\/]*\)\/\([^\/]*\).*/\2/p')
        elif [[ $url_type -eq $GITLAB ]]; then
        # GitLab
        REPO_OWNER=$(echo "$URL" | sed -n 's/.*gitlab.com\/\([^\/]*\)\/\([^\/]*\).*/\1/p')
        REPO_NAME=$(echo "$URL" | sed -n 's/.*gitlab.com\/\([^\/]*\)\/\([^\/]*\).*/\2/p')
    fi
}

# Checks if URL is valid
# Usage: check_valid_url <url>
# Returns 0 for GitHub, 1 for GitLab
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


# Checks if string is valid JSON
# Usage: is_valid_json <string>
# Returns 0 if valid, 1 if invalid
function is_valid_json() {
    echo "$1" | jq . >/dev/null 2>&1
}


# Checks if GitHub commits rate limit exceeded
# Usage: check_github_commits_rate_limit <response>
# Exits if rate limit exceeded
function check_github_commits_rate_limit() {
    local response="$1"
    
    if echo "$response" | jq -e '.[] | select(.message != null) | .message | contains("Rate limit exceeded")' >/dev/null; then
        echo "Rate limit exceeded for GitHub commits. Please try again later or authenticate your requests."
        exit 1
    fi
}


# Checks if GitHub files rate limit exceeded
# Usage: check_github_files_rate_limit <response>
# Exits if rate limit exceeded
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



# Checks if GitLab rate limit exceeded
# Usage: check_gitlab_rate_limit <response>
# Exits if rate limit exceeded
function check_gitlab_rate_limit() {
    local response="$1"
    # Check every object in the array for "message" field
    if echo "$response" | jq -e '.[] | select(.message? | contains("Rate limit exceeded"))' >/dev/null; then
        echo "Rate limit exceeded for GitLab. Please try again later or authenticate your requests."
        exit 1
    fi
}


# Checks if GitHub token is set
# Usage: check_github_token
# Exits if not set
function check_github_token() {
    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo "GITHUB_TOKEN environment variable not set. Please set it to proceed."
        exit 1
    fi
}


# Checks if GitLab token is set
# Usage: check_gitlab_token
# Exits if not set
function check_gitlab_token() {
    if [[ -z "$GITLAB_TOKEN" ]]; then
        echo "GITLAB_TOKEN environment variable not set. Please set it to proceed."
        exit 1
    fi
}


# Prints commits summary
# Usage: print_commits_summary <url_type>
# url_type: 0 for GitHub, 1 for GitLab
function print_commits_summary() {
    local url_type="$1"
    
    echo "Summary of recent commits:"
    if [[ $url_type -eq $GITHUB ]]; then
        # GitHub
        # Check if rate limit exceeded
        check_github_commits_rate_limit "$COMMITS"
        echo "$COMMITS" | jq -r '.[] | "\(.sha[0:8]) - \(.commit.committer.date) - \(.commit.message)"'
        elif [[ $url_type -eq $GITLAB ]]; then
        # GitLab
        echo "$COMMITS" | jq -r '.[] | "\(.short_id) - \(.committed_date) - \(.title)"'
    fi
}


# Fetches recent commits from GitHub
# Usage: fetch_recent_github_commits
# Sets COMMITS variable
function fetch_recent_github_commits() {
    local full_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/commits")
    
    check_github_commits_rate_limit "$full_response"
    
    COMMITS="$full_response"
}


# Fetches recent commits from GitLab
# Usage: fetch_recent_gitlab_commits
# Sets COMMITS variable
function fetch_github_commits() {
    
    local all_commits=""
    local page=1
    local per_page=100
    local limit=30
    
    local current_time_epoch=$(date +%s)
    local duration_ago_epoch=$(($current_time_epoch - $duration_seconds))
    
    while : ; do
        
        local full_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -i "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/commits?page=$page&per_page=$per_page")
        
        # Extract Link header
        local link_header=$(echo "$full_response" | grep -i '^link:' | sed 's/^link:/LINK:/I')
        
        # Separate headers from JSON body
        local response=$(echo "$full_response" | awk '/^\[/{p=1} p')
        
        # Check if rate limited
        check_github_commits_rate_limit "$response"
        
        # Check if the last commit in this page is older than our duration
        local last_commit_date=$(echo "$response" | jq -r '.[-1].commit.committer.date')
        local last_commit_epoch=$(date --date="$last_commit_date" +%s)
        
        all_commits+="$response"
        
        if [[ $last_commit_epoch -lt $duration_ago_epoch ]]; then
            echo "All commits within the duration fetched."
            break
        fi
        
        # Check the Link header for the absence of "next" to determine end of pages
        if [[ ! $link_header == *rel=\"next\"* ]]; then
            echo "No more pages to fetch. Reached the end of commits."
            break
        fi
        
        page=$((page + 1))
    done
    
    COMMITS="$all_commits"
}


# Fetches recent commits from GitLab
# Usage: fetch_recent_gitlab_commits
# Sets COMMITS variable
function fetch_github_commit_files() {
    local commit_sha="$1"
    local response
    
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/commits/$commit_sha")
    check_github_files_rate_limit "$response"
    
    echo "$response"
}


# Fetches recent commits from GitLab
# Usage: fetch_recent_gitlab_commits
# Sets COMMITS variable
function fetch_recent_gitlab_commits(){
    local response
    response=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "https://gitlab.com/api/v4/projects/$REPO_OWNER%2F$REPO_NAME/repository/commits")
    check_gitlab_rate_limit "$response"
    
    COMMITS="$response"
}


# Fetches recent commits from GitLab
# Usage: fetch_recent_gitlab_commits
# Sets COMMITS variable
function fetch_gitlab_commits() {
    
    local all_commits=""
    local page=1
    local per_page=100
    local current_time_epoch=$(date +%s)
    local duration_ago_epoch=$(($current_time_epoch - $duration_seconds))
    
    while : ; do
        
        local full_response=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -i "https://gitlab.com/api/v4/projects/$REPO_OWNER%2F$REPO_NAME/repository/commits?page=$page&per_page=$per_page")
        
        # Extract next page from header
        local next_page=$(echo "$full_response" | grep -i '^x-next-page:' | sed -n 's/^x-next-page: //p')
        
        # Separate headers from JSON body
        local response=$(echo "$full_response" | awk '/^\[/{p=1} p')
        
        # Check if rate limited
        check_gitlab_rate_limit "$response"
        
        # Check if the last commit in this page is older than our duration
        local last_commit_date=$(echo "$response" | jq -r 'if .[-1] then .[-1].committed_date else null end')
        
        if [ "$last_commit_date" != "null" ]; then
            local last_commit_epoch=$(date --date="$last_commit_date" +%s)
        else
            last_commit_epoch=0
        fi
        
        all_commits+="$response"
        
        if [[ $last_commit_epoch -lt $duration_ago_epoch ]]; then
            echo "All commits within the duration fetched."
            break
        fi
        
        # Check the absence of "x-next-page" to determine end of pages
        if [[ -z "$next_page" ]]; then
            echo "No more pages to fetch. Reached the end of commits."
            break
        fi
        
        page=$((page + 1))
    done
    
    COMMITS="$all_commits"
}


# Fetches recent commits from GitLab
# Usage: fetch_recent_gitlab_commits
# Sets COMMITS variable
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


# Fetches recent commits from GitLab
# Usage: fetch_recent_gitlab_commits
# Sets COMMITS variable
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


# Converts duration to seconds
# Usage: get_duration_in_seconds <duration>
# duration: e.g. 3d, 6h, 15m, 2d3h15m
# Returns duration in seconds
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


# Converts seconds to human readable format
# Usage: get_readable_duration <seconds>
# seconds: e.g. 86400, 3600, 60, 1
# Returns duration in human readable format
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


# Converts ISO-8601 date to epoch
# Usage: iso_to_epoch <iso_date>
# iso_date: e.g. 2019-10-15T13:00:00+02:00
# Returns epoch time
function iso_to_epoch() {
    date --date="$1" +%s
}


# Filters commits based on regex
# Usage: filter_commits <regex> <url_type> <duration_seconds>
# regex: e.g. A_File\.txt
# url_type: 0 for GitHub, 1 for GitLab
# duration_seconds: e.g. 86400, 3600, 60, 1
function filter_commits() {
    local regex="$1"
    local url_type="$2"
    local duration_seconds="$3"
    local matched_commits=0
    
    local duration_ago=$(date -d "@$(($(date +%s) - $duration_seconds))" --iso-8601=seconds | sed 's/+.*//')
    
    local readable_duration=$(get_readable_duration "$duration_seconds")
    
    echo -e "\nCommits matching the regex \"$regex\" within the duration of $readable_duration:\n"
    
    if [ "$COMMITS" == "null" ] || [ -z "$COMMITS" ]; then
        echo "No commits data received."
        return
    fi
    
    if [[ $url_type -eq $GITHUB ]]; then
        for row in $(echo "${COMMITS}" | jq -r '.[] | @base64'); do
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
        for row in $(echo "${COMMITS}" | jq -r '.[] | @base64'); do
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
        SEARCH_FILES=1
    else
        duration_seconds=$(get_duration_in_seconds "1d")
    fi
    
    # Get commits
    if [[ $repo_type -eq $GITHUB ]]; then
        
        if [[ $SEARCH_FILES -eq 1 ]]; then
            fetch_github_commits
            
        else
            fetch_recent_github_commits
        fi
        
        elif [[ $repo_type -eq $GITLAB ]]; then
        
        if [[ $SEARCH_FILES -eq 1 ]]; then
            fetch_gitlab_commits
            
        else
            fetch_recent_gitlab_commits
        fi
        
    fi
    
    
    # Filter commits based on regex (only if regex provided)
    if [[ -n "$regex" ]]; then
        filter_commits "$regex" "$repo_type" "$duration_seconds"
        exit 0
    fi
    
    # Print commits summary
    print_commits_summary "$repo_type"
    
}
main "$@"


