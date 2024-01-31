# Ensure TLS 1.2 for PowerShell gallery access
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Get the current username without the domain prefix
$currentUsernameWithDomain = whoami
$currentUsername = $currentUsernameWithDomain.Split('\')[1]

# Check if the current user is a Domain Administrator
$domainAdminCheck = (Get-ADUser $currentUsername -Properties memberof).memberof -like "*CN=Domain Admins*"
if (-not $domainAdminCheck) {
    Write-Host "$currentUsername is not a member of the Domain Admins group. Please run the script with appropriate permissions."
    Read-Host "Press any key to exit..."
    exit
}

# Check if the session is elevated
if (-not ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script requires elevated permissions. Please restart the script in an elevated PowerShell session."
    exit
}

# Check if the AzureADHybridAuthenticationManagement module is installed
$moduleName = "AzureADHybridAuthenticationManagement"
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    $userConsent = Read-Host "Module '$moduleName' is not installed. Would you like to install it now? (Y/N)"
    if ($userConsent -eq 'Y') {
        Install-Module -Name $moduleName -Force -AllowClobber
        Write-Host "Module '$moduleName' installed."
    } else {
        Write-Host "Module '$moduleName' is required to run this script. Exiting."
        exit
    }
} else {
    Write-Host "Module '$moduleName' is already installed. Skipping installation."
}

# Specify the Active Directory Domain to use
$Domain = $env:USERDNSDOMAIN

# Provide the UPN of an Azure Active Directory Global Administrator
$UserPrincipalName = Read-Host "Enter the username of a Global Administrator within the M365 tenant"

# Create the Entra Kerberos Server object in Active Directory and then publish it to Entra
Write-Host "`nA Modern Auth pop-up will request the remainder of the Global Administrator credentials."
Set-AzureADKerberosServer -Domain $Domain -UserPrincipalName $UserPrincipalName
