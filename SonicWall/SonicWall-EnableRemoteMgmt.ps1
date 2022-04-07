<#
.SYNOPSIS
Enables HTTPS Remote Management for SonicWALL firewalls.
.DESCRIPTION
This script will enable HTTPS Remote Management, Ping, disable HTTP Redirect, and lock down the WAN interface
to only specified IP Addresses.
.NOTES
The API is not enabled by default in SonicOS 6 and will need to be turned on before running this script
In addition, both OS versions (6 & 7) will need 2FA turned on:
    1. Enable TOTP for the admin user account and then turn on the API
    2. Enable 'Two-Factor and Bearer Token Authentication' - disable the rest (if possible)
    3. Save/Accept the settings and log out
    4. Finish setting up 2FA for the firewall and document the scratch code in IT Glue
    5. Run this script
.LINK
How to enable the SonicOS API:
https://www.sonicwall.com/techdocs/pdf/sonicos-6-5-system-setup.pdf (page 45)
https://www.sonicwall.com/techdocs/pdf/sonicos-7-0-0-0-device_settings.pdf (page 23)
GL version for Gen7: https://greenloop.itglue.com/DOC-1286312-7728669
#>

param (
    [Parameter(Mandatory)]
    [ipaddress]
    $IPAddress
)

# Set the error action preference and suppress progress information from 'Test-NetConnection'
$ErrorActionPreference = 'Stop'
$global:ProgressPreference = 'SilentlyContinue'

# Test port connectivity on 8443
$port = Test-NetConnection -ComputerName $IPAddress -Port 8443 -InformationLevel Quiet -WarningAction SilentlyContinue
if (-not ($port)) {
    throw "Unable to connect on port 8443. Check the firewall and try again."
} else {
    $url = "https://$($IPAddress):8443"
}

# Declare API endpoints
$endpointURI = @{
    tfa                   = $url + '/api/sonicos/tfa'
    auth                  = $url + '/api/sonicos/auth'
    addressObjipv4        = $url + '/api/sonicos/address-objects/ipv4'
    addressObjipv4UUID    = $url + '/api/sonicos/address-objects/ipv4/uuid'
    addressObjGrpipv4     = $url + '/api/sonicos/address-groups/ipv4'
    addressObjGrpipv4UUID = $url + '/api/sonicos/address-groups/ipv4/uuid'
    interfacesipv4        = $url + '/api/sonicos/interfaces/ipv4'
    aclRulesUUID          = $url + '/api/sonicos/access-rules/ipv4/uuid'
    aclRules              = $url + '/api/sonicos/access-rules/ipv4'
    flbSettings           = $url + '/api/sonicos/failover-lb/settings'
    flbGrpName            = $url + '/api/sonicos/failover-lb/groups/name/ Default LB Group'
    configSave            = $url + '/api/sonicos/config/pending'
    configCurrent         = $url + '/api/sonicos/config/current'
}

# Ignore self-signed certificate errors and allow TLS 1.0, 1.1, and 1.2
Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Prompt for the username/password and build request headers
$credential = Get-Credential
$2fa = Read-Host ('Enter 2FA Code')
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/json")
$headers.Add("Accept", "application/json")
$body = @{
    user     = "$($credential.Username)"
    password = "$($credential.GetNetworkCredential().Password)"
    tfa      = $2fa
    override = $true
} | ConvertTo-Json

try {
    # Add a bearer token to auth headers - needed for all remaining REST requests
    $getToken = Invoke-RestMethod -Uri $endpointURI.tfa -Method 'POST' -Headers $headers -Body $body
    $token = $getToken.status.info.message.Split(': ')[3]
    if ($null -eq $token) { # SonicOS is likely version 7 - use a different path
        $token = $getToken.status.info.bearer_token
        if ($null -eq $token) {
            throw "Oops! Unable to obtain authentication token. Is someone currently logged in?"
        }
    }
    $headers.Add("Authorization", "Bearer $token")
} catch {
    throw "Caught exception at line: $($_.InvocationInfo.ScriptLineNumber)`r`n$($_.Exception.Message)"
}

Write-Host "Successfully connected: $url" -ForegroundColor Green

