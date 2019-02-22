#---------------------------------------------------------
# Declare parameters
#---------------------------------------------------------
[cmdletbinding()]
param (
    [Parameter(Mandatory=$True)]
    [string]    $JiraServer = $( Read-Host "Jira API Endpoint, e.g. https://team.atlassian.net/rest/api/2"),
    [Parameter(Mandatory=$True)]
    [string]    $JiraUser = $( Read-Host "Input JIRA username (user.name@team.com)"),
    [Parameter(Mandatory=$True)]
    [string]    $JiraPassword = $( Read-Host "Input JIRA password"),
    [string]    $Repositories = $( Read-Host "Repositories paths separated with '|' ([./], './|../../../iris-devops|../../../playground')"),
    [Parameter(Mandatory=$True)]
    [string]    $GitAuthor = $( Read-Host "Input git username"),
    [string]    $Month = $(Read-Host "Month ([current], previous)")
)

#---------------------------------------------------------
# Check parameters
#---------------------------------------------------------
if($JiraServer -eq ""){
    throw "ArgumentError JiraServer is not defined"
}
if($JiraUser -eq ""){
    throw "ArgumentError JiraUser is not defined"
}
if($JiraPassword -eq ""){
    throw "ArgumentError JiraPassword is not defined"
}
if($GitAuthor -eq ""){
    throw "ArgumentError GitAuthor is not defined"
}

Write-Host ""

$pwd = Pwd

#---------------------------------------------------------
# Handle params
#---------------------------------------------------------
if($Repositories -eq ""){
    $Repositories = @("./")
} else {
    $Repositories = $Repositories.Split("|")
}

if($Month -eq ""){
    $Month = "current"
}

$inputMonth = $Month

function GetAndFirstLastDatesOfMonth ([datetime] $date) {
    $_nextMonthDate =  $(Get-Date -month $date.Month -day 28 -year $date.Year) + (New-TimeSpan -Days 5)
    $_lastMonthDate = $(Get-Date -month $_nextMonthDate.Month -day 1 -year $_nextMonthDate.Year) - (New-TimeSpan -Days 1)
    $_firstMonthDate = $(Get-Date -month $date.Month -day 1 -year $date.Year)
    Write-Output @($_firstMonthDate, $_lastMonthDate)
}

# Friday, December 15, 2017 -> december
function GetMonthName([datetime] $date){
    $longString = $date.ToLongDateString()
    $longString -match '[^\s]+\s(\w+)\s.+'
    $curMonth = $Matches[1].ToLower()
    Write-Output $curMonth
}

$date = Get-Date
$firstCurrentMonthDate = $(Get-Date -month $date.Month -day 1 -year $date.Year)

if($month -eq "current"){
    $boarders = $(GetAndFirstLastDatesOfMonth $date)
    $lastMonthDate = $boarders[1]
    $Month = $(GetMonthName $date)[1]
} elseif($month -eq "previous") {
    $firstCurrentMonthDate = $(Get-Date -month $date.Month -day 1 -year $date.Year)
    $lastMonthDate = $firstCurrentMonthDate - (New-TimeSpan -Days 1)
    $Month = $(GetMonthName $lastMonthDate)[1]
} else {
    throw "Month value is not supported"
}

$lastMonthDay = $lastMonthDate.Day

Write-Host ""

