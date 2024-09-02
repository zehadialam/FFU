param (
    [string]$GroupTag,
    [bool]$Assign = $true
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Installing NuGet..." -ForegroundColor Yellow
Install-PackageProvider -Name NuGet -Force -Confirm:$false | Out-Null
Write-Host "NuGet is installed." -ForegroundColor Green

$modules = @(
    "Microsoft.Graph.DeviceManagement",
    "Microsoft.Graph.DeviceManagement.Enrollment",
    "Microsoft.Graph.Identity.DirectoryManagement",
    "WindowsAutopilotIntune"
)

foreach ($module in $modules) {
    Write-Host "`nInstalling $module module..." -ForegroundColor Yellow
    Install-Module -Name $module -Force -Confirm:$false -AllowClobber -Scope CurrentUser -WarningAction SilentlyContinue
    Write-Host "$module module is installed." -ForegroundColor Green
    Write-Host "Importing $module module..." -ForegroundColor Yellow
    Import-Module -Name $module -Force -NoClobber -WarningAction SilentlyContinue
    Write-Host "$module module is imported" -ForegroundColor Green
}

do {
    $prompt = Read-Host "`nPress Enter to continue"
} while ($prompt -ne "")

Connect-MgGraph -NoWelcome

$serialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
Write-Host "`nDevice serial number is $serialNumber" -ForegroundColor Yellow

Write-Host "Checking if device already exists in Intune..." -ForegroundColor Yellow
$intuneDevice = Get-MgDeviceManagementManagedDevice -Filter "serialNumber eq '$serialNumber'"
if ($intuneDevice) {
    Write-Host "Device has been found in Intune. Deleting Intune device record..." -ForegroundColor Yellow
    Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $intuneDevice.Id -ErrorAction SilentlyContinue
    Write-Host "Device has been removed from Intune" -ForegroundColor Green
}
else {
    Write-Host "Device does not already exist in Intune" -ForegroundColor Green
}
Write-Host "Checking if device already exists in Entra..." -ForegroundColor Yellow
if ($intuneDevice) {
    $azureAdDeviceId = ($intuneDevice | Select-Object -Property AzureAdDeviceId).AzureAdDeviceId
    $entraDevice = Get-MgDevice -Filter "DeviceId eq '$azureAdDeviceId'"
}
else {
    $entraDevice = Get-MgDevice -Filter "displayName eq '$($env:computername)'"
    if ($entraDevice.Count -gt 1) {
        Write-Host "There are $($entraDevice.Count) devices with the name $($env:computername) in Entra." -ForegroundColor Yellow
        for ($i = 0; $i -lt $entraDevice.Count; $i++) {
            $trustType = ($entraDevice[$i] | Select-Object -Property TrustType).TrustType
            if ($trustType -ne "AzureAd") {
                Write-Host "Deleting device number $i with the name $($env:computername) whose Entra join type is $trustType..." -ForegroundColor Yellow
                Remove-MgDevice -DeviceId $entraDevice[$i].Id -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 10
            }
        }
        $entraDevice = Get-MgDevice -Filter "displayName eq '$($env:computername)'"
    }
}
if ($entraDevice) {
    Write-Host "Device has been found in Entra. Checking if device record needs deletion..." -ForegroundColor Yellow
    $enrollmentType = ($entraDevice | Select-Object -Property EnrollmentType).EnrollmentType
    if ($enrollmentType -ne "AzureDomainJoined") {
        Write-Host "Device enrollment type is $enrollmentType and requires deletion." -ForegroundColor Yellow
        Write-Host "Checking if device is already registered with Autopilot..." -ForegroundColor Yellow
        $autopilotDevice = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$serialNumber')" -ErrorAction Stop
        if ($autopilotDevice) {
            Write-Host "Device is registered with Autopilot. Deleting Autopilot device record..." -ForegroundColor Yellow
            Remove-MgDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $autopilotDevice.Id -ErrorAction Stop
            do {
                Write-Host "Waiting until Autopilot device record is no longer found..." -ForegroundColor Yellow
                $autopilotDevice = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$serialNumber')" -ErrorAction Stop
                Start-Sleep -Seconds 30
            } until (-not $autopilotDevice)
            Write-Host "Device has been removed from Autopilot" -ForegroundColor Green
        }
        else {
            Write-Host "Device is not already registered with Autopilot" -ForegroundColor Green
        }
        Write-Host "Deleting Entra device record..." -ForegroundColor Yellow
        Remove-MgDevice -DeviceId $entraDevice.Id -ErrorAction Stop
        do {
            Write-Host "Waiting until Entra device record is no longer found..." -ForegroundColor Yellow
            $entraDevice = Get-MgDevice -Filter "DeviceId eq '$azureAdDeviceId'"
            Start-Sleep -Seconds 10
        } until (-not $entraDevice)
        Write-Host "Device has been removed from Entra" -ForegroundColor Green
    }
    else {
        Write-Host "Device enrollment type is $enrollmentType and does not require deletion." -ForegroundColor Green
    }
}
else {
    Write-Host "Device does not already exist in Entra" -ForegroundColor Green
}

Write-Host "`nQuerying device with Autopilot..." -ForegroundColor Yellow
$autopilotDevice = Get-AutopilotDevice -Serial $serialNumber

if (-not $autopilotDevice) {
    Write-Host "Device is not registered with Autopilot. Registering device with the group tag $GroupTag...`n" -ForegroundColor Yellow
    Install-Script -Name Get-WindowsAutopilotInfo -Force
    Get-WindowsAutopilotInfo -Online -GroupTag $GroupTag
}
else {
    Write-Host "Device is registered with Autopilot." -ForegroundColor Green
}

if ($autopilotDevice -and $autopilotDevice.GroupTag -ne $GroupTag) {
    Write-Host "Assigning the group tag $GroupTag to the device...`n" -ForegroundColor Yellow
    Set-AutopilotDevice -Id $autopilotDevice.Id -GroupTag $GroupTag
}

$groupMapping = @{
    "CAESATH"     = "CAES OIT-Autopilot"
    "CAESFLD"     = "CAES Field Services Autopilot"
    "CAES-SHARED" = "CAES OIT-Self-Deploying Autopilot"
}

$securityGroupName = $groupMapping[$GroupTag]
$securityGroup = Get-MgGroup -Filter "DisplayName eq '$securityGroupName'"

if (-not $securityGroup) {
    throw "The group $securityGroup was not found"
}

do {
    Write-Host "`nWaiting until Entra device corresponding to Autopilot record is detected..." -ForegroundColor Yellow
    $autopilotDevice = Get-AutopilotDevice -Serial $serialNumber
    $uri = "https://graph.microsoft.com/beta/devices?`$filter=deviceId eq '" + "$(($autopilotDevice).azureActiveDirectoryDeviceId)" + "'"
    $entraDevice = (Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject -SkipHttpErrorCheck).value
    Start-Sleep -Seconds 10
} until ($entraDevice)

Write-Host "Device is now in Entra" -ForegroundColor Green

$entraDeviceInGroup = Get-MgGroupMember -GroupId $securityGroup.Id | Where-Object { $_.Id -eq $entraDevice.Id }
if (-not $entraDeviceInGroup) {
    New-MgGroupMember -GroupId $securityGroup.Id -DirectoryObjectId $entraDevice.Id
    Write-Host "Added device to the $securityGroupName group`n" -ForegroundColor Green
}
else {
    Write-Host "Device already exists in the $securityGroupName group" -ForegroundColor Green
}

if ($Assign) {
    do {
        $profileAssigned = (Get-AutopilotDevice -Serial $serialNumber).DeploymentProfileAssignmentStatus
        if (-not $profileAssigned) {
            $profileAssigned = "Unknown"
        }
        if ($profileAssigned -notlike "assigned*") {
            Write-Host "Waiting for Autopilot profile to be assigned. Current assignment status is: $profileAssigned" -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
        else {
            Write-Host "Autopilot profile is assigned." -ForegroundColor Green
        }
    } while ($profileAssigned -notlike "assigned*")
}

Uninstall-Module -Name WindowsAutopilotIntune -Force -Confirm:$false
if (Get-InstalledScript -Name Get-WindowsAutopilotInfo -ErrorAction SilentlyContinue) {
    Uninstall-Script -Name Get-WindowsAutopilotInfo -Force -Confirm:$false
}

$taskName = "CleanupandRestart"
$command = @"
Remove-Item -Path 'C:\Autopilot' -Recurse -Force
Remove-Item -Path 'C:\Windows\Setup\Scripts' -Recurse -Force
schtasks /Delete /TN '$taskName' /F
shutdown /r /t 3
"@
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$command`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(3)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Priority 0
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings
