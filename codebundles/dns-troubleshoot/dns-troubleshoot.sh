#! /bin/bash
# ======================================================================================
# Synopsis:
# - DNS resolution differs between DNS servers and available config info (is it still propagating?)
# - Is the information from dig/nslookup correct with the applied configuration for the server?
# - Are there any problems with the DNS records?
# - Raises issues for these cases when an issue is detected
# @author: Zeke Critchlow

# List of DNS servers to test against
dns_servers=("8.8.8.8" "1.1.1.1")

# Domain to check
domain="example.com"


check_dns_resolution() {
    local server=$1
    echo "Checking DNS resolution for $domain using server $server"
    dig @$server $domain +short
}


compare_dns_resolutions(){
    local -n resolutions=$1
    local prev_resolution=""
    for resolution in "${resolutions[@]}"; do
        if [ "$prev_resolution" != "" ] && [ "$prev_resolution" != "$resolution" ]; then
            echo "DNS resolution differs between servers"
            return 1
        fi
        prev_resolution=$resolution
    done
    echo "DNS resolution is the same across servers"
}


# Main execution
dns_results=()
for dns_server in "${dns_servers[@]}"; do
    result=$(check_dns_resolution $dns_server)
    dns_results+=("$result")
done

compare_dns_resolutions dns_results