#---------------------------------------------------------
# Get git logs
#---------------------------------------------------------
$index=0
$fileList = @()
 foreach ($repository in $Repositories) {
    pushd .
    cd $repository
    $fileName = "$pwd\git-$Month-$index.csv"
    Write-Host "Updating git repo"
    & git fetch
    Write-Host "Requesting data from GIT: git log --author=$GitAuthor --format=`"%cd|%s`" --date=short --since=`"1 $Month`" --until=`"$lastMonthDay $Month`" --no-merges --reverse --branches --remotes > `"$fileName`""
    & git log --author=$GitAuthor --format="%cd|%s" --date=short --since="1 $Month" --until="$lastMonthDay $Month" --no-merges --reverse --branches --remotes > "$fileName"
    $index++
    $fileList += $fileName
    popd
 }
 

#---------------------------------------------------------
# Request issues with Jira's REST API
#---------------------------------------------------------
$bytes = [System.Text.Encoding]::UTF8.GetBytes("$JiraUser`:$JiraPassword")
$global:encodedCredentials = [System.Convert]::ToBase64String($bytes)

$jqlQuery = ""

$JiraUserShort = $JiraUser.Split("@")[0]

 if($inputMonth -eq "current"){
    $jqlQuery = "((status=Done OR status=Closed) AND (assignee=$JiraUserShort) AND (updatedDate>startOfMonth(0))) order by updatedDate ASC"
 } elseif($inputMonth -eq "previous") {
    $jqlQuery = "((status=Done OR status=Closed) AND (assignee=$JiraUserShort) AND (updated>startOfMonth(-1)) AND (updated<startOfMonth(0))) order by updated ASC"
 }

 Write-Host "Running JQL: $jqlQuery"
 
Try
{
  $resturi="$JiraServer/search?jql=$jqlQuery&fields=summary,updated,lastUpdated&maxResults=200&expand=issues"
  $WebRequest = [System.Net.WebRequest]::Create($resturi)
  $WebRequest.Headers["Authorization"] = "Basic " + $global:encodedCredentials;
  $WebRequest.Method = "GET"
         
  [System.Net.WebResponse] $resp = $WebRequest.GetResponse();
  $rs = $resp.GetResponseStream();
  [System.IO.StreamReader] $sr = New-Object System.IO.StreamReader -argumentList $rs;
  [string] $results = $sr.ReadToEnd();
  $resp.Close()

  $fileName = "$pwd\jira-$Month-$index.csv"
  $selection = $results | ConvertFrom-Json | Select -expand issues | select key -expand fields | select updated, key, summary
  $selection | ForEach-Object {[String]::Format('{0}|{1} {2}', $_.updated.ToString().Substring(0,10), $_.key, $_.summary)} | Out-File "$fileName"

  $fileList += $fileName
}
Catch
{
  Write-Host("---------------------------------------------------------");
  Write-Host "Error while requesting $JiraServer"
  $ErrorMessage = $_.Exception.Message
  $FailedItem = $_.Exception.ItemName
  Write-Host ($jirakey + ": " + $FailedItem + " - The error message was " + $ErrorMessage)
  Write-Host("---------------------------------------------------------");
  $errorJira = true
  exit 1
}

#---------------------------------------------------------
# Merge
#---------------------------------------------------------
$mergedFileName = "$pwd\merged-$Month.csv"
foreach($file in $fileList){
    Get-Content $file | Out-File -FilePath $mergedFileName -Encoding UTF8 -Append
}
$mergedSortedFileName = "$pwd\mergedsorted-$Month.csv"
Get-Content $mergedFileName | sort | get-unique > $mergedSortedFileName

#---------------------------------------------------------
# Group
#---------------------------------------------------------
$groups = Get-Content $mergedSortedFileName | ForEach-Object {  [PSCustomObject]@{ 
    Date = $_.Split("|")[0]
    Text = $_.Split("|")[1] + ";"
    }
} | Group-Object Date 


Write-Host ""
Write-Host "========================================================"
Write-Host "Monthly report"
Write-Host "For the user:", "$JiraUser@jira or $GitAuthor@git"
Write-Host "Month:", $Month, "[", 1, ", ", $lastMonthDay,  "]"
Write-Host "========================================================"

foreach($group in $groups){
    Write-Host "=========="
    Write-Host $group.Name
    Write-Host "=========="
    foreach($obj in $group.Group){
        Write-Host $obj.Text
    }
    Write-Host ""
}