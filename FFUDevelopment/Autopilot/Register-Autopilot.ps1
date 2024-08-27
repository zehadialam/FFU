param (
    [string]$GroupTag,
    [bool]$Expedited = $false
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
    Write-Host "Installing NuGet..." -ForegroundColor Green
    Install-PackageProvider -Name NuGet -Force -Confirm:$false | Out-Null
    Write-Host "NuGet is installed." -ForegroundColor Green
}

if (-not (Get-Module -ListAvailable -Name WindowsAutopilotIntune -ErrorAction Ignore)) {
    Write-Host "`nInstalling WindowsAutopilotIntune module..." -ForegroundColor Green
    Install-Module -Name WindowsAutopilotIntune -Force -Confirm:$false
    Write-Host "WindowsAutopilotIntune module is installed." -ForegroundColor Green
    Write-Host "Importing WindowsAutopilotIntune module..." -ForegroundColor Green
    Import-Module WindowsAutopilotIntune
}

do {
    $prompt = Read-Host "Press Enter to continue"
} while ($prompt -ne "")

Connect-MgGraph -NoWelcome

$serialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
Write-Host "`nQuerying device with Autopilot..." -ForegroundColor Yellow
$autopilotDevice = Get-AutopilotDevice -Serial $serialNumber

if (-not $autopilotDevice) {
    Write-Host "Device is not registered with Autopilot. Registering device with the group tag $GroupTag...`n" -ForegroundColor Yellow
    Install-Script -Name Get-WindowsAutopilotInfo -Force
    Get-WindowsAutopilotInfo -Online -GroupTag $GroupTag
    Write-Host "`n"
}

if ($autopilotDevice -and -not $autopilotDevice.GroupTag) {
    Write-Host "`nDevice is registered with Autopilot, but no group tag is set" -ForegroundColor Yellow
    Write-Host "Assigning the group tag $GroupTag to the device...`n" -ForegroundColor Yellow
    Set-AutopilotDevice -Id $autopilotDevice.Id -GroupTag $GroupTag
}

if (-not $Expedited) {
    do {
        $profileAssigned = $autopilotDevice.DeploymentProfileAssignmentStatus
        if ($profileAssigned -notlike "assigned*") {
            Write-Host "Waiting for Autopilot profile to be assigned. Current assignment status is: $profileAssigned" -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        } else {
            Write-Host "Autopilot profile is assigned." -ForegroundColor Green
        }
    } while ($profileAssigned -notlike "assigned*")
}

Uninstall-Script -Name Get-WindowsAutopilotInfo -Force -Confirm:$false
Uninstall-Module -Name WindowsAutopilotIntune -Force -Confirm:$false

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
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal