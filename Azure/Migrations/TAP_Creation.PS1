# Clear the screen
Clear-Host

# Prompt the user to review key details before running the script
Write-Host "This script generates TAPs for Azure Active Directory.  It can either display them, or export them to CSV."
Write-Host ""
Write-Host "The Microsoft.Graph.Authentication module is required.  The script will prompt you if you do not have it installed."
Write-Host ""
Write-Host "You will need Global Administrator credentials for the tenant you wish to retrieve TAPs from."
Write-Host ""
Write-Host "Global Administrator credentials may be prompted several times.  This is intentional."
Start-Sleep 15

# Clear the screen
Clear-Host

# Required module
$requiredModule = 'Microsoft.Graph.Authentication'

# Check for required module
if (-not (Get-Module -ListAvailable -Name $requiredModule)) {
    Write-Host "$requiredModule module is not currently installed."
    $userConfirmation = Read-Host "Would you like to install the $requiredModule module now? (Y/N)"
    if ($userConfirmation -eq "Y") {
        try {
            Install-Module -Name $requiredModule -Force -AllowClobber
            Write-Host "$requiredModule module installed successfully."
        }
        catch {
            Write-Host "Failed to install $requiredModule module. Please check your permissions and try again." -ForegroundColor Red
            Exit
        }
    }
    else {
        Write-Host "This script requires $requiredModule module. Exiting script." -ForegroundColor Red
        Exit
    }
}

# Import required module
Import-Module -Name $requiredModule

# Authenticate with Azure AD
try {
    Connect-MgGraph -Scopes "UserAuthenticationMethod.ReadWrite.All"
}
catch {
    Write-Host "Failed to authenticate with Azure AD. Please check your credentials and try again." -ForegroundColor Red
    Exit
}

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

#Clear the Screen
Clear-Host

#Begin user input
Write-Host "Welcome to GreenLoop Automated TAP creation." -ForegroundColor Green
Write-Host ""

# Prompt for input method
$inputMethod = Read-Host "Enter '1' to input email addresses manually, '2' to import from a CSV file"
$emailAddresses = @()

if ($inputMethod -eq "2") {
    # Import email addresses from CSV
    $csvPath = Get-FileUsingGUI
    $emailAddresses = Import-Csv -Path $csvPath | Select-Object -ExpandProperty EmailAddress
} elseif ($inputMethod -eq "1") {
    # Prompt for email addresses
    $emailAddresses = Read-Host "Enter email addresses separated by commas"
    $emailAddresses = $emailAddresses -split ","
} else {
    Write-Host "Invalid choice. Please enter '1' or '2'." -ForegroundColor Red
    Exit
}

# Prompt for access pass lifetime in minutes
$lifetime = Read-Host "Enter access pass lifetime in minutes"

# Generate temporary access passes
$accessPasses = @()

foreach ($emailAddress in $emailAddresses) {
    try {
        $accessPassPayload = @{
            "isUsableOnce" = $false
            "lifetimeInMinutes" = [int]$lifetime
            "emailAddress" = $emailAddress
        }

        $accessPass = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $emailAddress -BodyParameter $accessPassPayload

        if ($null -eq $accessPass) {
            Write-Warning "Failed to generate an access pass for $emailAddress. Skipping..."
            continue
        }

        $accessPasses += [PSCustomObject]@{
            EmailAddress = $emailAddress
            AccessPass = $accessPass.temporaryAccessPass
            ExpirationTime = (Get-Date).AddMinutes($accessPass.lifetimeInMinutes)
        }
    }
    catch {
        Write-Warning "An error occurred while generating the access pass for $emailAddress. Skipping..."
    }
}

# Ask the user whether to display the passes or export them to CSV
$userChoice = Read-Host "Enter '1' to display the Temporary Access Passes, '2' to export them to CSV"

if ($userChoice -eq "1") {
    # Display the passes
    $accessPasses | Format-Table -AutoSize
}
elseif ($userChoice -eq "2") {
    # Export access passes to CSV

    # Get Arizona Timezone
    $arizonaTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("US Mountain Standard Time")

    # Adjust the expiration time to match Arizona time
    foreach ($accessPass in $accessPasses) {
        $accessPass.ExpirationTime = [System.TimeZoneInfo]::ConvertTime($accessPass.ExpirationTime, $arizonaTimeZone)
    }

    # Prompt for a location to save the CSV file
    $exportPath = Get-FolderUsingGUI

    if ([string]::IsNullOrEmpty($exportPath)) {
        Write-Host "Export path is empty. Please provide a valid path." -ForegroundColor Red
        Exit
    }

    $csvFilePath = Join-Path -Path $exportPath -ChildPath "AccessPasses_$tenantName.csv"
    $accessPasses | Export-Csv -Path $csvFilePath -NoTypeInformation

    Write-Host "Temporary access passes generated and exported to CSV successfully." -ForegroundColor Green
    Write-Host "CSV file location: $csvFilePath"
    Write-Host "expiration times displayed are formatted specifically for Arizona TimeZone" -ForegroundColor Yellow
}
else {
    Write-Host "Invalid choice. Please enter '1' or '2'." -ForegroundColor Red
    Exit
}

# Prompt to exit
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
