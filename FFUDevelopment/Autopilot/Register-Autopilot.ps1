#Requires -PSEdition Desktop
#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
 .SYNOPSIS
   A PowerShell script to register a device with Windows Autopilot.

 .DESCRIPTION
   This script automates the process of registering a device with Windows Autopilot and assigning it 
   to the appropriate security group based on the specified group tag. It will delete any existing
   Intune, Entra, and Autopilot record for the device if they exist in the tenant.

 .PARAMETER GroupTag
   The group tag to assign to the device in Autopilot.

 .PARAMETER AddToGroup
   Whether to add the device to a group based on the AutopilotGroupMapping.json file.

 .PARAMETER Assign
   Whether to wait for the Autopilot profile to be assigned. Defaults to $true.

 .PARAMETER Sysprep
   Whether to sysprep the device after Autopilot registration. Defaults to $true.

 .NOTES
   Author: Zehadi Alam

 .EXAMPLE
   .\Register-Autopilot.ps1 -GroupTag "Sales"

 .EXAMPLE
   .\Register-Autopilot.ps1 -GroupTag "Sales" -Assign $false

 .EXAMPLE
   .\Register-Autopilot.ps1 -GroupTag "Sales" -Sysprep $false

 .EXAMPLE
   .\Register-Autopilot.ps1 -GroupTag "Sales" -Assign $false -Sysprep $false
#>

param (
    [string]$GroupTag,
    [bool]$AddToGroup = $true,
    [bool]$Assign = $true,
    [bool]$Sysprep = $true
)

#region Functions 

function Install-RequiredModules {
    $progressPreference = 'silentlyContinue'
    if (-not (Get-PackageProvider -Name NuGet -Force -ErrorAction SilentlyContinue)) {
        Write-Host "Installing NuGet..." -ForegroundColor Yellow
        Install-PackageProvider -Name NuGet -Force -Confirm:$false | Out-Null
        Write-Host "NuGet is installed." -ForegroundColor Green
    }
    $modules = @(
        "Microsoft.Graph.Beta.DeviceManagement.Enrollment",
        "Microsoft.Graph.DeviceManagement",
        "Microsoft.Graph.DeviceManagement.Actions",
        "Microsoft.Graph.DeviceManagement.Enrollment",
        "Microsoft.Graph.Groups",
        "Microsoft.Graph.Identity.DirectoryManagement"
    )
    foreach ($module in $modules) {
        if (-not (Get-InstalledModule -Name $module -ErrorAction SilentlyContinue)) {
            Write-Host "`nInstalling $module module..." -ForegroundColor Yellow
            Install-Module -Name $module -Force -Confirm:$false -AllowClobber -Scope CurrentUser -WarningAction SilentlyContinue | Out-Null
            Write-Host "$module module is installed." -ForegroundColor Green
            Write-Host "Importing $module module..." -ForegroundColor Yellow
            Import-Module -Name $module -Force -Global -NoClobber -WarningAction SilentlyContinue
            Write-Host "$module module is imported" -ForegroundColor Green
        }
    }
}

function Get-AzureAdDeviceId {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber
    )
    $intuneDevice = Get-MgDeviceManagementManagedDevice -Filter "serialNumber eq '$SerialNumber'" -ErrorAction Stop
    if ($intuneDevice) {
        $azureAdDeviceId = $intuneDevice.AzureAdDeviceId
        return $azureAdDeviceId
    }
}

function Get-EntraDevice {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber
    )
    $azureAdDeviceId = Get-AzureAdDeviceId -SerialNumber $SerialNumber
    $entraDeviceResult = if ($azureAdDeviceId) {
        Get-MgDevice -Filter "DeviceId eq '$azureAdDeviceId'"
    }
    return $entraDeviceResult
}

function Remove-IntuneDeviceRecord {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber
    )
    Write-Host "Checking if device already exists in Intune..." -ForegroundColor Yellow
    $intuneDevice = Get-MgDeviceManagementManagedDevice -Filter "serialNumber eq '$SerialNumber'" -ErrorAction Stop
    if (-not $intuneDevice) {
        Write-Host "Device does not already exist in Intune" -ForegroundColor Green
        return
    }
    Write-Host "Device has been found in Intune. Deleting Intune device record..." -ForegroundColor Yellow
    Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $intuneDevice.Id -ErrorAction SilentlyContinue
    Write-Host "Device removed from Intune" -ForegroundColor Green
}

function Remove-AutopilotDeviceRecord {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber
    )
    Write-Host "Checking if device is already registered with Autopilot..." -ForegroundColor Yellow
    $autopilotDevice = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$SerialNumber')" -ErrorAction Stop
    if (-not $autopilotDevice) {
        Write-Host "Device is not already registered with Autopilot" -ForegroundColor Green
        return
    }
    Write-Host "Device is registered with Autopilot. Deleting Autopilot device record..." -ForegroundColor Yellow
    Remove-MgDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $autopilotDevice.Id -ErrorAction Stop
    do {
        $autopilotDevice = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$SerialNumber')" -ErrorAction Stop
        if ($autopilotDevice) {
            Write-Host "Waiting until Autopilot device record is no longer found..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
    } while ($autopilotDevice)
    Write-Host "Device has been removed from Autopilot" -ForegroundColor Green
}

