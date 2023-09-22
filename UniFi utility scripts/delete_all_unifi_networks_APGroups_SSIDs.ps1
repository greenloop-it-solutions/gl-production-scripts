# built this in conjunction with the create_unifi_networks_from_CSV script. Need to clear stuff out completely when debugging. Use with care, obviously.
# $siteID = abcd1234 # fill this in and uncomment if you need to (but if you're using that other script it may already be populated)

$wifinetworks = Invoke-RestMethod -Method Get -Uri "$($UnifiBaseUri)/s/$($siteID)/rest/wlanconf" -WebSession $websession

foreach ($wifinetwork in $($wifinetworks.data)) {
    Invoke-RestMethod -Method Delete -Uri "$($UnifiBaseUri)/s/$($siteID)/rest/wlanconf/$($wifinetwork._id)" -WebSession $websession
}

$APgroups = Invoke-RestMethod -Method Get -Uri "https://$($UniFiFqdn):8443/v2/api/site/$($siteID)/apgroups" -WebSession $websession -ContentType "application/json" #this uses the v2 api for some reason

foreach ($APGroup in $APgroups) {
    Invoke-RestMethod -Method Delete -Uri "https://$($UniFiFqdn):8443/v2/api/site/$($siteID)/apgroups/$($ApGroup._id)" -WebSession $websession -ContentType "application/json"
} #the default group will throw an error and not be deleted

$networks = Invoke-RestMethod -Method Get -Uri "$($UnifiBaseUri)/s/$($siteID)/rest/networkconf" -WebSession $websession

foreach ($network in $($networks.data)) {
    Invoke-RestMethod -Method Delete -Uri "$($UnifiBaseUri)/s/$($siteID)/rest/networkconf/$($network._id)" -WebSession $websession
}#the default networks will throw errors and not be deleted
