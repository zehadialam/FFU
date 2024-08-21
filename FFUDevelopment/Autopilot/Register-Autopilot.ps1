param (
    [string]$GroupTag
)

if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
    Write-Host "Installing NuGet..." -ForegroundColor Green
    Install-PackageProvider -Name NuGet -Force -Confirm:$false
}

if (-not (Get-Module -ListAvailable -Name WindowsAutopilotIntune -ErrorAction Ignore)) {
    Write-Host "Installing WindowsAutopilotIntune module..." -ForegroundColor Green
    Install-Module -Name WindowsAutopilotIntune -Force -Confirm:$false
    Import-Module WindowsAutopilotIntune
}

Connect-MgGraph -NoWelcome

$serialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
$autopilotDevice = Get-AutopilotDevice -Serial $serialNumber

if (-not $autopilotDevice) {
    Write-Host "Registering device with Autopilot with the group tag $GroupTag..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-Script -Name Get-WindowsAutopilotInfo -Force
    Get-WindowsAutopilotInfo -Online -GroupTag $GroupTag
}

if ($autopilotDevice -and -not $autopilotDevice.GroupTag) {
    Write-Warning "Device is registered with Autopilot, but no group tag is set"
    Write-Host "Assigning the group tag $GroupTag to the device..."
    Set-AutopilotDevice -Id $autopilotDevice.Id -GroupTag $GroupTag
} 

do {
    $profileAssigned = (Get-AutopilotDevice -Serial $serialNumber).DeploymentProfileAssignmentStatus
    if ($profileAssigned -eq "notAssigned") {
        Write-Host "Waiting for Autopilot profile to be assigned..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
} while ($profileAssigned -eq "notAssigned")

# Restart-Computer -Force