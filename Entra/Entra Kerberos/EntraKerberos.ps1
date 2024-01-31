# Ensure TLS 1.2 for PowerShell gallery access
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Check if the script is running as a Domain Administrator
$domainAdminGroupName = "Domain Admins"
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)

# Retrieve the Domain Admins group SID dynamically
$domainAdminGroup = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity(
    [System.DirectoryServices.AccountManagement.PrincipalContext]::new([System.DirectoryServices.AccountManagement.ContextType]::Domain),
    $domainAdminGroupName
)

if ($domainAdminGroup -eq $null -or -not $principal.IsInRole($domainAdminGroup.Sid)) {
    Write-Host "This script must be run as a Domain Administrator. Please run the script with the appropriate permissions."
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
