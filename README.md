# Time Reporting
Script takes logs from several git repositories, jira and merges them in one pretty file for time reporting purposes.

Currently supported sources:
- Git repositories
- Atlassian Jira

## Run
Run it with:
    
    powershell ./time.report.ps1 > out

## Parameters
    -JiraServer   Jira API endpoint, example "https://domain.atlassian.net/rest/api/2", where domain is your team name in Jira
    -JiraUser     User name in Jira, example user.name@domain.com
    -JiraPassword Password
    -Repositories List of local paths to git repositories separated by '|', exaples: './', './|../../../repo|../../../repo2'
    -GitAuthor    Name of the Git user, should correspond to git configuration param 'user.name'
    -Month        Month, may be on of 'current' or 'previous'

## Troubleshooting

### Restricted Script Execution in Windows
If you have the following problem with running PS script at the target machine:

    File time.report.ps1 cannot be loaded because the execution of scripts is disabled on this system. Please see "get- help about_signing" for more details.

then run the following line under admin rights:
     
     Set-ExecutionPolicy RemoteSigned
