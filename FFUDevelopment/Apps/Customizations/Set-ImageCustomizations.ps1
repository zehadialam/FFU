function Remove-UWPApps {
    $provisionedAppPackageNames = @(
        "Clipchamp.Clipchamp",
        "Microsoft.549981C3F5F10",
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.Copilot",
        "Microsoft.GamingApp",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.Microsoft3DViewer",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MicrosoftStickyNotes",
        "Microsoft.MixedReality.Portal",
        "Microsoft.OutlookForWindows"
        "Microsoft.People",
        "Microsoft.PowerAutomateDesktop",
        "Microsoft.Todos",
        "Microsoft.Windows.DevHome",
        "Microsoft.WindowsAlarms",
        "microsoft.windowscommunicationsapps",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.WindowsMaps",
        "Microsoft.WindowsSoundRecorder",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxGameOverlay",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxIdentityProvider",
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.YourPhone",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "MicrosoftCorporationII.QuickAssist"
    )
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
    $publicDesktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")
    Get-ChildItem -Path $publicDesktopPath -File | Remove-Item -Force
    $publicDesktopApps = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Firefox.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Zoom\Zoom Workplace.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Cisco\Cisco AnyConnect Secure Mobility Client\Cisco AnyConnect Secure Mobility Client.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Foxit PDF Editor\Foxit PDF Editor.lnk",
        "$env:windir\agdb\Data Transfer.lnk"
    )
    foreach ($desktopApp in $publicDesktopApps) {
        if (Test-Path -Path $desktopApp -PathType Leaf) {
            Copy-Item -Path $desktopApp -Destination $publicDesktopPath -Force
        }
    }
    Copy-CustomizationFile -SourcePath "$customizationsFolder\ITSupport.ico" -DestinationPath "$env:windir\System32"
    $requestITSupportShortcut = Build-InternetShortcut -Url "https://uga.teamdynamix.com/TDClient/3159/KB/Requests/ServiceCatalog" -IconFile "$env:windir\System32\ITsupport.ico"
    $requestITSupportShortcutPath = Join-Path -Path $publicDesktopPath -ChildPath "Request IT Support.url"
    Set-Content -Path $requestITSupportShortcutPath -Value $requestITSupportShortcut
    Copy-CustomizationFile -SourcePath "$customizationsFolder\UGA.ico" -DestinationPath "$env:windir\System32"
    $eitsKBShortcut = Build-InternetShortcut -Url "https://uga.teamdynamix.com/TDClient/3190/eitsclientportal/KB/" -IconFile "$env:windir\System32\UGA.ico"
    $eitsKBShortcutPath = Join-Path -Path $publicDesktopPath -ChildPath "EITS Knowledgebase.url"
    Set-Content -Path $eitsKBShortcutPath -Value $eitsKBShortcut
}

$customizationsFolder = "D:\Customizations"
Remove-UWPApps
Copy-CustomizationFile -SourcePath "$customizationsFolder\lockscreen.jpg" -DestinationPath "$env:windir\Web\Screen"
# https://learn.microsoft.com/en-us/windows/win32/controls/themesfileformat-overview
# https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/set-dark-mode
Copy-CustomizationFile -SourcePath "$customizationsFolder\oem.theme" -DestinationPath "C:\Users\Default\AppData\Local\Microsoft\Windows\Themes"
Set-PolicySettings -SettingsFile "$customizationsFolder\RegistrySettings.json"
Set-SecurityBaselines -CustomizationsFolder $customizationsFolder
@(
    "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate",
    "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate"
) | Where-Object { Test-Path $_ } | ForEach-Object { Remove-Item -Path $_ -Force }
Add-LocalGroupMember -Group "Administrators" -Member "S-1-12-1-3698080277-1147366962-2456473244-1386568132"
DISM /Online /Import-DefaultAppAssociations:"""$customizationsFolder\DefaultAppAssociations.xml"""
Set-PublicDesktopContents
