# Utility script that takes a list of Rooms/Network IDs, VLAN IDs, WiFI Passwords and creates networks and SSIDs accordingly
# there will be a one-to-one-to-one relationship between networks/AP Groups/SSIDs
# note that out of the box UniFi has a limit of 64 networks. If you want more you can either: add a UXG or set the system.properties value unifi.network.limit=256 (or some other large enough value)
# thanks to https://community.ui.com/questions/Software-Based-Controller-limit-VLANS-to-be-maximum-64/6f8ec8a7-ce1b-4476-9d1f-9955cda6a053#answer/468a5c80-efb8-4e19-a233-dae510b9f6ba

# Loads a CSV file. It is expecting "Room",SSW, PW fields
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
    Filter = 'Text Files (*.csv)|*.csv'
}
$null = $FileBrowser.ShowDialog()

$NetworksList = Import-Csv $FileBrowser.FileName

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
$networkCounter = 1 #if we never needed more than 254 we'd have to do something different here

foreach ($network in $NetworksList) {
    Write-Output "Working with Network $($network.Room):"
    
    # 1. Create the Network. Note that UniFi supports a maximum of 64 networks with VLANs. (as opposed to VLAN-only networks).
    $body = @{
        purpose = "guest" #change this to reflect the network type you want. guest,corporate,vlan-only. for vlan-only it you'll want to comment out DHCP-related lines below.
        networkgroup = "LAN"
        dhcpd_enabled = $true
        dhcpd_leasetime = 86400
        dhcpd_dns_enabled = $false
        dhcpd_gateway_enabled = $false
        dhcpd_time_offset_enabled = $false
        ipv6_interface_type = "none"
        ipv6_pd_start = "::2"
        ipv6_pd_stop = "::7d1"
        gateway_type = "default"
        nat_outbound_ip_addresses = @()
        name = "V$($network.SSW)-R$($network.Room)"
        vlan = "$($network.SSW)"
        ip_subnet = "10.0.$($networkCounter).1/24"
        dhcpd_start = "10.0.$($networkCounter).100"
        dhcpd_stop = "10.0.$($networkCounter).199"
        setting_preference = "manual"
        enabled = $true
        is_nat = $true
        dhcp_relay_enabled = $false
        vlan_enabled = $true
    } | ConvertTo-Json

    $networkObj = Invoke-RestMethod -Method Post -Uri "$($UnifiBaseUri)/s/$($siteID)/rest/networkconf" -body $body -WebSession $websession

    # 2. Create the AP Group
    $body = @{
        device_macs = @()
        name = "$($network.Room)"
    } | ConvertTo-Json

    $APgroupObj = Invoke-RestMethod -Method Post -Uri "https://$($UniFiFqdn):8443/v2/api/site/$($siteID)/apgroups" -body $body -WebSession $websession -ContentType "application/json" #this uses the v2 api for some reason
    
    # 3. Create the SSID
    $body = @{
        enabled = $true
        wpa3_support = $false
        wpa3_transition = $false
        security = "wpapsk"
        wep_idx = "1"
        wpa_mode = "wpa2"
        wpa_enc = "ccmp"
        pmf_mode = "disabled"
        pmf_cipher = "auto"
        usergroup_id = "6418847e2ed301023c17812e" #this is the default usergroup id in our instance
        wlan_band = "both"
        ap_group_ids = @($($APGroupObj._id))
        dtim_mode = "default"
        dtim_ng = 1
        dtim_na = 3
        minrate_setting_preference = "auto"
        minrate_ng_data_rate_kbps = 1000
        minrate_na_data_rate_kbps = 6000
        mac_filter_enabled = $false
        mac_filter_policy= "allow"
	    mac_filter_list = @()
        bc_filter_enabled = $false
        bc_filter_list = @()
        group_rekey = 3600
        hotspot2conf_enabled =  $false
        bss_transition = $true
        auth_cache = $true
        schedule_enabled = $false
	    name = "$($network.SSW)"
        x_passphrase = "$($network.PW)"
	    networkconf_id = "$($networkObj._id)"
	    setting_preference = "manual"
	    radius_das_enabled = $false
    } | ConvertTo-Json

    $wlanObj = Invoke-RestMethod -Method Post -Uri "$($UnifiBaseUri)/s/$($siteID)/rest/wlanconf" -body $body -WebSession $websession

    Write-Output "Done!"
    $networkCounter++
}
