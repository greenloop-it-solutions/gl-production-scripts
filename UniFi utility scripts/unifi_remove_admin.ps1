#This script removes a specified UniFi Admin/SuperAdmin from all sites. 

$admin_to_remove = Read-Host "Specify the registered email address of the user you want to remove"

$cred = Get-Credential -Message "Give UniFi portal SuperAdmin creds:"

# UniFi Details
$UniFiFqdn = Read-Host "provide the FQDN of your UniFi instance. Leave off the https:// and any slashes!"
$UnifiBaseUri = "https://" + $UniFiFqdn + ":8443/api"
$UnifiCredentials = @{
    username = $cred.UserName
    password = $cred.GetNetworkCredential().password
    remember = $true
} | ConvertTo-Json

#may be necessary to negotiate to TLS1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#login to UniFi to start a session
Invoke-RestMethod -Uri "$UnifiBaseUri/login" -Method POST -Body $UnifiCredentials -SessionVariable websession

#Get list of all admins
$admins = (Invoke-RestMethod -Uri "$UnifiBaseUri/stat/admin" -WebSession $websession).data

#pick the one we want to remove out of the list
$admin = $admins | ? {$_.email -eq $admin_to_remove }
#get the id too
$admin_id = $admin._id

#now for the good stuff

#revoke super admin
if ($admin.is_super) {
    Invoke-WebRequest -Uri "$UnifiBaseUri/s/default/cmd/sitemgr" -Method "POST" -WebSession $websession  -Body "{`"cmd`":`"revoke-super-admin`",`"admin`":`"$admin_id`"}"
}

#get a list of all site permissions
$admin_roles = $admin.roles

#we'll remove them one at a time
Foreach ($role in $admin_roles) {

    $site_name = $role.site_name
    
    Invoke-WebRequest -Uri "$UnifiBaseUri/s/$site_name/cmd/sitemgr" -Method "POST"  -WebSession $websession  -Body "{`"admin`":`"$admin_id`",`"cmd`":`"revoke-admin`"}"
}
