#Script Creates a Retention Policy for Exchange/OneDrive/SharePoint etc with 7 year/Keep retention, and another for Teams Channels and Chats. Teams private channel messages are currently only supported via the GUI (https://compliance.microsoft.com/informationgovernance?viewid=retention) not PowerShell.
#fill in the admin UPN and run in PowerShell. EXOv2 should already be loaded.

Import-Module ExchangeOnlineManagement
Connect-IPPSSession -UserPrincipalName <Admin UPN goes here>

New-RetentionCompliancePolicy -Name "Company Policy" -ExchangeLocation All -SharePointLocation All -ModernGroupLocation All -OneDriveLocation All -PublicFolderLocation All -Enabled $true
New-RetentionComplianceRule -Name "Company Policy Rule" -Policy "Company Policy" -RetentionDuration 2555 -ExpirationDateOption CreationAgeInDays -RetentionComplianceAction Keep   

New-RetentionCompliancePolicy -Name "Teams Policy"-TeamsChannelLocation All -TeamsChatLocation All -Enabled $true
New-RetentionComplianceRule -Name "Teams Policy Rule" -Policy "Teams Policy" -RetentionDuration 2555 -RetentionComplianceAction Keep   
