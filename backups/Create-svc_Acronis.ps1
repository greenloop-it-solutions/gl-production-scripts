#!ps
function Get-RandomPassword {
    param (
        [Parameter(Mandatory)]
        [int] $length,
        [int] $amountOfNonAlphanumeric = 1
    )
    Add-Type -AssemblyName 'System.Web'
    return [System.Web.Security.Membership]::GeneratePassword($length, $amountOfNonAlphanumeric)
}
$pwPlain = Get-RandomPassword 10

$pw = $pwPlain | ConvertTo-SecureString -AsPlainText -Force
New-ADUser -Name svc_Acronis -AccountPassword $pw -Passwordneverexpires $true -Enabled $true
Add-ADGroupMember -Identity "Domain Admins" -Members svc_Acronis

Write-Host "Password: $pwPlain"

Write-Host "Once agent is installed, update the Acronis Management Service to run as Local System and delete this account!"
