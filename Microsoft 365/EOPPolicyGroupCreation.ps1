<##################################################################################################
#
.SYNOPSIS
This script creates Groups for Exchange Online Protection Policy enforcement. It creates a Dynamic Group with all mail-enabled, non-guest users for the Standard Policy and an empty 365 Group for the Strict Policy (users to be added to this manually as needed).

.NOTES
    FileName:   EOPPolicyGroupCreation.ps1
    Author:     Stephen Moody, GreenLoop IT Solutions
    Created:    2022_03_02
	Revised:    2022_06_01 - Randall (Adjusted some verbiage and line suggestions at the end.)
                2023_07_03 - Terry W. (refactored majority of code - introduced Microsoft Graph, do-while loops, and minor error handling)
    Version:    1.12
#>
###################################################################################################

# Check if Microsoft.Graph.Groups module is installed
$module = Get-Module -ListAvailable -Name Microsoft.Graph.Groups
if ($null -eq $module) {
    # Install the module if it's not installed
    Write-Host "Microsoft.Graph.Groups module not found. Installing module..."
    Install-Module -Name Microsoft.Graph.Groups -Scope CurrentUser -Force
    # Import the module
    Import-Module -Name Microsoft.Graph.Groups -Force
} else {
    Write-Host "Microsoft.Graph.Groups module found. Importing module..."
    # Import the module
    Import-Module -Name Microsoft.Graph.Groups -Force
}

# Connect to Microsoft Graph
$scopes = "Group.ReadWrite.All"
Connect-MgGraph -Scopes $scopes

# Check if ExchangeOnlineManagement module is installed
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Host "ExchangeOnlineManagement module not found. Attempting to install..."
    Install-Module ExchangeOnlineManagement -Repository PSGallery -AllowClobber -Force
}

# Import the ExchangeOnlineManagement module
Import-Module ExchangeOnlineManagement -ErrorAction SilentlyContinue

# Check if the module is loaded, if not then exit
if (-not (Get-Module -Name ExchangeOnlineManagement)) {
    Write-Error "Failed to import ExchangeOnlineManagement module"
    exit
}

# Connect to Exchange
Connect-ExchangeOnline

$standardGroupParams = @{
    Description     = "All users get the EOP Standard Policy applied by default. No need to exclude them for *strict* as strict overrides *standard*."
    DisplayName     = "EOP Standard Protection Policy Users"
    MailEnabled     = $true
    SecurityEnabled = $true
    MailNickname    = "EOPStdPolicyUsers"
    GroupTypes      = "Unified"
}

# Creates the EOP Standard Policy Group as a 365 (Unified) Group. It will convert it to Dynamic and apply the rule at the next step.
$standardGroup = New-MgGroup @standardGroupParams

$strictGroupParams = @{
    Description     = "Add specific users that need *strict* protection here. Should not need to exclude them from the *standard* policy as strict policy overrides."
    DisplayName     = "EOP Strict Protection Policy Users"
    MailEnabled     = $true
    SecurityEnabled = $true
    MailNickname    = "EOPStrictPolicyUsers"
    GroupTypes      = "Unified"
}

# Creates the EOP Strict Policy Group as a 365 (Unified) Group. This is going to stay a static group.
$strictGroup = New-MgGroup @strictGroupParams

# Shouldn't need to change this
$dynamicGroupTypeString = "DynamicMembership"

# This is the dynamic membership rule. Only change this if you know what you're doing!
$dynamicMembershipRule = "(user.objectId -ne null) and (user.mail -ne null) and (user.userType -ne `"guest`") and (user.mailNickname -notContains `"#EXT#`")" # Last term is to exclude directory members who are external.

# Gets existing group types and adds DynamicMembership to the list
[Collections.ArrayList]$groupTypes = (Get-MgGroup -GroupId $standardGroup.Id).GroupTypes
$groupTypes.Add($dynamicGroupTypeString)

# Converts Group to Dynamic, adds membership rule, and sets state to Paused. (important so that it doesn't send an email immediately.
Update-MgGroup -GroupId $standardGroup.Id -GroupTypes $groupTypes.ToArray() -MembershipRule $dynamicMembershipRule -MembershipRuleProcessingState "paused"

<#
    Set both Groups (Standard & Strict) - hidden from GAL, Private, and turn off the welcome email.
    The default timeout value is currently set to 5 minutes to allow delayed processing.
#>

# Standard group check
$standardGroupCheck = $null
$timeout = (Get-Date).AddMinutes(5)
do {
    Write-Host "Waiting for the Standard Group to be created. Please wait... If the group is not created within 5 minutes, the operation will time out."
    Start-Sleep -Seconds 5
    $standardGroupCheck = Get-UnifiedGroup -Identity $standardGroup.Id -ErrorAction SilentlyContinue
    if ($null -ne $standardGroupCheck) {
        Set-UnifiedGroup -Identity $standardGroup.Id -UnifiedGroupWelcomeMessageEnabled:$false -AccessType Private -HiddenFromExchangeClientsEnabled:$true -HiddenFromAddressListsEnabled:$true
        break
    } else {
        if ((Get-Date) -gt $timeout) {
            Write-Warning "Timeout while waiting for the Standard Group to be created."
            break
        }
    }
} while ($true)

# Strict group check
$strictGroupCheck = $null
$timeout = (Get-Date).AddMinutes(5)
do {
    Write-Host "Waiting for the Strict Group to be created. Please wait... If the group is not created within 5 minutes, the operation will time out."
    Start-Sleep -Seconds 5
    $strictGroupCheck = Get-UnifiedGroup -Identity $strictGroup.Id -ErrorAction SilentlyContinue
    if ($null -ne $strictGroupCheck) {
        Set-UnifiedGroup -Identity $strictGroup.Id -UnifiedGroupWelcomeMessageEnabled:$false -AccessType Private -HiddenFromExchangeClientsEnabled:$true -HiddenFromAddressListsEnabled:$true
        break
    } else {
        if ((Get-Date) -gt $timeout) {
            Write-Warning "Timeout while waiting for the Strict Group to be created."
            break
        }
    }
} while ($true)

# Welcome Message Enabled processing
$timeout = (Get-Date).AddMinutes(5)
do {
    Start-Sleep -Seconds 5
    $WelcomeMessageEnabled = (Get-UnifiedGroup -Identity $standardGroup.Id -IncludeAllProperties).WelcomeMessageEnabled
    if (-not $WelcomeMessageEnabled) {
        # Turn on dynamic processing. Within a minute or two the group membership should be updated.
        Update-MgGroup -GroupId $standardGroup.Id -MembershipRuleProcessingState "On"
        break
    } else {
        if ((Get-Date) -gt $timeout) {
            $warningMessage = @(
                "Timeout while waiting for Welcome Messages to be properly configured.",
                "Please check this and correct it before proceeding!",
                "Sometimes there's a processing delay, so you may want to re-run lines 91 through the end, potentially more than once."
            )
            $warningMessage = $warningMessage -join "`n"
            Write-Warning $warningMessage
            break
        }
    }
} while ($true)
