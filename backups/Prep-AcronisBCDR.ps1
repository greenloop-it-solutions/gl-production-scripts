#!ps
# This script sets up accounts and security for a Windows Device to function as an Acronis BCDR.
# creates local accounts and network share. Gives service account necessary security profile permissions.
$BackupAccountName = "backupUser"
$BackupSvcAccountName = "svc_aMMS"
$BackupDriveLetter = "E:"
$BackupDataPath = "$($BackupDriveLetter)\Backup_Data"
$BackupDRPath = "$($BackupDriveLetter)\DR_Test"

function Get-RandomPassword {
    param (
        [Parameter(Mandatory)]
        [int] $length,
        [int] $amountOfNonAlphanumeric = 1
    )
    Add-Type -AssemblyName 'System.Web'
    return [System.Web.Security.Membership]::GeneratePassword($length, $amountOfNonAlphanumeric)
}

#create Backup Data Directory
$BackupData = Test-Path $BackupDataPath
if (!$BackupData) {
    New-Item -ItemType "directory" -Path $BackupDataPath
}

#create DR validation Directory
$DRPath = Test-Path $BackupDRPath
if (!$DRPath) {
    New-Item -ItemType "directory" -Path $BackupDRPath
}

#Create a new backup service account with a Random Password
$BackupSvcAcctPassword = Get-RandomPassword 10
$BackupSvcAcctPasswordSecure = $BackupSvcAcctPassword | ConvertTo-SecureString -AsPlainText -Force
$SvcAccountSid = (New-LocalUser -Name $BackupSvcAccountName -Password $BackupSvcAcctPasswordSecure -PasswordNeverExpires -UserMayNotChangePassword -Description "Service account for the Acronis MMS service").SID.Value
Write-Host "MMS Service Account credentials are below. This account should ONLY be used as the service account for MMS. This can be specified as the service logon account manually, or via the Immy deployment. See https://kb.acronis.com/content/56202."
Write-Host "Username: $BackupSvcAccountName"
Write-Host "Password: $BackupSvcAcctPassword"
Add-LocalGroupMember -Group Administrators -Member $BackupSvcAccountName
Add-LocalGroupMember -Group "Backup Operators" -Member $BackupSvcAccountName

#Create a new user for Network backups with a Random Password
$BackupAcctPassword = Get-RandomPassword 10
$BackupAcctPasswordSecure = $BackupAcctPassword | ConvertTo-SecureString -AsPlainText -Force
New-LocalUser -Name $BackupAccountName -Password $BackupAcctPasswordSecure -PasswordNeverExpires -UserMayNotChangePassword -Description "Account has Full Access to the Backup Share"
Write-Host "Backup Account Credentials are below. This account Should ONLY be used for network access to the backup share. Please store these securely!"
Write-Host "Username: $BackupAccountName"
Write-Host "Password: $BackupAcctPassword"

#give our backup user full access to the backup folder, subfolders and files
$ACL = Get-Acl $BackupDataPath
$AccessRule = $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($BackupAccountName,'FullControl','ContainerInherit,ObjectInherit','NoPropagateInherit','Allow')
$ACL.AddAccessRule($AccessRule)
$ACL | Set-Acl -Path $BackupDataPath

#create an SMB share and give our backup user Full Access permissions.
New-SmbShare -Path $BackupDataPath -Name 'BackupData$' -ReadAccess "Administrators" -FullAccess $BackupAccountName

#Give our MMS service account required local security context permissions
$ExportFile = "$($env:SystemRoot)\Temp\CurrentConfig.inf"
$SecDb = "$($env:SystemRoot)\Temp\secedt.sdb"

function Add-SidToSecDb {
    param (
        [Parameter(Mandatory)]
        [string] $SID,
        [string] $SecEntry
    )

    #Export the current configuration
    secedit /export /cfg $ExportFile

    #Find the current list of SIDs having already this right
    $CurrentRight = Get-Content -Path $ExportFile | Where-Object -FilterScript {$PSItem -match $SecEntry}

$FileContent = @'
    [Unicode]
    Unicode=yes
    [System Access]
    [Event Audit]
    [Registry Values]
    [Version]
    signature="$CHICAGO$"
    Revision=1
    [Profile Description]
    [Privilege Rights]
    {0}*{1}
'@ -f $(
        if($CurrentRight){"$CurrentRight,"}
        else{"$SecEntry = "}
    ), $SID
    
    Set-Content -Path $ImportFile -Value $FileContent

    #Import the new configuration into the SecDb
    $ImportFile = "$($env:SystemRoot)\Temp\NewConfig.inf"
    secedit /import /db $SecDb /cfg $ImportFile
    #Remove-Item $ImportFile
}

Add-SidToSecDb -SID $SvcAccountSid -SecEntry "SeServiceLogonRight"
Add-SidToSecDb -SID $SvcAccountSid -SecEntry "SeIncreaseQuotaPrivilege"
Add-SidToSecDb -SID $SvcAccountSid -SecEntry "SeAssignPrimaryTokenPrivilege"
Add-SidToSecDb -SID $SvcAccountSid -SecEntry "SeSystemEnvironmentPrivilege"

# Import the new configuration into the system configuration
secedit /configure /db $SecDb
