#This script iterates through all rules created by https://github.com/greenloop-it-solutions/Microsoft-365/blob/master/Incident%20Response/Install-AzureADProtectionAlerts.ps1 and disables email alerting.
#No longer need email alerts for these as other tools handle them.

Import-Module ExchangeOnlineManagement
Connect-IPPSSession

$ruleNames = @(
    "New member added to an Azure AD Role",
    "New application added to the directory",
    "New client credentials added to an application",
    "Add app role assignment to service principal",
    "Add delegated permission grant",
    "Consent to application",
    "Set federation settings on domain",
    "Partner relationship added to the organization",
    "Conditional Access policy added",
    "Conditional Access policy updated",
    "Conditional Access policy deleted"
)

foreach ($ruleName in $ruleNames) {
    try {
        Get-ProtectionAlert -Identity $ruleName | Set-ProtectionAlert -NotificationEnabled $false
        Get-ProtectionAlert -Identity $ruleName | ft Name,NotificationEnabled,NotifyUser
    } catch { }
}
