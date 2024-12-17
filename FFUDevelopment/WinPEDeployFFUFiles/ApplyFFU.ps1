function Get-USBDrive() {
    $USBDriveLetter = (Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.FileSystemType -eq 'NTFS' }).DriveLetter
    if ($null -eq $USBDriveLetter) {
        #Must be using a fixed USB drive - difficult to grab drive letter from win32_diskdrive. Assume user followed instructions and used Deploy as the friendly name for partition
        $USBDriveLetter = (Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.FileSystemType -eq 'NTFS' -and $_.FileSystemLabel -eq 'Deploy' }).DriveLetter
        #If we didn't get the drive letter, stop the script.
        if ($null -eq $USBDriveLetter) {
            WriteLog 'Cannot find USB drive letter - most likely using a fixed USB drive. Name the 2nd partition with the FFU files as Deploy so the script can grab the drive letter. Exiting'
            exit
        }
    }
    $USBDriveLetter = $USBDriveLetter + ":\"
    return $USBDriveLetter
}

function Get-HardDrive() {
    $SystemInfo = Get-WmiObject -Class 'Win32_ComputerSystem'
    $Manufacturer = $SystemInfo.Manufacturer
    $Model = $SystemInfo.Model
    WriteLog "Device Manufacturer: $Manufacturer"
    WriteLog "Device Model: $Model"
    WriteLog 'Getting Hard Drive info'
    if ($Manufacturer -eq 'Microsoft Corporation' -and $Model -eq 'Virtual Machine') {
        WriteLog 'Running in a Hyper-V VM. Getting virtual disk on Index 0 and SCSILogicalUnit 0'
        $DiskDrive = Get-WmiObject -Class 'Win32_DiskDrive' | Where-Object { $_.MediaType -eq 'Fixed hard disk media' `
                -and $_.Model -eq 'Microsoft Virtual Disk' `
                -and $_.Index -eq 0 `
                -and $_.SCSILogicalUnit -eq 0
        }
    }
    else {
        WriteLog 'Not running in a VM. Getting physical disk drive'
        $DiskDrive = Get-WmiObject -Class 'Win32_DiskDrive' | Where-Object { $_.MediaType -eq 'Fixed hard disk media' -and $_.Model -ne 'Microsoft Virtual Disk' }
    }
    $DeviceID = $DiskDrive.DeviceID
    $BytesPerSector = $Diskdrive.BytesPerSector
    $result = New-Object PSObject -Property @{
        DeviceID       = $DeviceID
        BytesPerSector = $BytesPerSector
    }
    return $result
}

function WriteLog($LogText) { 
    Add-Content -path $LogFile -value "$((Get-Date).ToString()) $LogText"
}

function Set-Computername {
    param (
        [Parameter(Mandatory = $true)]
        [string]$computername
    )
    try {
        [xml]$xml = Get-Content -Path $UnattendFile -ErrorAction Stop
        $nsManager = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsManager.AddNamespace("u", "urn:schemas-microsoft-com:unattend")
        $computerNameNodes = $xml.SelectNodes("//u:ComputerName", $nsManager)
        if ($computerNameNodes.Count -eq 0) {
            WriteLog "No ComputerName node found in the unattend.xml file. Adding a new one."
            $componentNode = $xml.SelectSingleNode("//u:component", $nsManager)
            if ($componentNode) {
                $newComputerNameNode = $xml.CreateElement("ComputerName", "urn:schemas-microsoft-com:unattend")
                $newComputerNameNode.InnerText = $computername
                $componentNode.AppendChild($newComputerNameNode) | Out-Null
            }
        }
        else {
            foreach ($node in $computerNameNodes) {
                $node.InnerText = $computername
            }
        }
        $xml.Save($UnattendFile)
        WriteLog "Computer name set to: $computername"
        return $computername
    }
    catch {
        WriteLog "An error occurred: $_"
        throw $_
    }
}

function Invoke-Process {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ArgumentList
    )
    $ErrorActionPreference = 'Stop'
    try {
        $stdOutTempFile = "$env:TEMP\$((New-Guid).Guid)"
        $stdErrTempFile = "$env:TEMP\$((New-Guid).Guid)"
        $startProcessParams = @{
            FilePath               = $FilePath
            ArgumentList           = $ArgumentList
            RedirectStandardError  = $stdErrTempFile
            RedirectStandardOutput = $stdOutTempFile
            Wait                   = $true;
            PassThru               = $true;
            NoNewWindow            = $false;
        }
        if ($PSCmdlet.ShouldProcess("Process [$($FilePath)]", "Run with args: [$($ArgumentList)]")) {
            $cmd = Start-Process @startProcessParams
            $cmdOutput = Get-Content -Path $stdOutTempFile -Raw
            $cmdError = Get-Content -Path $stdErrTempFile -Raw
            if ($cmd.ExitCode -ne 0) {
                if ($cmdError) {
                    throw $cmdError.Trim()
                }
                if ($cmdOutput) {
                    throw $cmdOutput.Trim()
                }
            }
            else {
                if ([string]::IsNullOrEmpty($cmdOutput) -eq $false) {
                    WriteLog $cmdOutput
                }
            }
        }
    }
    catch {
        #$PSCmdlet.ThrowTerminatingError($_)
        WriteLog $_
        Write-Host 'Script failed - check scriptlog.txt on the USB drive for more info'
        throw $_
    }
    finally {
        Remove-Item -Path $stdOutTempFile, $stdErrTempFile -Force -ErrorAction Ignore
    }
}

function Enable-DellBIOSSetting {
    param (
        [string]$BiosSettingsPath,
        [string]$SettingName,
        [string]$ExpectedValue,
        [string]$SuccessMessage,
        [string]$UnsupportedMessage,
        [string]$Pw = $null
    )
    $setting = Get-ChildItem -Path $BiosSettingsPath -ErrorAction SilentlyContinue | 
    Where-Object { $_.Attribute -contains $SettingName }
    if (-not $setting) {
        Write-Host $UnsupportedMessage -ForegroundColor Yellow
        return
    }
    $settingValue = $setting.CurrentValue
    if ($settingValue -eq $ExpectedValue) {
        Write-Host $SuccessMessage -ForegroundColor Green
    }
    elseif ($SettingName -eq 'TpmActivation') {
        Set-Item -Path DellSmbios:\Security\AdminPassword $Pw
        Set-Item -Path "$BiosSettingsPath\$SettingName" -Value $ExpectedValue -Password $Pw
        Set-Item -Path DellSmbios:\Security\AdminPassword "" -Password $Pw
        Write-Host "$SettingName has been set to $ExpectedValue" -ForegroundColor Green
    }
    else {
        Set-Item -Path "$BiosSettingsPath\$SettingName" -Value $ExpectedValue
        Write-Host "$SettingName has been set to $ExpectedValue" -ForegroundColor Green
    }
}

function Optimize-DellBIOSSettings {
    Enable-DellBIOSSetting `
        -BiosSettingsPath 'DellSmbios:\SystemConfiguration' `
        -SettingName 'EmbSataRaid' `
        -ExpectedValue 'Ahci' `
        -SuccessMessage 'AHCI mode is enabled' `
        -UnsupportedMessage 'AHCI mode is not supported on this system'
    Enable-DellBIOSSetting `
        -BiosSettingsPath 'DellSmbios:\SystemConfiguration' `
        -SettingName 'SmartErrors' `
        -ExpectedValue 'Enabled' `
        -SuccessMessage 'SMART reporting is enabled' `
        -UnsupportedMessage 'SMART reporting is not supported on this system'
    Enable-DellBIOSSetting `
        -BiosSettingsPath 'DellSmbios:\PreEnabled' `
        -SettingName 'IntelTME' `
        -ExpectedValue 'Enabled' `
        -SuccessMessage 'Intel Total Memory Encryption is enabled' `
        -UnsupportedMessage 'Intel Total Memory Encryption is not supported on this system'
    Enable-DellBIOSSetting `
        -BiosSettingsPath 'DellSmbios:\Security' `
        -SettingName 'AmdTSME' `
        -ExpectedValue 'Enabled' `
        -SuccessMessage 'AMD Transparent Secure Memory Encryption is enabled' `
        -UnsupportedMessage 'AMD Transparent Secure Memory Encryption is not supported on this system'
    Enable-DellBIOSSetting `
        -BiosSettingsPath 'DellSmbios:\AdvancedBootOptions' `
        -SettingName 'LegacyOrom' `
        -ExpectedValue 'Disabled' `
        -SuccessMessage 'Legacy Option ROMs are disabled' `
        -UnsupportedMessage 'Legacy Option ROMs are not supported on this system'
    Enable-DellBIOSSetting `
        -BiosSettingsPath 'DellSmbios:\SecureBoot' `
        -SettingName 'SecureBoot' `
        -ExpectedValue 'Enabled' `
        -SuccessMessage 'Secure Boot is enabled' `
        -UnsupportedMessage 'Secure Boot is not supported on this system'
    Enable-DellBIOSSetting `
        -BiosSettingsPath 'DellSmbios:\TpmSecurity' `
        -SettingName 'TpmSecurity' `
        -ExpectedValue 'Enabled' `
        -SuccessMessage 'TPM is enabled' `
        -UnsupportedMessage 'TPM is not supported on this system'
    Enable-DellBIOSSetting `
        -BiosSettingsPath 'DellSmbios:\TpmSecurity' `
        -SettingName 'TpmActivation' `
        -ExpectedValue 'Enabled' `
        -SuccessMessage 'TPM is activated' `
        -UnsupportedMessage 'TPM activation is not supported on this system' `
        -Password 'password'
    Enable-DellBIOSSetting `
        -BiosSettingsPath 'DellSmbios:\VirtualizationSupport' `
        -SettingName 'TrustExecution' `
        -ExpectedValue 'Enabled' `
        -SuccessMessage 'Trusted Execution is enabled' `
        -UnsupportedMessage 'Trusted Execution is not supported on this system'
}

function Optimize-BIOSSettings {
    param (
        [string]$ComputerManufacturer
    )
    if ($ComputerManufacturer -eq "Dell Inc.") {
        Write-Host "Configuring BIOS settings...`n" -ForegroundColor Yellow
        Write-Host "Importing DellBIOSProvider module..." -ForegroundColor Yellow
        Import-Module DellBIOSProvider -ErrorAction SilentlyContinue | Out-Null
        Write-Host "DellBIOSProvider module is imported`n" -ForegroundColor Green
        Optimize-DellBIOSSettings
        Write-Host "`nConfiguring BIOS settings complete" -ForegroundColor Green
    }
}

function Get-LocalDrivers {
    param (
        [string]$Model
    )
    $driverFolder = "W:\Drivers"
    $driverFolderPath = Join-Path -Path $driverFolder -ChildPath $model
    if (Test-Path -Path $driverFolderPath -PathType Container) {
        return $driverFolderPath
    }
}

function Save-DriverPack {
    param (
        [string]$Manufacturer,
        [string]$Model
    )
    $manufacturerMap = @{
        "Dell Inc." = @{
            UpdateCatalogCommand = { Update-DellDriverPackCatalog -UpdateModuleCatalog | Out-Null }
            GetDriverPackCommand = { Get-DellDriverPack -Compatible }
            GetDriverPackUrl     = { param($result) $result | Sort-Object -Property DriverPackOS -Descending | Select-Object -ExpandProperty DriverPackUrl -First 1 }
            GetDriverPackHash    = { param($result) $result | Sort-Object -Property DriverPackOS -Descending | Select-Object -ExpandProperty HashMD5 -First 1 }
            ExtractCommand       = { param($installer, $destination) Start-Process -FilePath $installer -ArgumentList "/e=$($destination)", "/s" -Wait -NoNewWindow }
            HashAlgorithm        = "MD5"
        }
    }
    if (-not $manufacturerMap.ContainsKey($Manufacturer)) {
        Write-Warning "Unsupported manufacturer: $Manufacturer"
        return
    }
    try {
        Write-Host "`nPreparing to install drivers..." -ForegroundColor Yellow
        Write-Host "Importing OSD module..." -ForegroundColor Yellow
        Import-Module OSD -ErrorAction SilentlyContinue | Out-Null
        Write-Host "OSD module is imported" -ForegroundColor Green
        Write-Host "`nRetrieving latest $Manufacturer driver pack catalog...`n" -ForegroundColor Yellow
        $manufacturerMap[$Manufacturer].UpdateCatalogCommand.Invoke()
        $driverPackResult = $manufacturerMap[$Manufacturer].GetDriverPackCommand.Invoke()
        if (-not $driverPackResult) {
            Write-Warning "Failed to retrieve $Model driver pack."
            return
        }
        $driverPackUrl = $manufacturerMap[$Manufacturer].GetDriverPackUrl.Invoke($driverPackResult)
        $driverPackUrl = [string]$driverPackUrl
        if (-not $driverPackUrl) {
            Write-Warning "Failed to retrieve $Model driver pack."
            return
        }
        $driverPackHash = $manufacturerMap[$Manufacturer].GetDriverPackHash.Invoke($driverPackResult)
        $driverPackHash = [string]$driverPackHash
        $driverFolder = "W:\Drivers"
        New-Item -Path $driverFolder -ItemType Directory -Force | Out-Null
        $driverPack = Split-Path -Path $driverPackUrl -Leaf
        $driverPackInstaller = Join-Path -Path $driverFolder -ChildPath $driverPack
        $curl = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath "curl\bin\curl.exe"
        Write-Host "`nDownloading latest $Model driver pack from $driverPackUrl...`n" -ForegroundColor Yellow
        Start-Process -FilePath $curl -ArgumentList "--connect-timeout 10", "-L", "--retry 5", "--retry-delay 1", "--retry-all-errors", $driverPackUrl, "-o $driverPackInstaller" -Wait -NoNewWindow
        if (-not (Test-Path $driverPackInstaller -PathType Leaf)) {
            Write-Warning "Failed to download $Model driver pack."
            return
        }
        Write-Host "`nCalculating driver pack hash...`n" -ForegroundColor Yellow
        $hashAlgorithm = $manufacturerMap[$Manufacturer].HashAlgorithm
        $downloadedDriverPack = Get-FileHash -Path $driverPackInstaller -Algorithm $hashAlgorithm
        Write-Host "Calculated $hashAlgorithm hash: $($downloadedDriverPack.Hash)"
        Write-Host "Catalog $hashAlgorithm hash:    $driverPackHash"
        if ($downloadedDriverPack.Hash -ne $driverPackHash) {
            Write-Host "$hashAlgorithm hashes do not match. Driver installation will not proceed." -ForegroundColor Red
            return
        }
        Write-Host "$hashAlgorithm hashes match. Driver pack integrity check succeeded." -ForegroundColor Green
        Write-Host "`nExtracting driver pack to $driverFolder..." -ForegroundColor Yellow
        $driverPackType = Get-Item $driverPackInstaller
        $driverPackFileExtension = $driverPackType.Extension
        if ($driverPackFileExtension -eq ".cab") {
            $extractCommand = { param($installer, $destination) $expand = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath "expand.exe"; Start-Process -FilePath $expand -ArgumentList "-f:*", $installer, $destination -Wait -NoNewWindow }
        }
        else {
            $extractCommand = $manufacturerMap[$Manufacturer].ExtractCommand
        }
        $extractCommand.Invoke($driverPackInstaller, $driverFolder)
        return $driverFolder
    }
    catch {
        throw $_
    }
}

function Update-DellBIOS {
    param (
        [string]$Model
    )
    try {
        Write-Host "`nChecking for BIOS update..." -ForegroundColor Yellow
        $computerBiosVersion = Get-MyBiosVersion
        $catalogBiosVersion = (Get-MyDellBios).DellVersion
        if (-not $catalogBiosVersion) {
            Write-Host "The latest BIOS version could not be determined. Skipping BIOS update." -ForegroundColor Yellow
            return
        }
        if ($computerBiosVersion -ge $catalogBiosVersion) {
            Write-Host "The current BIOS version $computerBiosVersion is the latest." -ForegroundColor Green
            return
        }
        Write-Host "`nThe current BIOS version $computerBiosVersion is not the latest ($catalogBiosVersion)" -ForegroundColor Yellow
        $biosUrl = (Get-MyDellBios).Url
        $flash64WUrl = "https://dl.dell.com/FOLDER10855396M/1/Flash64W_Ver3.3.22.zip"
        $biosHash = ((Get-MyDellBios).HashMD5).toUpper()
        $biosFile = Split-Path -Path $biosUrl -Leaf
        $flash64WFile = Split-Path -Path $flash64WUrl -Leaf
        $biosFilePath = Join-Path -Path "W:\Drivers" -ChildPath $biosFile
        $flash64WFilePath = Join-Path -Path "W:\Drivers" -ChildPath $flash64WFile
        Write-Host "`nDownloading latest $Model bios from $biosUrl...`n" -ForegroundColor Yellow
        $curl = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath "curl\bin\curl.exe"
        Start-Process -FilePath $curl -ArgumentList "--connect-timeout 10", "-L", "--retry 5", "--retry-delay 1", "--retry-all-errors", $biosUrl, "-o $biosFilePath" -Wait -NoNewWindow
        Write-Host "`nDownloading Dell System Firmware Update Utility from $flash64WUrl...`n" -ForegroundColor Green
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.75 Safari/537.36"
        }
        Invoke-WebRequest -Uri $flash64WUrl -OutFile $flash64WFilePath -Headers $headers
        Write-Host "Calculating BIOS hash...`n" -ForegroundColor Yellow
        $downloadedBios = Get-FileHash -Path $biosFilePath -Algorithm MD5
        Write-Host "Calculated MD5 hash: $($downloadedBios.Hash)"
        Write-Host "Catalog MD5 hash:    $biosHash"
        if ($downloadedBios.Hash -ne $biosHash) {
            Write-Host "MD5 hashes do not match. BIOS update will not proceed." -ForegroundColor Red
            return
        }
        Write-Host "MD5 hashes match. BIOS integrity check succeeded." -ForegroundColor Green
        Write-Host "`nExtracting $flash64WFile to W:\Drivers..." -ForegroundColor Yellow
        Expand-Archive -Path $flash64WFilePath -DestinationPath "W:\Drivers" -Force
        $flash64WExe = Get-ChildItem -Path "W:\Drivers" -Filter "Flash64W.exe" -Recurse -File
        if (-not $flash64WExe) {
            Write-Host "Could not find the Dell System Firmware Update Utility" -ForegroundColor Red
            return
        }
        Move-Item -Path $biosFilePath -Destination $flash64WExe.DirectoryName -Force
        Write-Host "`nInstalling BIOS update..." -ForegroundColor Yellow
        Set-Location -Path $flash64WExe.DirectoryName
        Write-Host "Running command $($flash64WExe.FullName) /b=$($biosFile) /s /f /l=x:\Flash64W.log" -ForegroundColor Yellow
        Start-Process -FilePath $flash64WExe.FullName -ArgumentList "/b=$($biosFile) /s /f /l=x:\Flash64W.log" -Wait -NoNewWindow
        Write-Host "BIOS update applied" -ForegroundColor Green
        Set-Location -Path "X:\windows\system32"
    }
    catch {
        throw $_
    }
}

