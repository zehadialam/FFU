function Remove-UWPApps {
    $provisionedAppPackageNames = @(
        "Clipchamp.Clipchamp",
        "Microsoft.549981C3F5F10",
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.GamingApp",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.Microsoft3DViewer",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MixedReality.Portal",
        "Microsoft.People",
        "Microsoft.PowerAutomateDesktop",
        "Microsoft.Todos",
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
        New-Item -Path $DestinationPath -ItemType Directory
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
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Zoom\Zoom Workplace.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Cisco\Cisco AnyConnect Secure Mobility Client\Cisco AnyConnect Secure Mobility Client.lnk"
    )
    foreach ($desktopApp in $publicDesktopApps) {
        Copy-Item -Path $desktopApp -Destination $publicDesktopPath -Force
    }
    Copy-CustomizationFile -SourcePath "$customizationsFolder\ITSupport.ico" -DestinationPath "$env:windir\System32"
    $requestITSupportShortcut = Build-InternetShortcut -Url "https://uga.teamdynamix.com/TDClient/2060/Portal/Requests/ServiceCatalog?CategoryID=3478" -IconFile "$env:windir\System32\ITsupport.ico"
    $requestITSupportShortcutPath = Join-Path -Path $publicDesktopPath -ChildPath "Request IT Support.url"
    Set-Content -Path $requestITSupportShortcutPath -Value $requestITSupportShortcut
    Copy-CustomizationFile -SourcePath "$customizationsFolder\UGA.ico" -DestinationPath "$env:windir\System32"
    $eitsKBShortcut = Build-InternetShortcut -Url "https://uga.teamdynamix.com/TDClient/3190/eitsclientportal/KB/" -IconFile "$env:windir\System32\UGA.ico"
    $eitsKBShortcutPath = Join-Path -Path $publicDesktopPath -ChildPath "EITS Knowledgebase.url"
    Set-Content -Path $eitsKBShortcutPath -Value $eitsKBShortcut
}

$customizationsFolder = "D:\Customizations"
Remove-UWPApps
# Customize taskbar: 
# https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps?tabs=intune&pivots=windows-11
# https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-the-windows-11-taskbar
Copy-CustomizationFile -SourcePath "$customizationsFolder\taskbarlayout.xml" -DestinationPath "$env:windir\ITAdmin"
# Copy lock screen background
Copy-CustomizationFile -SourcePath "$customizationsFolder\lockscreen.jpg" -DestinationPath "$env:windir\Web\Screen"
# Copy theme file to "C:\Users\Default\AppData\Local\Microsoft\Windows\Themes"
# https://learn.microsoft.com/en-us/windows/win32/controls/themesfileformat-overview
# https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/set-dark-mode
Copy-CustomizationFile -SourcePath "$customizationsFolder\oem.theme" -DestinationPath "C:\Users\Default\AppData\Local\Microsoft\Windows\Themes"
Set-PolicySettings -SettingsFile "D:\Customizations\RegistrySettings.json"
Set-PublicDesktopContents