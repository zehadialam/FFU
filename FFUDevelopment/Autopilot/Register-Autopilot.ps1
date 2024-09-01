param (
    [string]$GroupTag,
    [bool]$Assign = $true
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Installing NuGet..." -ForegroundColor Yellow
Install-PackageProvider -Name NuGet -Force -Confirm:$false | Out-Null
Write-Host "NuGet is installed." -ForegroundColor Green

Write-Host "`nInstalling Microsoft.Graph.DeviceManagement..." -ForegroundColor Yellow
Install-Module -Name Microsoft.Graph.DeviceManagement -Force -Confirm:$false
Write-Host "Installed Microsoft.Graph.DeviceManagement" -ForegroundColor Green
Write-Host "Importing Microsoft.Graph.DeviceManagement module..." -ForegroundColor Yellow
Import-Module -Name Microsoft.Graph.DeviceManagement
Write-Host "Microsoft.Graph.DeviceManagement module is imported" -ForegroundColor Green

Write-Host "`nInstalling Microsoft.Graph.DeviceManagement.Enrollment" -ForegroundColor Yellow
Install-Module -Name Microsoft.Graph.DeviceManagement.Enrollment -Force -Confirm:$false
Write-Host "Installed Microsoft.Graph.DeviceManagement.Enrollment" -ForegroundColor Green
Write-Host "Importing Microsoft.Graph.DeviceManagement.Enrollment module..." -ForegroundColor Yellow
Import-Module -Name Microsoft.Graph.DeviceManagement.Enrollment
Write-Host "Microsoft.Graph.DeviceManagement.Enrollment module is imported" -ForegroundColor Green

Write-Host "`nInstalling Microsoft.Graph.DirectoryManagement..." -ForegroundColor Yellow
Install-Module -Name Microsoft.Graph.DirectoryManagement -Force -Confirm:$false
Write-Host "Installed Microsoft.Graph.DirectoryManagement" -ForegroundColor Green
Write-Host "Importing Microsoft.Graph.DirectoryManagement module..." -ForegroundColor Yellow
Import-Module -Name Microsoft.Graph.DirectoryManagement
Write-Host "Microsoft.Graph.DirectoryManagement module is imported" -ForegroundColor Green

Write-Host "`nInstalling WindowsAutopilotIntuneCommunity module..." -ForegroundColor Yellow
Install-Module -Name WindowsAutopilotIntuneCommunity -Force -Confirm:$false
Write-Host "WindowsAutopilotIntuneCommunity module is installed." -ForegroundColor Green
Write-Host "Importing WindowsAutopilotIntuneCommunity module..." -ForegroundColor Yellow
Import-Module -Name WindowsAutopilotIntuneCommunity
Write-Host "WindowsAutopilotIntuneCommunity module is imported" -ForegroundColor Green

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
    $intuneDevice | Remove-MgDeviceManagementManagedDevice -ErrorAction SilentlyContinue
    Write-Host "Device has been removed from Intune" -ForegroundColor Green
    Write-Host "Checking if device already exists in Entra..." -ForegroundColor Yellow
    $azureAdDeviceId = ($intuneDevice | Select-Object -Property AzureAdDeviceId).AzureAdDeviceId
    $entraDevice = Get-MgDevice -Filter "DeviceId eq '$azureAdDeviceId'"
    if ($entraDevice) {
        Write-Host "Device has been found in Entra. Checking if device records needs deletion..." -ForegroundColor Yellow
        $enrollmentType = ($entraDevice | Select-Object -Property EnrollmentType).EnrollmentType
        if ($enrollmentType -ne "AzureDomainJoined") {
            Write-Host "Device enrollment type is $enrollmentType and requires deletion. Checking if device is already registered with Autopilot..." -ForegroundColor Yellow
            $autopilotDevice = Get-AutopilotDevice -Serial $serialNumber
            if ($autopilotDevice) {
                Write-Host "Device is registered with Autopilot. Deleting Autopilot device record..." -ForegroundColor Yellow
                $autopilotDevice | Remove-AutopilotDevice -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5
                Write-Host "Device has been removed from Autopilot" -ForegroundColor Green
            }
            Write-Host "Deleting Entra device record..." -ForegroundColor Yellow
            $entraDevice | Remove-MgDevice -ErrorAction SilentlyContinue
            Write-Host "Device has been removed from Entra" -ForegroundColor Green
        }
    }
}

Write-Host "`nQuerying device with Autopilot..." -ForegroundColor Yellow
$autopilotDevice = Get-AutopilotDevice -Serial $serialNumber

if (-not $autopilotDevice) {
    Write-Host "Device is not registered with Autopilot. Registering device with the group tag $GroupTag...`n" -ForegroundColor Yellow
    Install-Script -Name Get-WindowsAutopilotInfoCommunity -Force
    Get-WindowsAutopilotInfoCommunity -Online -GroupTag $GroupTag
    Write-Host "`n"
}

if ($autopilotDevice -and $autopilotDevice.GroupTag -ne $GroupTag) {
    Write-Host "`nDevice is registered with Autopilot, but group tag does not equal $GroupTag" -ForegroundColor Yellow
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
$uri = "https://graph.microsoft.com/beta/devices?`$filter=deviceId eq '" + "$(($autopilotDevice).azureActiveDirectoryDeviceId)" + "'"
$entraDevice = (Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject -SkipHttpErrorCheck).value
if (-not $entraDevice) {
    throw "The device was not found in Entra"
}
New-MgGroupMember -GroupId $securityGroup.Id -DirectoryObjectId $entraDevice.Id
Write-Host "Added device to the $securityGroup group" -ForegroundColor Green

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

Uninstall-Module -Name WindowsAutopilotIntuneCommunity -Force -Confirm:$false
if (Get-InstalledScript -Name Get-WindowsAutopilotInfoCommunity) {
    Uninstall-Script -Name Get-WindowsAutopilotInfoCommunity -Force -Confirm:$false
}

$taskName = "CleanupandRestart"
$command = @"
$modules = Get-InstalledModule -Name Microsoft.Graph* -ErrorAction SilentlyContinue
foreach ($module in $modules) {
    Uninstall-Module -Name $module.Name -Force
}
Remove-Item -Path 'C:\Autopilot' -Recurse -Force
Remove-Item -Path 'C:\Windows\Setup\Scripts' -Recurse -Force
schtasks /Delete /TN '$taskName' /F
shutdown /r /t 3
"@
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$command`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(3)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal