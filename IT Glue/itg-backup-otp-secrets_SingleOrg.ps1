<# To obtain a bearer token, make sure to log into IT Glue first, enable developer tools (F12) and do the following:
    1. Reload the page and click on the 'Network' tab
    2. Find any password in IT Glue and click 'Show Password or 'Show OTP' on the left hand side
    3. In the developer tools on the right, click on the last 'Get' command (ending with 'show_password=true')
    4. Under the 'Headers' tab, scroll down to the 'Request Headers' and find 'Authorization'
    5. Copy everything after the word 'Bearer'
    6. Paste this token when prompted
    This version backs up tokens for a single Organization, specified by Org ID.
#>
$OrgID = Read-Host 'Enter IT Glue Org ID to export OTP secrets for'
$Token = Read-Host 'Enter Bearer Token'
$APIEndpoint = 'https://itg-api-prod-api-lb-us-west-2.itglue.com'
$resource_uri = "/api/organizations/$OrgID/relationships/passwords"
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/vnd.api+json")
$headers.Add("Accept", "application/json, text/plain")
$headers.Add("Authorization", "Bearer $Token")
$page = 1
$otpEnabled = $null
do {
    $ExistingPasswordAsset = Invoke-RestMethod -Method 'GET' -uri ($APIEndpoint + $resource_uri +"?page[number]=$page&page[size]=1000") -headers $headers
    $otpEnabled += $ExistingPasswordAsset.data | Where-Object {$_.attributes."otp-enabled" -eq $true}
    Write-Host "Working on page $page. Passwords found so far: $($otpEnabled.Count)"
    $page++
} while ($ExistingPasswordAsset.meta.'next-page' -ne $null)
$objects = foreach ($id in $otpEnabled.Id) {
    $attribs = (Invoke-RestMethod -Method Get -Uri ($APIEndpoint + "/api/passwords/$($id)?show_password=true") -Headers $headers).data.attributes
    $attribs | Select-Object name,organization-id,organization-name,username,password,resource-url,password-category-name,otp-secret
}
Write-Host "Exporting passwords to $env:Temp\OTPSecrets$OrgID.csv" -ForegroundColor Green
ii $env:Temp