function Remove-EntraDeviceRecord {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber
    )
    Write-Host "Checking if device already exists in Entra..." -ForegroundColor Yellow
    $entraDeviceResult = Get-EntraDevice -ComputerName $ComputerName -SerialNumber $SerialNumber
    if (-not $entraDeviceResult) {
        Write-Host "Device with name $computerName and serial number $SerialNumber does not already exist in Entra." -ForegroundColor Green
        return
    }
    Write-Host "Found device in Entra with the name $ComputerName and serial number $SerialNumber." -ForegroundColor Yellow
    foreach ($entraDevice in $entraDeviceResult) {
        $enrollmentType = $entraDevice.EnrollmentType
        Write-Host "Device enrollment type is $enrollmentType." -ForegroundColor Yellow
        Remove-AutopilotDeviceRecord -SerialNumber $serialNumber
        Write-Host "Deleting Entra device record..." -ForegroundColor Yellow
        Remove-MgDevice -DeviceId $entraDevice.Id -ErrorAction Stop
        do {
            $entraDevice = Get-MgDevice -Filter "DeviceId eq '$($entraDevice.DeviceId)'" -ErrorAction Stop
            if ($entraDevice) {
                Write-Host "Waiting until Entra device record is no longer found..." -ForegroundColor Yellow
                Start-Sleep -Seconds 10
            } 
        } while ($entraDevice)
        Write-Host "Device has been removed from Entra" -ForegroundColor Green
    }
}

function Add-AutopilotDeviceRecord {
    param (
        [string]$HardwareIdentifier,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber,
        [string]$GroupTag
    )
    Write-Host "`nQuerying device with Autopilot..." -ForegroundColor Yellow
    $autopilotDevice = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$serialNumber')" -ErrorAction Stop
    if (-not $autopilotDevice) {
        Write-Host "Device is not registered with Autopilot. Registering device with the group tag $GroupTag..." -ForegroundColor Yellow
        $uri = "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities"
        $body = @{
            "@odata.type" = "#microsoft.graph.importedWindowsAutopilotDeviceIdentity"
            "groupTag" = $groupTag
            "serialNumber" = $serialNumber
            "productKey" = ""
            "hardwareIdentifier" = $hardwareIdentifier
            "assignedUserPrincipalName" = ""
            "state" = @{
                "@odata.type" = "microsoft.graph.importedWindowsAutopilotDeviceIdentityState"
                "deviceImportStatus" = "pending"
                "deviceRegistrationId" = ""
                "deviceErrorCode" = 0
                "deviceErrorName" = ""
            }
        }
        $jsonBody = $body | ConvertTo-Json -Depth 3
        Invoke-MgGraphRequest -Uri $uri -Method Post -Body $jsonBody -ContentType "application/json"
        do {
            $autopilotDevice = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$serialNumber')" -ErrorAction Stop
            if (-not $autopilotDevice) {
                Write-Host "Waiting until Autopilot device record is found..." -ForegroundColor Yellow
                Start-Sleep -Seconds 30
            }
        } until ($autopilotDevice)
        Write-Host "Found device in Autopilot." -ForegroundColor Green
    }
    elseif ($autopilotDevice.GroupTag -ne $GroupTag) {
        Write-Host "Assigning the group tag $GroupTag to the device...`n" -ForegroundColor Yellow
        Update-MgDeviceManagementWindowsAutopilotDeviceIdentityDeviceProperty -WindowsAutopilotDeviceIdentityId $autopilotDevice.Id -GroupTag $GroupTag -ErrorAction Stop
    }
    else {
        Write-Host "Device is registered with Autopilot." -ForegroundColor Green
    }
}

function Wait-EntraDeviceRecord {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber
    )
    $autopilotDevice = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$serialNumber')" -ErrorAction SilentlyContinue
    if (-not $autopilotDevice) {
        throw "Autopilot device not found"
    }
    do {
        $entraDevice = Get-MgDevice -Filter "DeviceId eq '$($autopilotdevice.azureActiveDirectoryDeviceId)'" -ErrorAction Stop
        if (-not $entraDevice) {
            Write-Host "Waiting until Entra device corresponding to Autopilot record is found..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }
    } while (-not $entraDevice)
    Write-Host "Found device in Entra." -ForegroundColor Green
}

