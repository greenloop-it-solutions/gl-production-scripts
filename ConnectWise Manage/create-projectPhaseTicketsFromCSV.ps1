# S. Moody 2/16/2021
# This script creates a set of sequentially numbered project sub-tickets from user contact information provided in a CSV. Tickets under the designated phase given the provided inputs.
# Each ticket will use the provided Displayname and email address and are suitable for creating a custom TimeZest invite for each user.
#currently does NOT populate phone numbers, so make sure to use a TimeZest appt. type that requires user to provide a callback number and populates it into the ticket!

#get user input
$userAPIcompany = Read-Host "Provide the Manage company name"
$userAPIpublickey = Read-Host "Provide your public API key for Manage"
$userAPIprivatekey = Read-Host "Provide your private API key for Manage"
$manageServerFqdn = Read-Host "Provide the FQDN of your Manage server. Do not use https:// or a trailing slash!"
$ClientNameString = Read-Host "Please Enter the first part of the company name. No wildcard required."
$ProjectNameString = Read-Host "Please Enter the Project Name, exactly as it appears in Manage."
$projectPhase = Read-Host "Enter the 'WBS' project phase (i.e. '2' or '3.2') to use for these tickets. It needs to already exist!"
$csvFilePath = Read-Host "Enter the full file system path to your CSV file. It should have headers, with columns for DisplayName and EmailAddress."
$ticketSummary = Read-Host "Provide a brief description for these tickets, to go in the summary line."

$manage_base_url = "https://$($manageServerFqdn)/v4_6_release/apis/3.0/"

#set up the Basic auth header
$pair = "$($userAPIcompany)+$($userAPIpublickey):$($userAPIprivatekey)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCreds"

#load other headers
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", $basicAuthValue)
$headers.Add("Content-Type", "application/json")
$headers.Add("clientid", "2628d75d-c2ea-43c4-bac4-33ea7181d0d6")

#find the project
$request_url = $manage_base_url + "project/projects?conditions=company/name LIKE `'$ClientNameString*`' AND name = `'$ProjectNameString`'"
$response = Invoke-RestMethod $request_url -Method 'GET' -Headers $headers

#only proceed if we get exactly one result
if ($response.Count -eq 1) {
    $projectId = $response.id

    #get the project phase
    $request_url = $manage_base_url + "project/projects/$($projectId)/phases?conditions=wbsCode = `'$projectPhase`'"
    $response = Invoke-RestMethod $request_url -Method 'GET' -Headers $headers

    if ($response.Count -eq 1) {
        $phaseId = $response.id
        $users = import-csv -Path $csvFilePath

        $counter = 1
        #create a ticket for each user
        foreach ($user in $users) {
            $username = $user.DisplayName
            $request_url = $manage_base_url + "project/tickets"
            $summary = "$($projectPhase).$($counter) $ticketSummary | $username"
            $body = @{
                summary = $summary 
                project = @{
                    id = $projectId
                }
                phase = @{
                    id = $phaseId
                }
                contactName = $username
                contactEmailAddress = $($user.EmailAddress)

            } | ConvertTo-Json

            $response = Invoke-RestMethod $request_url -Method 'POST' -Headers $headers -Body $body
            Write-Host "Ticket $($response.id) created for $username."
            $counter++
        }
    } else {
        Write-Host "We got $($response.Count) results, which is unexpected. Please adjust your Project Phase code and try again."
    } 

} else {
    Write-Host "We got $($response.Count) results, which is unexpected. Please adjust your search terms and try again."
}