# Get the current config
$currentConfig = Invoke-RestMethod -Uri $endpointURI.configCurrent -Method 'GET' -Headers $headers
Write-Host ""
Write-Host "================== SonicWALL Configuration =================="
Write-Host "Firewall Name    = $($currentConfig.administration.firewall_name)"
Write-Host "Model            = $($currentConfig.model)"
Write-Host "Serial Number    = $($currentConfig.serial_number)"
Write-Host "Firmware Version = $($currentConfig.firmware_version)"
Write-Host "ROM Version      = $($currentConfig.rom_version)"
Write-Host "System Time      = $($currentConfig.system_time)"
Write-Host "System Uptime    = $($currentConfig.system_uptime)"
Write-Host "============================================================="
Write-Host ""

# If SonicOS 7, update the API endpoints for compatibility
if ($currentConfig.firmware_version -match 'SonicOS 7') {
    $currentVersion = 7
    $endpointURI.flbSettings = $url + '/api/sonicos/failover-lb/base'
}

try {
    # Build body request to turn on https management, ping, and disable http redirect
    $intSettings = @{
        interfaces = @(@{ipv4 = @{name = ""; management = @{https = $true; ping = $true}; https_redirect = $false}})
    }

    # Search all active WAN interfaces and update settings here
    $getAddressObjects = (Invoke-RestMethod -Uri $endpointURI.addressObjipv4 -Method 'GET' -Headers $headers).address_objects.ipv4
    $interfacesToUpdate = foreach ($int in $getAddressObjects) {
        if ($int.host.ip -and $int.name -match 'X\d IP' -and $int.zone -eq 'WAN') {
            $intName = $int.name.TrimEnd('IP').Trim()
            [PSCustomObject]@{
                'Name' = $intName
                'Zone' = $int.zone
                'IP'   = $int.host.ip
            }
            $intSettings.interfaces.ipv4.name = $intName
            $intSettingsBody = $intSettings | ConvertTo-Json -Depth 4
            $result = Invoke-RestMethod -Uri $endpointURI.interfacesipv4 -Method 'PUT' -Headers $headers -Body $intSettingsBody
            if ($result.status.success -eq $true) {
                Write-Host "Interface updated successfully: $intName" -ForegroundColor Green
            }
        }
    }

    # Save the interface changes first and generate the UUID we'll need to update the access rules later
    $null = Invoke-RestMethod -Uri $endpointURI.configSave -Method 'POST' -Headers $headers

    # Another annoying transition from the SW team... *sigh*
    if ($currentVersion -eq 7) {
        $addressBody = @{address_objects = @(@{ipv4 = @{name = ''}})}
    } else {
        $addressBody = @{address_object = @{ipv4 = @{name = ''}}}
    }

    # Search for existing address objects and force an update to maintain required settings (in case of config drift)
    $managementIPs = @('184.178.29.113', '40.78.12.9', '104.42.236.208')
    foreach ($address in $getAddressObjects) {
        if ($managementIPs -contains $address.host.ip) {
            switch ($address.host.ip) {
                '184.178.29.113' {
                    $uuid = $address.uuid
                    foreach ($value in $addressBody.GetEnumerator()) {
                        $value.Value.ipv4.name = 'GL Mgmt - PHX Office'
                    }
                    Write-Host "Updated address object: $($address.host.ip)" -ForegroundColor Green
                    $null = Invoke-RestMethod -Uri ($endpointURI.addressObjipv4UUID + "/$uuid") -Method 'PUT' -Headers $headers -Body ($addressBody | ConvertTo-Json -Depth 3)
                }
                '40.78.12.9' {
                    $uuid = $address.uuid
                    foreach ($value in $addressBody.GetEnumerator()) {
                        $value.Value.ipv4.name = 'GL Mgmt - Azure 1'
                    }
                    Write-Host "Updated address object: $($address.host.ip)" -ForegroundColor Green
                    $null = Invoke-RestMethod -Uri ($endpointURI.addressObjipv4UUID + "/$uuid") -Method 'PUT' -Headers $headers -Body ($addressBody | ConvertTo-Json -Depth 3)
                }
                '104.42.236.208' {
                    $uuid = $address.uuid
                    foreach ($value in $addressBody.GetEnumerator()) {
                        $value.Value.ipv4.name = 'GL Mgmt - Azure 2'
                    }
                    Write-Host "Updated address object: $($address.host.ip)" -ForegroundColor Green
                    $null = Invoke-RestMethod -Uri ($endpointURI.addressObjipv4UUID + "/$uuid") -Method 'PUT' -Headers $headers -Body ($addressBody | ConvertTo-Json -Depth 3)
                }
            }
        }
    }

    if ($currentVersion -eq 7) {
        $addressBody = @{address_objects = @(@{ipv4 = @{name = ''; host = @{ip = ''}}})}
    } else {
        $addressBody = @{address_object = @{ipv4 = @{name = ''; host = @{ip = ''}}}}
    }

    # If address objects are not found, create them below
    $missingAddress = $managementIPs | Where-Object {$getAddressObjects.host.ip -notcontains $_}
    foreach ($address in $missingAddress) {
        switch ($address) {
            '184.178.29.113' {
                foreach ($value in $addressBody.GetEnumerator()) {
                    $value.Value.ipv4.name = 'GL Mgmt - PHX Office'
                    $value.Value.ipv4.zone = 'WAN'
                    $value.Value.ipv4.host.ip = '184.178.29.113'
                }
                $null = Invoke-RestMethod -Uri $endpointURI.addressObjipv4 -Method 'POST' -Headers $headers -Body ($addressBody | ConvertTo-Json -Depth 4)
                Write-Host "Created address object: $address" -ForegroundColor Green
            }
            '40.78.12.9' {
                foreach ($value in $addressBody.GetEnumerator()) {
                    $value.Value.ipv4.name = 'GL Mgmt - Azure 1'
                    $value.Value.ipv4.zone = 'WAN'
                    $value.Value.ipv4.host.ip = '40.78.12.9'
                }
                $null = Invoke-RestMethod -Uri $endpointURI.addressObjipv4 -Method 'POST' -Headers $headers -Body ($addressBody | ConvertTo-Json -Depth 4)
                Write-Host "Created address object: $address" -ForegroundColor Green
            }
            '104.42.236.208' {
                foreach ($value in $addressBody.GetEnumerator()) {
                    $value.Value.ipv4.name = 'GL Mgmt - Azure 2'
                    $value.Value.ipv4.zone = 'WAN'
                    $value.Value.ipv4.host.ip = '104.42.236.208'
                }
                $null = Invoke-RestMethod -Uri $endpointURI.addressObjipv4 -Method 'POST' -Headers $headers -Body ($addressBody | ConvertTo-Json -Depth 4)
                Write-Host "Created address object: $address" -ForegroundColor Green
            }
        }
    }

    # Save the config here - this is required if existing address object names were mismatched
    # This allows the group object (GL Mgmt) to find the correct names and successfully add all of them later
    $null = Invoke-RestMethod -Uri $endpointURI.configSave -Method 'POST' -Headers $headers

    # Check if the group object exists - if not, create it and add all address objects
    # Also, set the correct body parameters
    if ($currentVersion -eq 7) {
        $groupBody = @{address_groups = @(@{ipv4 = @{name = ''; address_object = @{ipv4 = @(@{name = ''}, @{name = ''}, @{name = ''})}}})}
    } else {
        $groupBody = @{address_group = @{ipv4 = @{name = ''; address_object = @{ipv4 = @(@{name = ''}, @{name = ''}, @{name = ''})}}}}
    }

    foreach ($value in $groupBody.GetEnumerator()) {
        $value.Value.ipv4.name = 'GL Mgmt'
        $value.Value.ipv4.address_object.ipv4[0].name = 'GL Mgmt - PHX Office'
        $value.Value.ipv4.address_object.ipv4[1].name = 'GL Mgmt - Azure 1'
        $value.Value.ipv4.address_object.ipv4[2].name = 'GL Mgmt - Azure 2'
    }

    $getAddressGroups = (Invoke-RestMethod -Uri $endpointURI.addressObjGrpipv4 -Method 'GET' -Headers $headers).address_groups
    $glMgmtGroup = $getAddressGroups.ipv4 | Where-Object {$_.name -like "*GL*"}
    if (-not ($glMgmtGroup)) {
        $null = Invoke-RestMethod -Uri $endpointURI.addressObjGrpipv4 -Method 'POST' -Headers $headers -Body ($groupBody | ConvertTo-Json -Depth 6)
        Write-Host "Created address group: GL Mgmt" -ForegroundColor Green
    } else {
        $uuid = $glMgmtGroup.uuid
        $null = Invoke-RestMethod -Uri ($endpointURI.addressObjGrpipv4UUID + "/$uuid") -Method 'PUT' -Headers $headers -Body ($groupBody | ConvertTo-Json -Depth 6)
        Write-Host "Updated address group: GL Mgmt" -ForegroundColor Green
    }

    # Save again here since we made changes to the group
    $null = Invoke-RestMethod -Uri $endpointURI.configSave -Method 'POST' -Headers $headers

    # Update all HTTPS management access rules (WAN to WAN) to include the 'GL Mgmt' group
    if ($currentVersion -eq 7) {
        $aclSettings = @{access_rules = @(@{ipv4 = @{source = @{address = @{group = 'GL Mgmt'}}}})} | ConvertTo-Json -Depth 5
    } else {
        $aclSettings = @{access_rule = @{ipv4 = @{source = @{address = @{group = 'GL Mgmt'}}}}} | ConvertTo-Json -Depth 4
    }

    $getAclResponse = Invoke-RestMethod -Uri $endpointURI.aclRules -Method 'GET' -Headers $headers
    foreach ($item in $getAclResponse.access_rules.ipv4) {
        if ($item.service.name -eq 'HTTPS Management') {
            if ($item.from -eq 'WAN' -and $item.to -eq 'WAN' -and $item.source.address.any -eq $true) {
                $uuid = $item.uuid
                $aclRulesResponse = Invoke-RestMethod -Uri ($endpointURI.aclRulesUUID + "/$uuid") -Method 'PUT' -Headers $headers -Body $aclSettings
                if ($aclRulesResponse.status.success -eq $true) {
                    Write-Host "Access rule {$uuid} updated" -ForegroundColor Green
                }
            } elseif ($item.from -eq 'WAN' -and $item.to -eq 'WAN' -and $item.source.address.group -eq 'GL Mgmt') {
                $uuid = $item.uuid
                Write-Host "Access rule {$uuid} already includes 'GL Mgmt'" -ForegroundColor Green
            }
        }
    }

    # Provide all URL's for IT Glue
    $interfaces = (Invoke-RestMethod -Uri $endpointURI.interfacesipv4 -Method 'GET' -Headers $headers).interfaces.ipv4
    Write-Host ""
    Write-Host "============= Save the following URLs in IT Glue ============"
    foreach ($item in $interfaces) {
        foreach ($int in $interfacesToUpdate) {
            if ($item.name -eq $int.name -and $item.ip_assignment.mode.static.ip) {
                Write-Host "$($int.name) (Static) = https://$($int.IP):8443" -ForegroundColor Green
            } elseif ($item.name -eq $int.name) {
                Write-Host "$($int.name) (Dynamic) = https://$($int.IP):8443" -ForegroundColor Green
            }
        }
    }
    # Save final pending changes
    Write-Host ""
    Write-Host "Saving changes..."
    $null = Invoke-RestMethod -Uri $endpointURI.configSave -Method 'POST' -Headers $headers
    # Delete the current session
    Write-Host "Disconnecting session..."
    $null = Invoke-RestMethod -Uri $endpointURI.auth -Method 'DELETE' -Headers $headers

} catch {
    Write-Host "Caught exception at line: $($_.InvocationInfo.ScriptLineNumber)`r`n$($_.Exception.Message)" -ForegroundColor Red
    $null = Invoke-RestMethod -Uri $endpointURI.auth -Method 'DELETE' -Headers $headers
}

# Clear sensitive values
Clear-Variable -Name @("headers", "body", "credential", "getToken", "token")
