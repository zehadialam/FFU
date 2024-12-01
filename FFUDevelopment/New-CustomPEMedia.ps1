#region Variables
$scriptRoot = $PSScriptRoot
$winpeRoot = Join-Path -Path $scriptRoot -ChildPath "WinPE-Root"
$winpePaths = @{
    Apps     = Join-Path -Path $scriptRoot -ChildPath "PEResources\WinPE-Apps"
    Drivers  = Join-Path -Path $scriptRoot -ChildPath "PEDrivers"
    Wallpaper= Join-Path -Path $scriptRoot -ChildPath "PEResources\WinPE-Wallpaper"
}
$adkPath = "$env:ProgramFiles (x86)\Windows Kits\10\Assessment and Deployment Kit"
$dandIEnv = Join-Path -Path $adkPath -ChildPath "Deployment Tools\DandISetEnv.bat"
$winpeOCPath = Join-Path -Path $adkPath -ChildPath "Windows Preinstallation Environment\amd64\WinPE_OCs"
$bootwim = Join-Path -Path $winpeRoot -ChildPath "media\sources\boot.wim"
$mountPath = Join-Path -Path $winpeRoot -ChildPath "mount"
$psModulesPath = Join-Path -Path $mountPath -ChildPath "Program Files\WindowsPowerShell\Modules"
$system32Path = Join-Path -Path $mountPath -ChildPath "Windows\system32"
$repairPath = Join-Path -Path $scriptRoot -ChildPath "repair.txt"
#endregion

function Remove-DirectoryContents {
    param (
        [string]$Path
    )
    if (Test-Path -Path $Path -PathType Container) {
        Get-ChildItem -Path $Path -Exclude ".gitkeep" -Recurse -Force | ForEach-Object {
            if ($_.PSIsContainer) {
                Remove-Item -Path $_.FullName -Recurse -Force -Confirm:$false
            } else {
                Remove-Item -Path $_.FullName -Force -Confirm:$false
            }
        }        
    }
}

function Add-Packages {
    param (
        [string]$MountPath,
        [string]$OCPath,
        [array]$Packages
    )
    foreach ($package in $Packages) {
        $packagePath = Join-Path -Path $OCPath -ChildPath $package
        Add-WindowsPackage -Path $MountPath -PackagePath $packagePath | Out-Null
    }
}

function Install-OSDModule {
    if (-not (Get-Module -ListAvailable -Name OSD)) {
        Install-Module -Name OSD -Force -Confirm:$false
    }
    Import-Module OSD
}

function Get-WinPEDriverPack {
    param (
        [string]$DestinationPath
    )
    $driverPackUrl = Get-DellWinPEDriverPack
    Start-BitsTransfer -Source $driverPackUrl -Destination $DestinationPath
    $driverPack = Get-ChildItem -Path $DestinationPath -Filter "*.cab" -File
    Start-Process -FilePath expand.exe -ArgumentList "-f:* ""$($driverPack.FullName)"" ""$DestinationPath""" -Wait -NoNewWindow
}

