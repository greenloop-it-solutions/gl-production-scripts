<##################################################################################################
#
.SYNOPSIS
This script creates Groups for Exchange Online Protection Policy enforcement. It creates a Dynamic Group with all mail-enabled, non-guest users for the Standard Policy and an empty 365 Group for the Strict Policy (users to be added to this manually as needed).

.NOTES
    FileName:    EOPPolicyGroupCreation.ps1
    Author:      Stephen Moody, GreenLoop IT Solutions
    Created:     2022_03_02
	Revised:     --
    Version:     1.0
    
#>
###################################################################################################

# need to be connected to AzureAD PowerShell for the first part.
Connect-AzureAD
# currently, have to use the "preview" module for the commands on line 22 to work.
Import-Module -Name AzureADPreview

# Creates the EOP Standard Policy Group as a 365 (Unified) Group. It will convert it to Dynamic and apply the rule at the next step.
$standardGroup = New-AzureADMSGroup -Description “All users get the EOP Standard Policy applied by default. No need to exclude them for *strict* as strict overrides *standard*.” -DisplayName “EOP Standard Protection Policy Users” -MailEnabled $true -SecurityEnabled $true -MailNickname “EOPStdPolicyUsers” -GroupTypes “Unified”
# Creates the EOP Strict Policy Group as a 365 (Unified) Group. This is going to stay a static group.
$strictGroup = New-AzureADMSGroup -Description “Add specific users that need *strict* protection here. Should not need to exclude them from the *standard* policy as strict policy overrides.” -DisplayName “EOP Strict Protection Policy Users” -MailEnabled $true -SecurityEnabled $true -MailNickname “EOPStrictPolicyUsers” -GroupTypes “Unified”

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

# turn on the dynamic processing. Within a minute or two the Group Membership should be updated.
Set-AzureAdMsGroup -Id $($standardGroup.id) -MembershipRuleProcessingState "on"