function Get-DownloadedDrivers {
    param (
        [string]$ComputerManufacturer,
        [string]$Model
    )
    do {
        $connection = Test-Connection -ComputerName "www.google.com" -Count 2 -Quiet -ErrorAction SilentlyContinue
        if (-not $connection) {
            Write-Warning "Device is not connected to the Internet. Please connect or reconnect the Ethernet cable. Waiting 5 seconds..."
            Start-Sleep -Seconds 5
        }
    } while (-not $connection)
    $driverPath = Save-DriverPack -Manufacturer $ComputerManufacturer -Model $Model
    return $driverPath
}

function Install-Drivers {
    param (
        [string]$ComputerManufacturer,
        [string]$Model,
        [string]$MountPath
    )
    try {
        #Some drivers can sometimes fail to copy and dism ends up with a non-zero error code. Invoke-process will throw and terminate in these instances. 
        if (Test-Path -Path $Drivers -PathType Container) {
            if ((Get-ChildItem -Path $Drivers | Measure-Object).Count -gt 0) {
                WriteLog 'Copying drivers'
                Write-Warning 'Copying Drivers - dism will pop a window with no progress. This can take a few minutes to complete. This is done so drivers are logged to the scriptlog.txt file. Please be patient.'
                Start-Process -FilePath dism.exe -ArgumentList "/Image:$MountPath", "/Add-Driver", "/Driver:""$Drivers""", "/Recurse" -Wait -NoNewWindow
                WriteLog 'Copying drivers succeeded'
            }
        }
        else {
            $driverPath = Get-LocalDrivers -Model $model
            if ($driverPath -and $ComputerManufacturer -eq "Dell Inc.") {
                Write-Host "Extracting driver pack to $driverPath..." -ForegroundColor Yellow
                $driverPackPath = Get-ChildItem -Path "$driverPath\*" -Include "*.exe" -File -ErrorAction Stop
                if (-not $driverPackPath) {
                    Write-Host "Driver pack path not found" -ForegroundColor Red
                    return
                }
                Start-Process -FilePath $driverPackPath -ArgumentList "/e=$($driverPath)", "/s" -Wait -NoNewWindow
                Write-Host "`nInstalling drivers for $model..." -ForegroundColor Yellow
                Write-Host "`nRunning command DISM /Image:$MountPath /Add-Driver /Driver:""$driverPath"" /Recurse" -ForegroundColor Yellow
                Start-Process -FilePath dism.exe -ArgumentList "/Image:$MountPath", "/Add-Driver", "/Driver:""$driverPath""", "/Recurse" -Wait -NoNewWindow
            }
            if (-not $driverPath) {
                $driverPath = Get-DownloadedDrivers -ComputerManufacturer $ComputerManufacturer -Model $model
                if ($ComputerManufacturer -eq "Dell Inc.") {
                    Update-DellBIOS -Model $Model
                }
            }
            if (-not $driverPath) {
                Write-Warning "Cannot find drivers for the $model model. The imaging process will continue without driver installation at this stage."
                return
            }
            Write-Host "`nInstalling drivers for $model..." -ForegroundColor Yellow
            Write-Host "`nRunning command DISM /Image:$MountPath /Add-Driver /Driver:""$driverPath"" /Recurse" -ForegroundColor Yellow
            Start-Process -FilePath dism.exe -ArgumentList "/Image:$MountPath", "/Add-Driver", "/Driver:""$driverPath""", "/Recurse" -Wait -NoNewWindow
        }
    }
    catch {
        throw $_
    }
    finally {
        $driversFolder = Join-Path -Path $MountPath -ChildPath "Drivers"
        if (Test-Path -Path $driversFolder -PathType Container) {
            Remove-Item -Path $driversFolder -Recurse -Force -Confirm:$false
        }
    }
}
#Get USB Drive and create log file
$LogFileName = 'ScriptLog.txt'
$USBDrive = Get-USBDrive
$LogFileDir = Join-Path -Path $USBDrive -ChildPath "logs"
New-Item -Path $LogFileDir -ItemType Directory -Force | Out-Null
New-item -Path $LogFileDir -Name $LogFileName -ItemType "file" -Force | Out-Null
$LogFile = Join-Path -Path $LogFileDir -ChildPath $LogFilename
$version = '2408.1'
WriteLog 'Begin Logging'
WriteLog "Script version: $version"
$hardDrive = Get-HardDrive
if (-not $hardDrive) {
    WriteLog 'No hard drive found. Exiting'
    WriteLog 'Try adding storage drivers to the PE boot image (you can re-create your FFU and USB drive and add the PE drivers to the PEDrivers folder and add -CopyPEDrivers $true to the command line, or manually add them via DISM)'
    exit
}
$PhysicalDeviceID = $hardDrive.DeviceID
$BytesPerSector = $hardDrive.BytesPerSector
WriteLog "Physical BytesPerSector is $BytesPerSector"
WriteLog "Physical DeviceID is $PhysicalDeviceID"
$DiskID = $PhysicalDeviceID.substring($PhysicalDeviceID.length - 1, 1)
$SetupCompleteData = ""
WriteLog "DiskID is $DiskID"
[array]$FFUFiles = @(Get-ChildItem -Path $USBDrive*.ffu)
$FFUCount = $FFUFiles.Count
if ($FFUCount -gt 1) {
    WriteLog "Found $FFUCount FFU Files"
    $array = @()
    for ($i = 0; $i -le $FFUCount - 1; $i++) {
        $Properties = [ordered]@{Number = $i + 1 ; FFUFile = $FFUFiles[$i].FullName }
        $array += New-Object PSObject -Property $Properties
    }
    $array | Format-Table -AutoSize -Property Number, FFUFile
    do {
        try {
            $var = $true
            [int]$FFUSelected = Read-Host 'Enter the FFU number to install'
            $FFUSelected = $FFUSelected - 1
        }
        catch {
            Write-Host 'Input was not in correct format. Please enter a valid FFU number'
            $var = $false
        }
    } until (($FFUSelected -le $FFUCount - 1) -and $var) 
    $FFUFileToInstall = $array[$FFUSelected].FFUFile
    WriteLog "$FFUFileToInstall was selected"
}
elseif ($FFUCount -eq 1) {
    WriteLog "Found $FFUCount FFU File"
    $FFUFileToInstall = $FFUFiles[0].FullName
    WriteLog "$FFUFileToInstall will be installed"
}
else {
    Writelog 'No FFU files found'
    Write-Host 'No FFU files found'
    exit
}
#FindAP
$APFolder = $USBDrive + "Autopilot\"
If (Test-Path -Path $APFolder) {
    [array]$APFiles = @(Get-ChildItem -Path $APFolder*.json)
    $APFilesCount = $APFiles.Count
    if (Test-Path -Path "$APFolder\AutopilotGroupMapping.json" -PathType Leaf) {
        $APFilesCount -= 1
    }
    if ($APFilesCount -ge 1) {
        $autopilot = $true
    }
}
#FindPPKG
$PPKGFolder = $USBDrive + "PPKG\"
if (Test-Path -Path $PPKGFolder) {
    [array]$PPKGFiles = @(Get-ChildItem -Path $PPKGFolder*.ppkg)
    $PPKGFilesCount = $PPKGFiles.Count
    if ($PPKGFilesCount -ge 1) {
        $PPKG = $true
    }
}
#FindUnattend
$UnattendFolder = $USBDrive + "unattend\"
$UnattendFilePath = $UnattendFolder + "unattend.xml"
$UnattendPrefixPath = $UnattendFolder + "prefixes.txt"
If (Test-Path -Path $UnattendFilePath) {
    $UnattendFile = Get-ChildItem -Path $UnattendFilePath
    If ($UnattendFile) {
        $Unattend = $true
    }
}
If (Test-Path -Path $UnattendPrefixPath) {
    $UnattendPrefixFile = Get-ChildItem -Path $UnattendPrefixPath
    If ($UnattendPrefixFile) {
        $UnattendPrefix = $true
    }
}
#Ask for device name if unattend exists
if ($Unattend -and $UnattendPrefix) {
    $registerAutopilotPath = Join-Path -Path $APFolder -ChildPath "Register-Autopilot.ps1"
    $autopilotContent = Get-Content -Path $registerAutopilotPath
    WriteLog 'Unattend file found with prefixes.txt. Getting prefixes.'
    $deploymentTeams = @{
        "1" = "Service Desk"
        "2" = "Field Services"
        "3" = "Griffin Campus"
    }
    do {
        Write-Host @"
Please select the deployment team:
====================================
[1] Service Desk
[2] Field Services
[3] Griffin Campus
====================================
"@
    $choice = Read-Host 'Enter the number corresponding to your choice'
        $deploymentTeam = $deploymentTeams[$choice]
        if (-not $deploymentTeam) {
            Write-Host "Invalid selection. Pick a number from the above." -ForegroundColor Red
        }
    } until ($deploymentTeam)
    do {
        $deploymentType = Read-Host 'Is this a shared device? [Y]es or [N]o'
    } until ($deploymentType -match '^[YyNn]$')
    $isSharedDevice = $deploymentType.ToUpperInvariant() -eq 'Y'
    if ($isSharedDevice) {
        do {
            $sharedDeviceType = Read-Host 'Is this an A/V or computer lab device? [Y]es or [N]o'
        } until ($sharedDeviceType -match '^[YyNn]$')
        if ($sharedDeviceType.ToUpperInvariant() -eq 'N') {
            Copy-Item -Path "$PPKGFolder\IntuneEnroll.ppkg.bak" -Destination "$USBDrive\IntuneEnroll.ppkg.bak"
            Rename-Item -Path "$USBDrive\IntuneEnroll.ppkg.bak" -NewName "IntuneEnroll.ppkg"
        }
    }
    if ($deploymentTeam -eq "Field Services") {
        do {
            $localAccount = Read-Host 'Do you want to create a local account? [Y]es or [N]o'
        } until ($localAccount -match '^[YyNn]$')
        if ($localAccount.ToUpperInvariant() -eq 'Y') {
            $username = Read-Host 'Type in the username'
            $password = Read-Host 'Type in the password'
            $SetupCompleteData += "`nnet user $username $password /add && net localgroup Administrators $username /add && wmic useraccount where name=`'$username`' set PasswordExpires=false"
        }
    }
    switch ($deploymentTeam) {
        "Service Desk" {
            $groupTag = if ($isSharedDevice) { "CAES-SHARED" } else { "CAESATH" }
            $registerAutopilot = !$isSharedDevice
            $autopilot = $false
        }
        "Field Services" {
            $groupTag = if ($isSharedDevice) { "CAES-SHARED" } else { "CAESFLD" }
            $registerAutopilot = !$isSharedDevice
            if ($registerAutopilot) {
                $autopilotContent = $autopilotContent -replace '\[bool\]\$Assign = \$true', "[bool]`$Assign = `$false"
            }
            $autopilot = $true
        }
        "Griffin Campus" {
            $registerAutopilot = $false
            $autopilot = $false
        }
    }
    if ($groupTag) {
        $autopilotContent = $autopilotContent -replace '\[string\]\$GroupTag,', "[string]`$GroupTag = `"$groupTag`","
    }
    if ($isSharedDevice -or $deploymentTeam -ne "Service Desk") {
        do {
            $computerName = Read-Host 'Type in the name of the computer'
            $computerName = $computerName -replace "\s", ""
            if ($computerName.Length -gt 15) {
                $SetupCompleteData += "`npowershell.exe -Command { Rename-Computer -NewName $computerName -Force }"
                $computerName = $computerName.Substring(0, 15)
            }
        } while (-not $computerName)
        $computerName = Set-Computername($computername)
        WriteLog "Computer name set to $computername"
    }
    else {
        $UnattendPrefixes = @(Get-content $UnattendPrefixFile)
        $UnattendPrefixCount = $UnattendPrefixes.Count
        if ($UnattendPrefixCount -gt 1) {
            WriteLog "Found $UnattendPrefixCount Prefixes"
            $array = @()
            for ($i = 0; $i -le $UnattendPrefixCount - 1; $i++) {
                $Properties = [ordered]@{Number = $i + 1 ; DeviceNamePrefix = $UnattendPrefixes[$i] }
                $array += New-Object PSObject -Property $Properties
            }
            $array | Format-Table -AutoSize -Property Number, DeviceNamePrefix
            do {
                try {
                    $var = $true
                    [int]$PrefixSelected = Read-Host 'Enter the prefix number to use for the device name'
                    $PrefixSelected = $PrefixSelected - 1
                }
                catch {
                    Write-Host 'Input was not in correct format. Please enter a valid prefix number'
                    $var = $false
                }
            } until (($PrefixSelected -le $UnattendPrefixCount - 1) -and $var) 
            $PrefixToUse = $array[$PrefixSelected].DeviceNamePrefix
            WriteLog "$PrefixToUse was selected"
        }
        elseif ($UnattendPrefixCount -eq 1) {
            WriteLog "Found $UnattendPrefixCount Prefix"
            $PrefixToUse = $UnattendPrefixes[0]
            WriteLog "Will use $PrefixToUse as device name prefix"
        }
        $serial = (Get-CimInstance -ClassName win32_bios).SerialNumber.Trim()
        $computername = ($PrefixToUse + $serial) -replace "\s", "" # Remove spaces because windows does not support spaces in the computer names
        #If computername is longer than 15 characters, reduce to 15. Sysprep/unattend doesn't like ComputerName being longer than 15 characters even though Windows accepts it
        if ($computername.Length -gt 15) {
            $SetupCompleteData += "`npowershell.exe -Command { Rename-Computer -NewName $computerName -Force }"
            $computername = $computername.substring(0, 15)
        }
        $computername = Set-Computername($computername)
        Writelog "Computer name set to $computername"
    }
}
elseif ($Unattend) {
    Writelog 'Unattend file found with no prefixes.txt, asking for name'
    [string]$computername = Read-Host 'Enter device name'
    Set-Computername($computername)
    Writelog "Computer name set to $computername"
}
else {
    WriteLog 'No unattend folder found. Device name will be set via PPKG, AP JSON, or default OS name.'
}
#If both AP and PPKG folder found with files, ask which to use.
if ($autopilot -eq $true -and $PPKG -eq $true) {
    WriteLog 'Both PPKG and Autopilot json files found'
    Write-Host 'Both Autopilot JSON files and Provisioning packages were found.'
    do {
        try {
            $var = $true
            [int]$APorPPKG = Read-Host 'Enter 1 for Autopilot or 2 for Provisioning Package'
        }
        catch {
            Write-Host 'Incorrect value. Please enter 1 for Autopilot or 2 for Provisioning Package'
            $var = $false
        }
    } until (($APorPPKG -gt 0 -and $APorPPKG -lt 3) -and $var)
    if ($APorPPKG -eq 1) {
        $PPKG = $false
    }
    else {
        $autopilot = $false
    } 
}
#If multiple AP json files found, ask which to install
if ($APFilesCount -gt 1 -and $autopilot -eq $true) {
    WriteLog "Found $APFilesCount Autopilot json Files"
    $array = @()
    for ($i = 0; $i -le $APFilesCount - 1; $i++) {
        $Properties = [ordered]@{Number = $i + 1 ; APFile = $APFiles[$i].FullName; APFileName = $APFiles[$i].Name }
        $array += New-Object PSObject -Property $Properties
    }
    $array | Format-Table -AutoSize -Property Number, APFileName
    do {
        try {
            $var = $true
            [int]$APFileSelected = Read-Host 'Enter the AP json file number to install'
            $APFileSelected = $APFileSelected - 1
        }
        catch {
            Write-Host 'Input was not in correct format. Please enter a valid AP json file number'
            $var = $false
        }
    } until (($APFileSelected -le $APFilesCount - 1) -and $var) 
    $APFileToInstall = $array[$APFileSelected].APFile
    $APFileName = $array[$APFileSelected].APFileName
    WriteLog "$APFileToInstall was selected"
}
elseif ($APFilesCount -eq 1 -and $autopilot -eq $true) {
    WriteLog "Found $APFilesCount AP File"
    $APFileToInstall = $APFiles[0].FullName
    $APFileName = $APFiles[0].Name
    WriteLog "$APFileToInstall will be copied"
}
else {
    Writelog 'No AP files found or AP was not selected'
}
#If multiple PPKG files found, ask which to install
if ($PPKGFilesCount -gt 1 -and $PPKG -eq $true) {
    WriteLog "Found $PPKGFilesCount PPKG Files"
    $array = @()
    for ($i = 0; $i -le $PPKGFilesCount - 1; $i++) {
        $Properties = [ordered]@{Number = $i + 1 ; PPKGFile = $PPKGFiles[$i].FullName; PPKGFileName = $PPKGFiles[$i].Name }
        $array += New-Object PSObject -Property $Properties
    }
    $array | Format-Table -AutoSize -Property Number, PPKGFileName
    do {
        try {
            $var = $true
            [int]$PPKGFileSelected = Read-Host 'Enter the PPKG file number to install'
            $PPKGFileSelected = $PPKGFileSelected - 1
        }
        catch {
            Write-Host 'Input was not in correct format. Please enter a valid PPKG file number'
            $var = $false
        }
    } until (($PPKGFileSelected -le $PPKGFilesCount - 1) -and $var) 
    $PPKGFileToInstall = $array[$PPKGFileSelected].PPKGFile
    WriteLog "$PPKGFileToInstall was selected"
}
elseif ($PPKGFilesCount -eq 1 -and $PPKG -eq $true) {
    WriteLog "Found $PPKGFilesCount PPKG File"
    $PPKGFileToInstall = $PPKGFiles[0].FullName
    WriteLog "$PPKGFileToInstall will be used"
}
else {
    Writelog 'No PPKG files found or PPKG not selected.'
}
$Drivers = $USBDrive + "Drivers"
if (Test-Path -Path $Drivers) {
    $DriverFolders = Get-ChildItem -Path $Drivers -directory
    $DriverFoldersCount = $DriverFolders.count
    if ($DriverFoldersCount -gt 1) {
        WriteLog "Found $DriverFoldersCount driver folders"
        $array = @()
        for ($i = 0; $i -le $DriverFoldersCount - 1; $i++) {
            $Properties = [ordered]@{Number = $i + 1; Drivers = $DriverFolders[$i].FullName }
            $array += New-Object PSObject -Property $Properties
        }
        $array | Format-Table -AutoSize -Property Number, Drivers
        do {
            try {
                $var = $true
                [int]$DriversSelected = Read-Host 'Enter the set of drivers to install'
                $DriversSelected = $DriversSelected - 1
            }
            catch {
                Write-Host 'Input was not in correct format. Please enter a valid driver folder number'
                $var = $false
            }
        } until (($DriversSelected -le $DriverFoldersCount - 1) -and $var) 
        $Drivers = $array[$DriversSelected].Drivers
        WriteLog "$Drivers was selected"
    }
    elseif ($DriverFoldersCount -eq 1) {
        WriteLog "Found $DriverFoldersCount driver folder"
        $Drivers = $DriverFolders.FullName
        WriteLog "$Drivers will be installed"
    }
    else {
        Writelog 'No driver folders found'
    }
}
$computerManufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
$model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
Write-Host "`nComputer manufacturer is $computerManufacturer" -ForegroundColor Yellow
Write-Host "Computer model is $model`n" -ForegroundColor Yellow
Optimize-BIOSSettings -ComputerManufacturer $computerManufacturer
Writelog 'Clean Disk'
Write-Host "`nCleaning disk" -ForegroundColor Yellow
try {
    $Disk = Get-Disk -Number $DiskID
    if ($Disk.PartitionStyle -ne "RAW") {
        $Disk | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
    }
}
catch {
    WriteLog 'Cleaning disk failed. Exiting'
    throw $_
}
Writelog 'Cleaning Disk succeeded'
Write-Host "Cleaning disk successful" -ForegroundColor Green
WriteLog "Applying FFU to $PhysicalDeviceID"
WriteLog "Running command dism /apply-ffu /ImageFile:$FFUFileToInstall /ApplyDrive:$PhysicalDeviceID"
Write-Host "`nRunning command DISM /Apply-FFU /ImageFile:$FFUFileToInstall /ApplyDrive:$PhysicalDeviceID" -ForegroundColor Yellow
#In order for Applying Image progress bar to show up, need to call dism directly. Might be a better way to handle, but must have progress bar show up on screen.
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
DISM /Apply-FFU /ImageFile:$FFUFileToInstall /ApplyDrive:$PhysicalDeviceID
$stopwatch.Stop()
$elapsedSeconds = $stopwatch.Elapsed.TotalSeconds
$minutes = [math]::Floor($elapsedSeconds / 60)
$seconds = [math]::Round($elapsedSeconds % 60, 2)
if ($elapsedSeconds -lt 60) {
    $formattedTime = "{0:N2} seconds" -f $elapsedSeconds
}
elseif ($minutes -eq 1) {
    $formattedTime = "{0} minute and {1} seconds" -f $minutes, $seconds
}
else {
    $formattedTime = "{0} minutes and {1} seconds" -f $minutes, $seconds
}
Write-Host "`nImage was applied in $formattedTime." -ForegroundColor Green
Write-Host "`nSetting GPT attributes to recovery partition" -ForegroundColor Yellow
$recoveryPartition = Get-Partition -Disk $Disk | Where-Object PartitionNumber -eq 4
if ($recoveryPartition) {
    WriteLog 'Setting recovery partition attributes'
    $diskpartScript = @(
        "SELECT DISK $($Disk.Number)", 
        "SELECT PARTITION $($recoveryPartition.PartitionNumber)", 
        "GPT ATTRIBUTES=0x8000000000000001", 
        "EXIT"
    )
    $diskpartScript | diskpart.exe | Out-Null
    WriteLog 'Setting recovery partition attributes complete'
    Write-Host "GPT attributes applied to recovery partition" -ForegroundColor Green
}
if ($LASTEXITCODE -eq 0) {
    WriteLog 'Successfully applied FFU'
}
elseif ($LASTEXITCODE -eq 1393) {
    WriteLog "Failed to apply FFU - LastExitCode = $LastExitCode"
    WriteLog "This is likely due to a mismatched LogicalSectorByteSize"
    WriteLog "BytesPerSector value from Win32_Diskdrive is $BytesPerSector"
    if ($BytesPerSector -eq 4096) {
        WriteLog "The FFU build process by default uses a 512 LogicalSectorByteSize. Rebuild the FFU by adding -LogicalSectorByteSize 4096 to the command line"
    }
    elseif ($BytesPerSector -eq 512) {
        WriteLog "This FFU was likely built with a LogicalSectorByteSize of 4096. Rebuild the FFU by adding -LogicalSectorByteSize 512 to the command line"
    }
    Invoke-Process xcopy.exe "X:\Windows\logs\dism\dism.log $USBDrive /Y"
    exit
}
else {
    Writelog "Failed to apply FFU - LastExitCode = $LASTEXITCODE also check dism.log on the USB drive for more info"
    Invoke-Process xcopy.exe "X:\Windows\logs\dism\dism.log $USBDrive /Y"
    exit
}
Get-Disk | Where-Object Number -eq $DiskID | Get-Partition | Where-Object PartitionNumber -eq 3 | Set-Partition -NewDriveLetter W
#Copy modified WinRE if folder exists, else copy inbox WinRE
$WinRE = $USBDrive + "WinRE\winre.wim"
if (Test-Path -Path $WinRE) {
    WriteLog 'Copying modified WinRE to Recovery directory'
    Get-Disk | Where-Object Number -eq $DiskID | Get-Partition | Where-Object Type -eq Recovery | Set-Partition -NewDriveLetter R
    Invoke-Process xcopy.exe "/h $WinRE R:\Recovery\WindowsRE\ /Y"
    WriteLog 'Copying WinRE to Recovery directory succeeded'
    WriteLog 'Registering location of recovery tools'
    Invoke-Process W:\Windows\System32\Reagentc.exe "/Setreimage /Path R:\Recovery\WindowsRE /Target W:\Windows"
    Get-Disk | Where-Object Number -eq $DiskID | Get-Partition | Where-Object Type -eq Recovery | Remove-PartitionAccessPath -AccessPath R:
    WriteLog 'Registering location of recovery tools succeeded'
}
#Autopilot JSON
if ($APFileToInstall) {
    WriteLog "Copying $APFileToInstall to W:\windows\provisioning\autopilot"
    Invoke-process xcopy.exe "$APFileToInstall W:\Windows\provisioning\autopilot\"
    WriteLog "Copying $APFileToInstall to W:\windows\provisioning\autopilot succeeded"
    try {
        Rename-Item -Path "W:\Windows\Provisioning\Autopilot\$APFileName" -NewName 'W:\Windows\Provisioning\Autopilot\AutoPilotConfigurationFile.json'
        WriteLog "Renamed W:\Windows\Provisioning\Autopilot\$APFilename to W:\Windows\Provisioning\Autopilot\AutoPilotConfigurationFile.json"
    }
    catch {
        Writelog "Copying $APFileToInstall to W:\windows\provisioning\autopilot failed with error: $_"
        throw $_
    }
}
#Apply PPKG
if ($PPKGFileToInstall) {
    try {
        #Make sure to delete any existing PPKG on the USB drive
        Get-Childitem -Path $USBDrive\*.ppkg | ForEach-Object {
            Remove-item -Path $_.FullName
        }
        WriteLog "Copying $PPKGFileToInstall to $USBDrive"
        Invoke-process xcopy.exe "$PPKGFileToInstall $USBDrive"
        WriteLog "Copying $PPKGFileToInstall to $USBDrive succeeded"
    }
    catch {
        Writelog "Copying $PPKGFileToInstall to $USBDrive failed with error: $_"
        throw $_
    }
}
#Set DeviceName
if ($computername) {
    try {
        $PantherDir = 'w:\windows\panther'
        if (Test-Path -Path $PantherDir) {
            Writelog "Copying $UnattendFile to $PantherDir"
            Invoke-process xcopy "$UnattendFile $PantherDir /Y"
            WriteLog "Copying $UnattendFile to $PantherDir succeeded"
        }
        else {
            Writelog "$PantherDir doesn't exist, creating it"
            New-Item -Path $PantherDir -ItemType Directory -Force
            Writelog "Copying $UnattendFile to $PantherDir"
            Invoke-Process xcopy.exe "$UnattendFile $PantherDir"
            WriteLog "Copying $UnattendFile to $PantherDir succeeded"
        }
    }
    catch {
        WriteLog "Copying Unattend.xml to name device failed"
        throw $_
    }   
}
# Apply PPKG
$provisioningFolder = Join-Path -Path $USBDrive -ChildPath "Provisioning"
if (Test-Path -Path $provisioningFolder -PathType Container) {
    if ((Get-ChildItem -Path $provisioningFolder | Measure-Object).Count -gt 0) {
        $provisioningPackages = Get-ChildItem -Path $provisioningFolder -Filter "*.ppkg"
        if ($provisioningPackages) {
            foreach ($provisioningPackage in $provisioningPackages) {
                Start-Process -FilePath dism.exe -ArgumentList "/Image=W:\ /Add-ProvisioningPackage /PackagePath:$($provisioningPackage.FullName)" -Wait -NoNewWindow
            }
        }
    }
}
#Add Drivers
Install-Drivers -ComputerManufacturer $ComputerManufacturer -Model $Model -MountPath "W:\"
if ((Test-Path -Path $Drivers -PathType Container) -and ($deploymentTeam -ne "Field Services")) {
    Remove-Item -Path $Drivers -Recurse -Force
}
if ($registerAutopilot) {
    $autopilotexe = Join-Path -Path $APFolder -ChildPath "Autopilot.exe"
    $autopilotGroupMapping = Join-Path -Path $APFolder -ChildPath "AutopilotGroupMapping.json"
    $autopilotCleanup = Join-Path -Path $APFolder -ChildPath "Start-CleanupAndSysprep.ps1"
    $autopilotFiles = @(
        $autopilotexe,
        $autopilotGroupMapping,
        $autopilotCleanup
    )
    if (-not (Test-Path -Path "W:\Autopilot" -PathType Container)) {
        New-Item -Path "W:\Autopilot" -ItemType Directory -Force | Out-Null
    }
    foreach ($file in $autopilotFiles) {
        if (-not (Test-Path -Path $file -PathType Leaf)) {
            throw "$file not found"
        }
        Copy-Item -Path $file -Destination "W:\Autopilot" -Force
    }
    $autopilotContent | Set-Content -Path "W:\Autopilot\Register-Autopilot.ps1"
    $SetupCompleteData += "`npowershell.exe -command Start-Process -FilePath C:\Autopilot\Autopilot.exe"
}
New-Item -Path "W:\Windows\Setup\Scripts" -ItemType Directory -Force | Out-Null
Set-Content -Path "W:\Windows\Setup\Scripts\SetupComplete.cmd" -Value $SetupCompleteData -Force
WriteLog "Copying dism log to $LogFileDir"
Invoke-Process xcopy "X:\Windows\logs\dism\dism.log $LogFileDir /Y" 
WriteLog "Copying dism log to $LogFileDir succeeded"
if (Test-Path -Path "X:\Flash64W.log" -PathType Leaf) {
    WriteLog "Copying Flash64W log to $LogFileDir"
    Invoke-Process xcopy "x:\Flash64W.log $LogFileDir /Y"
    WriteLog "Copying Flash64W log to $LogFileDir succeeeded"
}
WriteLog "Setting Windows Boot Manager to be first in the display order"
Write-Host "Setting Windows Boot Manager to be first in the display order" -ForegroundColor Yellow
Invoke-Process bcdedit.exe "/set {fwbootmgr} displayorder {bootmgr} /addfirst"
WriteLog "Setting default Windows boot loader to be first in the display order"
Write-Host "Setting default Windows boot loader to be first in the display order" -ForegroundColor Yellow
Invoke-Process bcdedit.exe "/set {bootmgr} displayorder {default} /addfirst"
Restart-Computer -Force
