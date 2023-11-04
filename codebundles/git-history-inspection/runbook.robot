*** Settings ***
Metadata    Author    Zeke Critchlow
Documentation    This is a git history inspection tool
Force Tags    Git    History    Inspection    Tool
Library    RW.Core
Library    RW.CLI
Library    OperatingSystem

Suite Setup       Suite Initialization


*** Variables ***
${BASH_SCRIPT}    ./git-history-inspection.sh

*** Keywords ***
Suite Initialization
    ${GITLAB_TOKEN}=    RW.Core.Import Secret
    ...    GITLAB_TOKEN
    ...    type=string
    ...    pattern=\w*

    ${GITHUB_TOKEN}=    RW.Core.Import Secret
    ...    GITHUB_TOKEN
    ...    type=string
    ...    pattern=\w*
    

    ${URL}=    RW.Core.Import User Variable    URL
    ...    type=string
    ...    description=The URL to inspect
    ...    pattern=http.*
    ...    example=http://example.com

    ${REGEX_PATTERN}=    RW.Core.Import User Variable    REGEX_PATTERN
    ...    type=string
    ...    description=Filename to find in the git history
    ...    pattern=\w*
    ...    example=README.md

    ${INSPECTION_DURATION}=    RW.Core.Import User Variable    INSPECTION_DURATION
    ...    type=string
    ...    description=Time to wait after executing the script
    ...    pattern=\w*
    ...    example=1d3h15m

    Set Suite Variable    ${URL}    ${URL}
    Set Suite Variable    ${REGEX_PATTERN}    ${REGEX_PATTERN}
    Set Suite Variable    ${INSPECTION_DURATION}    ${INSPECTION_DURATION}

*** Tasks ***
Inspect Git Repository
    [Documentation]    Inspect the git history of a GitHub or GitLab URL
    [Tags]    info git history inspection
    ${result}=   RW.CLI.Run Bash File 
    ...    bash_file=git-history-inspection.sh 
    ...    cmd_args=${BASH_SCRIPT} ${URL} ${REGEX_PATTERN} ${INSPECTION_DURATION} 
    ...    secret__GITLAB_TOKEN=${GITLAB_TOKEN} 
    ...    secret__GITHUB_TOKEN=${GITHUB_TOKEN}
    RW.Core.Add Pre To Report    ${result}
    
    
