function Remove-UWPApps {
    $inboxApps = ".\InboxApps.json"
    if (-not (Test-Path -Path $InboxApps -PathType Leaf)) {
        return
    }
    $provisionedAppPackageNames = Get-Content -Path $inboxApps | ConvertFrom-Json
    $provisionedStoreApps = (Get-AppXProvisionedPackage -Online).DisplayName
    try {
        foreach ($provisionedAppName in $provisionedAppPackageNames) {
            if($provisionedAppName -in $provisionedStoreApps) {
                Get-AppxPackage -Name $provisionedAppName -AllUsers | Remove-AppxPackage -AllUsers
                Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $provisionedAppName | Remove-AppxProvisionedPackage -Online -AllUsers
            }
        }
    } catch {
        throw $_
    }
}

function Copy-CustomizationFile {
    param (
        [string]$SourcePath,
        [string]$DestinationPath
    )
    if (-not (Test-Path $DestinationPath -PathType Container)) {
        New-Item -Path $DestinationPath -ItemType Directory -Force
    }
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
}

function Set-RegistrySetting {
    param (
        $RegPath,
        $RegValueName,
        $RegValueType,
        $RegValueData
    )
    if (-not (Test-Path -Path $RegPath)) {
        New-Item -Path $RegPath -Force
    }
    New-ItemProperty -Path $RegPath -Name $RegValueName -Value $RegValueData -PropertyType $RegValueType -Force
}

function Set-PolicySettings {
    param (
        [string]$SettingsFile
    )
    $settings = Get-Content -Path $SettingsFile | ConvertFrom-Json
    foreach ($setting in $settings.RegistrySettings) {
        Set-RegistrySetting -RegPath $setting.RegPath -RegValueName $setting.RegValueName -RegValueType $setting.RegValueType -RegValueData $setting.RegValueData
    }
}

function Set-SecurityBaselines {
    param (
        [string]$CustomizationsFolder
    )
    try {
        $policyDefinitionsPath = "$env:windir\PolicyDefinitions"
        $policyLanguagePath = "$policyDefinitionsPath\en-US"
        Get-ChildItem -Path "$CustomizationsFolder\GPOs\*.admx" -Recurse -Force -ErrorAction SilentlyContinue | 
            ForEach-Object { Copy-CustomizationFile -SourcePath $_.FullName -DestinationPath $policyDefinitionsPath }
        Get-ChildItem -Path "$CustomizationsFolder\GPOs\*.adml" -Recurse -Force -ErrorAction SilentlyContinue | 
            ForEach-Object { Copy-CustomizationFile -SourcePath $_.FullName -DestinationPath $policyLanguagePath }
        $LGPO = "$CustomizationsFolder\GPOS\LGPO.exe"
        if (Test-Path -Path $LGPO -PathType Leaf) {
            Get-ChildItem -Path "$CustomizationsFolder\GPOs\*.txt" -Recurse -Force -ErrorAction SilentlyContinue | 
                ForEach-Object { Start-Process -FilePath $LGPO -ArgumentList "/t ""$($_.FullName)"" /v" -Wait -NoNewWindow }
            Get-ChildItem -Path "$CustomizationsFolder\GPOs\*.inf" -Recurse -Force -ErrorAction SilentlyContinue | 
                ForEach-Object { Start-Process -FilePath $LGPO -ArgumentList "/s ""$($_.FullName)"" /v" -Wait -NoNewWindow }
        }
        Get-ChildItem -Path "$CustomizationsFolder\GPOs\*.csv" -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Start-Process -FilePath "$env:windir\system32\auditpol.exe" -ArgumentList "/restore /file:""$($_.FullName)""" -Wait -NoNewWindow }
    }
    catch {
        Write-Error "Error processing security baselines: $_"
    }
}

function Build-InternetShortcut {
    param (
        [string]$Url,
        [string]$IconFile
    )
    $shortcutContent = "[InternetShortcut]`n"
    $shortcutContent += "URL=`"$Url`"`n"
    $shortcutContent += "IconFile=`"$IconFile`"`n"
    $shortcutContent += "IconIndex=0"
    return $shortcutContent
}

function Set-PublicDesktopContents {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigFilePath
    )
    $config = Get-Content -Path $configFilePath | ConvertFrom-Json
    $publicDesktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")
    Get-ChildItem -Path $publicDesktopPath -File | Remove-Item -Force
    foreach ($desktopApp in $config.desktopApps) {
        if (Test-Path -Path $desktopApp.source -PathType Leaf) {
            Copy-Item -Path $desktopApp.source -Destination $publicDesktopPath -Force
        }
    }
    foreach ($icon in $config.icons) {
        Copy-CustomizationFile -SourcePath $icon.source -DestinationPath $icon.destination
    }
    foreach ($shortcut in $config.shortcuts) {
        $shortcutContent = Build-InternetShortcut -Url $shortcut.url -IconFile $shortcut.icon
        $shortcutPath = Join-Path -Path $publicDesktopPath -ChildPath $shortcut.name
        Set-Content -Path $shortcutPath -Value $shortcutContent
    }
}

function Add-LocalGroupMembers {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigFilePath
    )
    $config = Get-Content -Path $configFilePath | ConvertFrom-Json
    foreach ($group in $config.LocalGroups) {
        $groupName = $group.GroupName
        $members = $group.Members
        foreach ($member in $members) {
            try {
                Add-LocalGroupMember -Group $groupName -Member $member
                Write-Host "Successfully added $member to $groupName"
            } catch {
                Write-Host "Failed to add $member to $groupName $_"
            }
        }
    }
}

$customizationsFolder = "D:\Customizations"
Remove-UWPApps
Copy-CustomizationFile -SourcePath "$customizationsFolder\Branding\lockscreen.jpg" -DestinationPath "$env:windir\Web\Screen"
# https://learn.microsoft.com/en-us/windows/win32/controls/themesfileformat-overview
# https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/set-dark-mode
Copy-CustomizationFile -SourcePath "$customizationsFolder\Branding\oem.theme" -DestinationPath "C:\Users\Default\AppData\Local\Microsoft\Windows\Themes"
Set-PolicySettings -SettingsFile "$customizationsFolder\RegistrySettings.json"
Set-SecurityBaselines -CustomizationsFolder $customizationsFolder
Add-LocalGroupMembers -ConfigFilePath "$customizationsFolder\LocalGroupMembers.json"
Set-PublicDesktopContents -ConfigFilePath "$customizationsFolder\PublicDesktop.json"
@(
    "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate",
    "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate"
) | Where-Object { Test-Path $_ } | ForEach-Object { Remove-Item -Path $_ -Force }
DISM /Online /Import-DefaultAppAssociations:"""$customizationsFolder\DefaultAppAssociations.xml"""
$provisioningPackages = Get-ChildItem -Path $customizationsFolder -Filter "*.ppkg"
if ($provisioningPackages) {
    foreach ($provisioningPackage in $provisioningPackages) {
        DISM /Online /Add-ProvisioningPackage /PackagePath:"""$($provisioningPackage.FullName)"""
    }
}
