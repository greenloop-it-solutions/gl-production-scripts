# For this specific script, all WiFi networks have a corresponding "network" with the SSID in the name. This matches them and updates the WLAN objects as needed.
# Login 
$cred = Get-Credential -Message "Give UniFi portal Admin creds:"

# UniFi Details
$UniFiFqdn = Read-Host "Provide the FQDN of your UniFi server. Don't include https:// port, or the rest of the URL string."
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

$siteID = Read-Host -Prompt "Provide the UniFi Site ID"

# get all wifi networks
$wifinetworks = (Invoke-RestMethod -Method Get -Uri "$($UnifiBaseUri)/s/$($siteID)/rest/wlanconf" -WebSession $websession).data
# get all networkconf objects
$networks = (Invoke-RestMethod -Method Get -Uri "$($UnifiBaseUri)/s/$($siteID)/rest/networkconf" -WebSession $websession).data

foreach ($wifinetwork in $wifinetworks) {
    Write-Host "Wifi network $($wifinetwork.name)"
    # get the network where the name is a match
    $network = $networks | ? {$_.name -like "V$($wifinetwork.name)-*"} #this is the match pattern for this particular job.
    # compare IDs
    if ($($wifinetwork.networkconf_id ) -ne $($network._id)) {
        Write-Host "No match found. Updating"
        #    update if necessary
        
        $body = @{
            networkconf_id = $network._id
        } | ConvertTo-Json

        Invoke-RestMethod -Method PUT -Uri "$($UnifiBaseUri)/s/$($siteID)/rest/wlanconf/$($wifinetwork._id)" -WebSession $websession -Body $body
    }
}
