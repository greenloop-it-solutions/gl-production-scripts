# Check and install required modules silently
$requiredModules = @('MicrosoftTeams', 'ImportExcel')

foreach ($module in $requiredModules) {
    if (-not (Get-Module -Name $module -ListAvailable)) {
        Install-Module -Name $module -Force -Scope CurrentUser -AllowClobber -Quiet
    }
}

# Error handling function
function Handle-Error {
    param (
        [string]$errorMessage
    )
    Write-Host "Error: $errorMessage"
    exit 1
}

# Connect to Microsoft Teams
try {
    Import-Module MicrosoftTeams -ErrorAction Stop
    Connect-MicrosoftTeams -ErrorAction Stop
}
catch {
    Handle-Error "Failed to connect to Microsoft Teams."
}

# Retrieve all users with non-null LineUri
try {
    $users = Get-CsOnlineUser | Where-Object { $_.LineUri -ne $null }
}
catch {
    Handle-Error "Failed to retrieve user data."
}

# Sort users by active/inactive/resource account
$activeUsers = $users | Where-Object { $_.AccountEnabled -eq $true }
$inactiveUsers = $users | Where-Object { $_.AccountEnabled -eq $false -and $_.FeatureTypes -notcontains 'VoiceApp' }
$resourceAccounts = $users | Where-Object { $_.FeatureTypes -contains 'VoiceApp' }

# Retrieve tenant display name
try {
    $tenant = Get-CsTenant
    $tenantDisplayName = $tenant.DisplayName
}
catch {
    Handle-Error "Failed to retrieve tenant display name."
}

# Retrieve auto-attendants
try {
    $autoAttendants = Get-CsAutoAttendant
}
catch {
    Handle-Error "Failed to retrieve auto-attendants."
}

# Map resource accounts to auto-attendants
$resourceAccountMappings = $resourceAccounts | ForEach-Object {
    $resourceAccount = $_
    $autoAttendant = $autoAttendants | Where-Object { $_.ApplicationInstances -contains $resourceAccount.Identity }
    $autoAttendantName = $autoAttendant.Name

    [PSCustomObject]@{
        AutoAttendantName = $autoAttendantName
        ResourceAccount = $resourceAccount.DisplayName
        PhoneNumber = $resourceAccount.LineUri -replace '^tel:\+(\d{1})(\d{3})(\d{3})(\d{4})', '+$1 ($2) $3-$4'
    }
}

# Prompt user to select a location for saving the file
$folderBrowser = New-Object -ComObject Shell.Application
$selectedFolder = $folderBrowser.BrowseForFolder(0, "Select a location to save the Excel file", 0)

if ($selectedFolder -ne $null) {
    $selectedFolderPath = $selectedFolder.Self.Path
    $currentDate = Get-Date -Format 'yyyyMMdd'
    $fileName = Join-Path -Path $selectedFolderPath -ChildPath "TVDID$tenantDisplayName$currentDate.xlsx"

    # Export to Excel with dynamic file name in the selected folder
    try {
        # Import the required module
        Import-Module ImportExcel -ErrorAction Stop

        if ($activeUsers.Count -gt 0) {
            $activeUsers | Select-Object DisplayName, UserPrincipalName, @{Name='PhoneNumber';Expression={$_.LineUri -replace '^tel:\+(\d{1})(\d{3})(\d{3})(\d{4})', '+$1 ($2) $3-$4'}} | Export-Excel -Path $fileName -AutoSize -TableName 'ActiveUsers' -WorksheetName 'Active Users' -ErrorAction Stop
        }

        if ($inactiveUsers.Count -gt 0) {
            $inactiveUsers | Select-Object DisplayName, UserPrincipalName, @{Name='PhoneNumber';Expression={$_.LineUri -replace '^tel:\+(\d{1})(\d{3})(\d{3})(\d{4})', '+$1 ($2) $3-$4'}} | Export-Excel -Path $fileName -AutoSize -TableName 'InactiveUsers' -WorksheetName 'Inactive Users' -ErrorAction Stop
        }

        if ($resourceAccountMappings.Count -gt 0) {
            $resourceAccountMappings | Select-Object AutoAttendantName, ResourceAccount, PhoneNumber | Export-Excel -Path $fileName -AutoSize -TableName 'AutoAttendants' -WorksheetName 'Auto Attendants' -ErrorAction Stop
        }

        Write-Host "Export completed successfully. File saved as $fileName"
    }
    catch {
        Handle-Error "Failed to export data to Excel. Error: $($Error[0].Exception.Message)"
    }
}
else {
    Write-Host "No folder selected. Export aborted."
}