function Add-SecurityGroupMember {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber
    )
    $autopilotDevice = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$serialNumber')" -ErrorAction Stop
    if (-not $autopilotDevice) {
        throw "Device not found in Autopilot"
    }
    $entraDevice = Get-MgDevice -Filter "DeviceId eq '$($autopilotdevice.azureActiveDirectoryDeviceId)'" -ErrorAction Stop
    if (-not $entraDevice) {
        throw "Device not found in Entra"
    }
    $autopilotGroupMappingPath = "C:\Autopilot\AutopilotGroupMapping.json"
    if (Test-Path -Path $autopilotGroupMappingPath -PathType Leaf) {
        $autopilotMappings = Get-Content -Raw -Path $autopilotGroupMappingPath | ConvertFrom-Json
    }
    else {
        throw "AutopilotGroupMapping.json file not found"
    }
    $securityGroupName = $autopilotMappings.$GroupTag
    if (-not $securityGroupName) {
        throw "$GroupTag does not correspond to any group name. Check the accuracy of the AutopilotGroupMapping.json file."
    }
    $securityGroup = Get-MgGroup -Filter "DisplayName eq '$securityGroupName'"
    if (-not $securityGroup) {
        throw "The group $securityGroup was not found in Entra"
    }
    $entraDeviceInGroup = Get-MgGroupMember -GroupId $securityGroup.Id | Where-Object { $_.Id -eq $entraDevice.Id }
    if (-not $entraDeviceInGroup) {
        # New-MgGroupMember -GroupId $securityGroup.Id -DirectoryObjectId $entraDevice.Id
        $groupuri = "https://graph.microsoft.com/beta/groups/$($securityGroup.Id)/members/`$ref"
        $body = @{
            "@odata.id" = "https://graph.microsoft.com/beta/directoryObjects/$($entraDevice.Id)"
        }
        $jsonBody = $body | ConvertTo-Json -Depth 2
        Invoke-MgGraphRequest -Method POST -Uri $groupuri -Body $jsonBody -ContentType "application/json" -OutputType PSObject
        Write-Host "Added device to the $securityGroupName group`n" -ForegroundColor Green
    }
    else {
        Write-Host "Device already exists in the $securityGroupName group" -ForegroundColor Green
    }
}

function Wait-AutopilotProfileAssignment {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SerialNumber
    )
    if (-not $Assign) {
        return 
    }
    do {
        $autopilotDevice = Get-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$serialNumber')" -ErrorAction Stop
        $profileAssignmentStatus = $autopilotDevice.DeploymentProfileAssignmentStatus -as [string]
        if (-not ($profileAssignmentStatus.StartsWith("assigned"))) {
            Write-Host "Waiting for Autopilot profile to be assigned. Current assignment status is: $profileAssignmentStatus" -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
        else {
            Write-Host "Autopilot profile is assigned." -ForegroundColor Green
        }
    } until ($profileAssignmentStatus.StartsWith("assigned"))
}

function New-CleanupScheduledTask {
    $startCleanupAndSysprepPath = "C:\Autopilot\Start-CleanupAndSysprep.ps1"
    if (-not (Test-Path -Path $startCleanupAndSysprepPath -PathType Leaf)) {
        throw "Start-CleanupAndSysprep.ps1 file not found"
    }
    $taskName = "CleanupAndSysprep"
    $command = Get-Content -Path $startCleanupAndSysprepPath -Raw
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Priority 0
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
}

#endregion

#region Main

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

    Install-RequiredModules

    $manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    $model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
    $serialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
    $computerName = $env:COMPUTERNAME
    $deviceHardwareData = (Get-CimInstance -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData
    # $hardwareIdentifier = [System.Convert]::FromBase64String($deviceHardwareData)

    do {
        $prompt = Read-Host "`nPress Enter to log in with your administrative Entra account"
    } while ($prompt -ne "")

    $scopes = @(
        "Device.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "DeviceManagementServiceConfig.ReadWrite.All",
        "Group.ReadWrite.All",
        "GroupMember.ReadWrite.All"
    )
    
    Connect-MgGraph -Scopes $scopes -NoWelcome
    
    Write-Host "`nDevice manufacturer is $manufacturer" -ForegroundColor Yellow
    Write-Host "Device model is $model" -ForegroundColor Yellow
    Write-Host "Device serial number is $serialNumber" -ForegroundColor Yellow
    Write-Host "Device name is $computerName" -ForegroundColor Yellow

    $entraDeviceResult = Get-EntraDevice -ComputerName $ComputerName -SerialNumber $SerialNumber
    if ($entraDeviceResult.EnrollmentType -eq "AzureADJoinUsingDeviceAuth") {
        Write-Host "This device has a self-deploying Autopilot profile assigned. You may close the command prompt window." -ForegroundColor Yellow
        Remove-Item -Path "C:\Autopilot" -Recurse -Force
        Remove-Item -Path "C:\Windows\Setup\Scripts" -Recurse -Force
        exit
    }

    Remove-IntuneDeviceRecord -SerialNumber $serialNumber
    Remove-EntraDeviceRecord -ComputerName $computerName -SerialNumber $serialNumber
    Add-AutopilotDeviceRecord -HardwareIdentifier $deviceHardwareData -SerialNumber $serialNumber -GroupTag $GroupTag
    Wait-EntraDeviceRecord -SerialNumber $serialNumber
    Add-SecurityGroupMember -SerialNumber $serialNumber
    Wait-AutopilotProfileAssignment -SerialNumber $serialNumber

    if ($Sysprep) {
        New-CleanupScheduledTask
        Write-Host "Cleaning up scripts. Device will automatically restart once complete." -ForegroundColor Yellow
    }
}
catch {
    throw $_
}
finally {
    Disconnect-MgGraph | Out-Null
}

#endregion
