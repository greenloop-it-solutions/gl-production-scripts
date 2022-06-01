<##################################################################################################
#
.SYNOPSIS
This script creates Groups for Exchange Online Protection Policy enforcement. It creates a Dynamic Group with all mail-enabled, non-guest users for the Standard Policy and an empty 365 Group for the Strict Policy (users to be added to this manually as needed).

.NOTES
    FileName:    EOPPolicyGroupCreation.ps1
    Author:      Stephen Moody, GreenLoop IT Solutions
    Created:     2022_03_02
	Revised:     2022_06_01 - Randall (Adjusted some verbiage and line suggestions at the end.)
    Version:     1.11
    
#>
###################################################################################################

# need to be connected to AzureAD PowerShell for the first part.
Connect-AzureAD
# currently, have to use the "preview" module for the commands on line 22 to work.
Install-module AzureADPreview -Repository PSGallery -AllowClobber -Force

#if you have both modules, you should ensure that the correct module is the one you are using:

# Unload the AzureAD module (or continue if it's already unloaded)
Remove-Module AzureAD -ErrorAction SilentlyContinue
# Load the AzureADPreview module
Import-Module AzureADPreview

# Creates the EOP Standard Policy Group as a 365 (Unified) Group. It will convert it to Dynamic and apply the rule at the next step.
$standardGroup = New-AzureADMSGroup -Description "All users get the EOP Standard Policy applied by default. No need to exclude them for *strict* as strict overrides *standard*." -DisplayName "EOP Standard Protection Policy Users" -MailEnabled $true -SecurityEnabled $true -MailNickname "EOPStdPolicyUsers" -GroupTypes "Unified"
# Creates the EOP Strict Policy Group as a 365 (Unified) Group. This is going to stay a static group.
$strictGroup = New-AzureADMSGroup -Description "Add specific users that need *strict* protection here. Should not need to exclude them from the *standard* policy as strict policy overrides." -DisplayName "EOP Strict Protection Policy Users" -MailEnabled $true -SecurityEnabled $true -MailNickname "EOPStrictPolicyUsers" -GroupTypes "Unified"

#shouldn't need to change this
$dynamicGroupTypeString = "DynamicMembership"
# this is the dynamic membership rule. Only change this if you know what you're doing!
$dynamicMembershipRule = "(user.objectId -ne null) and (user.mail -ne null) and (user.userType -ne `"guest`") and (user.mailNickname -notContains `"#EXT#`")" #last term is to exclude directory members who are external.

# gets existing group types
[System.Collections.ArrayList]$groupTypes = (Get-AzureAdMsGroup -Id $($standardGroup.id)).GroupTypes 
#adds DynamicMembership to the list
$groupTypes.Add($dynamicGroupTypeString) 

# converts Group to Dynamic, adds membership rule, and sets state to Paused. (important so that it doesn't send an email immediately.
Set-AzureAdMsGroup -Id $($standardGroup.id) -GroupTypes $groupTypes.ToArray() -MembershipRule $dynamicMembershipRule -MembershipRuleProcessingState "paused"

# we'll need to connect to exchange online to turn off the welcome email, and hide the group.
Connect-ExchangeOnline

# set both Groups - hidden from GAL, Private, and turn off the welcome email.
Set-UnifiedGroup -Identity $($standardGroup.id) -UnifiedGroupWelcomeMessageEnabled:$false -AccessType Private -HiddenFromExchangeClientsEnabled:$true -HiddenFromAddressListsEnabled:$true
Set-UnifiedGroup -Identity $($strictGroup.id) -UnifiedGroupWelcomeMessageEnabled:$false  -AccessType Private -HiddenFromExchangeClientsEnabled:$true -HiddenFromAddressListsEnabled:$true

$WelcomeMessageEnabled = [boolean](Get-UnifiedGroup -Identity $($standardGroup.id) -IncludeAllProperties | Select WelcomeMessageEnabled).WelcomeMessageEnabled

#seems that sometimes this doesn't apply the first time, or right away. Adding this for now. May change to a do-while when I have an opportunity. -SM
if (!$WelcomeMessageEnabled) {
    # turn on the dynamic processing. Within a minute or two the Group Membership should be updated.
    Set-AzureAdMsGroup -Id $($standardGroup.id) -MembershipRuleProcessingState "On"
} else {
    Write-Host "Unable to set rule processing to 'On' because Welcome Messages are still not properly configured. Please check this and correct it before proceeding! Sometimes there's a processing delay, so you may want to re-run lines 50 through the end, potentially more than once."   
}