function Set-WinPEWallpaper {
    param (
        [string]$SourcePath,
        [string]$DestinationPath
    )
    if (Test-Path -Path $SourcePath -PathType Container) {
        $wallpaperFile = Get-ChildItem -Path $SourcePath -Filter "winpe.jpg" -File
        if ($wallpaperFile) {
            $defaultWallpaper = Join-Path -Path $DestinationPath -ChildPath "winpe.jpg"
            Start-Process -FilePath takeown.exe -ArgumentList "/f ""$defaultWallpaper""" -Wait -NoNewWindow
            Start-Process -FilePath icacls.exe -ArgumentList """$defaultWallpaper"" /grant administrators:F" -Wait -NoNewWindow
            Copy-Item -Path $wallpaperFile.FullName -Destination $DestinationPath -Force
        }
    }
}

function Add-WinPEApps {
    param (
        [string]$SourcePath,
        [string]$DestinationPath
    )
    $psexec64Path = Join-Path -Path $SourcePath -ChildPath "PsExec64.exe"
    Start-BitsTransfer -Source "https://live.sysinternals.com/PsExec64.exe" -Destination $psexec64Path
    Copy-Item -Path $psexec64Path -Destination $DestinationPath -Force
    $curlArchivePath = Join-Path -Path $SourcePath -ChildPath "curl.zip"
    $curlExtractPath = Join-Path -Path $SourcePath -ChildPath "curl"
    Start-BitsTransfer -Source "https://curl.se/windows/latest.cgi?p=win64-mingw.zip" -Destination $curlArchivePath
    Expand-Archive -Path $curlArchivePath -DestinationPath $curlExtractPath -Force
    $curlBinPath = Get-ChildItem -Path $winpePaths.Apps -Filter "bin" -Recurse -Directory | Select-Object -ExpandProperty FullName
    $curlWinPEPath = Join-Path -Path $DestinationPath -ChildPath "curl"
    New-Item -Path $curlWinPEPath -ItemType Directory -Force | Out-Null
    Copy-Item -Path $curlBinPath -Destination $curlWinPEPath -Recurse -Force
}

function Add-PSModules {
    param (
        [string]$SourcePath,
        [string]$DestinationPath
    )
    if (-not (Get-Module -ListAvailable -Name DellBIOSProvider)) {
        Install-Module -Name DellBIOSProvider -Force -Confirm:$false
    }
    $dellBIOSProviderPath = Join-Path $SourcePath -ChildPath "DellBIOSProvider"
    $dellBIOSProviderDirectory = Get-ChildItem -Path $dellBIOSProviderPath -Directory
    $dellBIOSProviderLatestDirectory = $dellBIOSProviderDirectory | Sort-Object CreationTime -Descending | Select-Object -First 1
    New-Item -Path $DestinationPath -Name "DellBIOSProvider" -ItemType Directory -Force | Out-Null
    Copy-Item -Path "$dellBIOSProviderPath\$dellBIOSProviderLatestDirectory" -Destination "$DestinationPath\DellBIOSProvider" -Recurse -Force
    # https://www.dell.com/support/kbdoc/en-us/000146531/installing-the-dell-smbios-powershell-provider-in-windows-pe
    $dellBIOSProviderWinPEDependencies = @(
        "$env:windir\System32\msvcp140.dll",
        "$env:windir\System32\vcruntime140.dll",
        "$env:windir\System32\vcruntime140_1.dll"
    )
    $dellBIOSProviderWinPEPath = Join-Path -Path $DestinationPath -ChildPath "DellBIOSProvider\$dellBIOSProviderLatestDirectory"
    foreach ($dependency in $dellBIOSProviderWinPEDependencies) {
        Copy-Item -Path $dependency -Destination $dellBIOSProviderWinPEPath -Force
    }
    $osdPath = Join-Path $SourcePath -ChildPath "OSD"
    Copy-Item -Path $osdPath -Destination $DestinationPath -Recurse -Force
}

function Remove-ResidualFiles {
    if (Test-Path -Path $winpeRoot -PathType Container) {
        Remove-Item -Path $winpeRoot -Recurse -Force
    }
    Remove-DirectoryContents -Path $winpePaths.Apps
    Remove-DirectoryContents -Path $winpePaths.Drivers
    Remove-Item -Path $repairPath -Force
}

function Repair-Environment {
    if (-not (Test-Path -Path $repairPath -PathType Leaf)) {
        return
    }
    cmd.exe /c mountvol /r
    Get-WindowsImage -Mounted | ForEach-Object {
        Dismount-WindowsImage -Path $_.Path -Discard | Out-Null
    }    
    Clear-WindowsCorruptMountPoint | Out-Null
    Remove-ResidualFiles
}

Repair-Environment

New-Item -Path $scriptRoot -Name "repair.txt" -ItemType File -Force | Out-Null

# Create WinPE directory structure
cmd.exe /c """$dandIEnv"" && copype amd64 ""$winpeRoot""" | Out-Null

Mount-WindowsImage -ImagePath $bootwim -Index 1 -Path $mountPath -CheckIntegrity | Out-Null

$packages = @(
    "WinPE-HTA.cab",
    "en-us\WinPE-HTA_en-us.cab",
    "WinPE-WMI.cab",
    "en-us\WinPE-WMI_en-us.cab",
    "WinPE-StorageWMI.cab",
    "en-us\WinPE-StorageWMI_en-us.cab",
    "WinPE-Scripting.cab",
    "en-us\WinPE-Scripting_en-us.cab",
    "WinPE-NetFx.cab",
    "en-us\WinPE-NetFx_en-us.cab",
    "WinPE-PowerShell.cab",
    "en-us\WinPE-PowerShell_en-us.cab",
    "WinPE-DismCmdlets.cab",
    "en-us\WinPE-DismCmdlets_en-us.cab",
    "WinPE-FMAPI.cab",
    "WinPE-SecureBootCmdlets.cab",
    "WinPE-EnhancedStorage.cab",
    "en-us\WinPE-EnhancedStorage_en-us.cab",
    "WinPE-SecureStartup.cab",
    "en-us\WinPE-SecureStartup_en-us.cab"
)

Add-Packages -MountPath $mountPath -OCPath $winpeOCPath -Packages $packages
Install-OSDModule
Get-WinPEDriverPack -DestinationPath $winpePaths.Drivers
Add-WindowsDriver -Path $mountPath -Driver $winpePaths.Drivers -Recurse -Verbose | Out-Null
Set-WinPEWallpaper -SourcePath $winpePaths.Wallpaper -DestinationPath $system32Path
Add-WinPEApps -SourcePath $winpePaths.Apps -DestinationPath $system32Path
Add-PSModules -SourcePath (Join-Path -Path $env:ProgramFiles -ChildPath "WindowsPowerShell\Modules") -DestinationPath $psModulesPath
Dismount-WindowsImage -Path $mountPath -Save -CheckIntegrity | Out-Null

$winpeISOPath = Join-Path -Path $scriptRoot -ChildPath "WinPE.iso"

if (Test-Path -Path $winpeISOPath -PathType Leaf) {
    Remove-Item -Path $winpeISOPath -Force
}

cmd.exe /c """$dandIEnv"" && Makewinpemedia /iso ""$winpeRoot"" ""$winpeISOPath""" | Out-Null
Remove-ResidualFiles
