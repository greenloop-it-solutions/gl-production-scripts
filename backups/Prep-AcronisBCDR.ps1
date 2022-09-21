#!ps
# This script sets up accounts and security for a Windows Device to function as an Acronis BCDR.
# creates local accounts and network share. Gives service account necessary security profile permissions.
$BackupAccountName = "backupUser"
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
New-SmbShare -Path $BackupDataPath -Name 'BackupData$' -FullAccess $BackupAccountName
