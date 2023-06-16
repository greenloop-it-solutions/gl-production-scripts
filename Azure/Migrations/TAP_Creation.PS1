# Prompt the user to perform specific actions before running the script
Write-Host "Before running this script, please make sure to perform the following steps:"
Write-Host "1. Ensure that you have installed the Microsoft.Graph.Authentication module."
Write-Host "2. Close any existing PowerShell sessions to avoid conflicts."
Write-Host ""
Write-Host "You will be promptd several times for GLobal Administrator Credentials.  This is normal."

# Import required modules
Import-Module -Name Microsoft.Graph.Authentication

# Authenticate with Azure AD
Connect-MgGraph -Scopes "UserAuthenticationMethod.ReadWrite.All"

# Function to prompt for file selection using GUI
function Get-FileUsingGUI {
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    $openFileDialog.Multiselect = $false
    $openFileDialog.Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
    $openFileDialog.ShowDialog() | Out-Null

    return $openFileDialog.FileName
}

# Function to prompt for folder selection using GUI
function Get-FolderUsingGUI {
    $folderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowserDialog.ShowDialog() | Out-Null

    return $folderBrowserDialog.SelectedPath
}

# Get the tenant name
$tenant = Get-MgOrganization
$tenantName = $tenant.DisplayName

# Prompt for email addresses
$emailAddresses = Read-Host "Enter email addresses separated by commas or choose 'CSV' to import from a CSV file"

if ($emailAddresses -eq "CSV") {
    # Import email addresses from CSV
    $csvPath = Get-FileUsingGUI
    $emailAddresses = Import-Csv -Path $csvPath | Select-Object -ExpandProperty EmailAddress
} else {
    $emailAddresses = $emailAddresses -split ","
}

# Prompt for access pass lifetime in minutes
$lifetime = Read-Host "Enter access pass lifetime in minutes"

# Generate temporary access passes
$accessPasses = @()

foreach ($emailAddress in $emailAddresses) {
    $accessPassPayload = @{
        "isUsableOnce" = $false
        "lifetimeInMinutes" = [int]$lifetime
        "emailAddress" = $emailAddress
    }

    $accessPass = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $emailAddress -BodyParameter $accessPassPayload

    $accessPasses += [PSCustomObject]@{
        EmailAddress = $emailAddress
        AccessPass = $accessPass.temporaryAccessPass
        ExpirationTime = (Get-Date).AddMinutes($accessPass.lifetimeInMinutes)
    }
}

# Export access passes to CSV
$exportPath = Get-FolderUsingGUI

if ([string]::IsNullOrEmpty($exportPath)) {
    Write-Host "Export path is empty. Please provide a valid path."
    Exit
}

$csvFilePath = Join-Path -Path $exportPath -ChildPath "AccessPasses_$tenantName.csv"
$accessPasses | Export-Csv -Path $csvFilePath -NoTypeInformation

Write-Host "Temporary access passes generated and exported to CSV successfully."
Write-Host "CSV file location: $csvFilePath"
Write-Host ""

# Prompt to exit
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
