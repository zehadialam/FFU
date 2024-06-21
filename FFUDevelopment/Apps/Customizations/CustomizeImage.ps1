function Set-RegistrySetting {
    param (
        $RegPath,
        $RegValueName,
        $RegValueType,
        $RegValueData
    )
    if (-not (Test-Path -Path $RegPath)) {
        $RegPathModified = $RegPath.Replace(":", "")
        New-Item -Path Registry::$RegPathModified
    }
    New-ItemProperty -Path $RegPath -Name $RegValueName -PropertyType $RegValueType -Value $RegValueData
}

try {
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
    foreach ($provisionedAppName in $provisionedAppPackageNames) {
        if($provisionedAppName -in $provisionedStoreApps) {
            Get-AppxPackage -Name $provisionedAppName -AllUsers | Remove-AppxPackage -AllUsers
            Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $provisionedAppName | Remove-AppxProvisionedPackage -Online -AllUsers
        }
    }
} catch {
    throw $_
}

# Customize taskbar
Import-StartLayout -LayoutPath "D:\Customizations\taskbar.xml" -MountPath "C:\"

# Copy lock screen background
Copy-Item -Path "D:\Customizations\lockscreen.jpg" -Destination "C:\Windows\Web\Screen" -Force

# Enable periodic registry backups
Set-RegistrySetting -RegPath "HKLM:\System\CurrentControlSet\Control\Session Manager\Configuration Manager" -RegValueName "EnablePeriodicBackup" -RegValueType DWORD -RegValueData 1
# Configures the Chat icon on the taskbar
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Windows\Windows Chat" -RegValueName "ChatIcon" -RegValueType DWORD -RegValueData 3
# Disable widgets
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Dsh" -RegValueName "AllowNewsAndInterests" -RegValueType DWORD -RegValueData 0
# Do not show Windows tips
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -RegValueName "DisableSoftLanding" -RegValueType DWORD -RegValueData 1
# Turn off cloud consumer account state content
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -RegValueName "DisableConsumerAccountStateContent" -RegValueType DWORD -RegValueData 1
# Turn off Microsoft consumer experiences
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -RegValueName "DisableWindowsConsumerFeatures" -RegValueType DWORD -RegValueData 1
# Set lock screen
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -RegValueName "LockScreenImage" -RegValueType String -RegValueData "C:\Windows\Web\Screen\lockscreen.jpg"
# Allow changing lock screen and logon image
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -RegValueName "NoChangingLockScreen" -RegValueType DWORD -RegValueData 0
# Turn off fun facts, tips, tricks, and more on lock screen
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -RegValueName "LockScreenOverlaysDisabled" -RegValueType DWORD -RegValueData 1
# Use Windows Hello for Business
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\PassportForWork" -RegValueName "Enabled" -RegValueType DWORD -RegValueData 1
# Do not start Windows Hello provisioning after sign-in
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\PassportForWork" -RegValueName "DisablePostLogonProvisioning" -RegValueType DWORD -RegValueData 1
# Require a password when a computer wakes (plugged in)
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51" -RegValueName "ACSettingIndex" -RegValueType DWORD -RegValueData 1
# Require a Password When a Computer Wakes (On Battery)
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51" -RegValueName "DCSettingIndex" -RegValueType DWORD -RegValueData 1
# Turn off the display (plugged in)
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Power\PowerSettings\3C0BC021-C8A8-4E07-A973-6B14CBCB2B7E" -RegValueName "ACSettingIndex" -RegValueType DWORD -RegValueData 0
# Specify the system sleep timeout (plugged in)
Set-RegistrySetting -RegPath "HKLM:\Software\Policies\Microsoft\Power\PowerSettings\29F6C1DB-86DA-48C5-9FDB-F2B67B1F44DA" -RegValueName "ACSettingIndex" -RegValueType DWORD -RegValueData 0

# Copy theme file to "C:\Users\Default\AppData\Local\Microsoft\Windows\Themes"
$themesFolder = "C:\Users\Default\AppData\Local\Microsoft\Windows\Themes"
if (-not (Test-Path $themesFolder -PathType Container)) {
    New-Item -Path $themesFolder -ItemType Directory
    Copy-Item -Path "D:\Customizations\oem.theme" -Destination $themesFolder -Force
}

# Copy preferred apps to public desktop
$publicDesktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")
Get-ChildItem -Path $publicDesktopPath -File | Remove-Item -Force

$publicDesktopApps = @(
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Firefox.lnk",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Zoom\Zoom Workplace.lnk"
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Cisco\Cisco AnyConnect Secure Mobility Client\Cisco AnyConnect Secure Mobility Client.lnk"
)

foreach ($desktopApp in $publicDesktopApps) {
    Copy-Item -Path $desktopApp -Destination $publicDesktopPath -Force
}

Copy-Item -Path "D:\Customations\ITSupport.ico" -Destination "$env:windir\System32" -Force

$shortcutContent = @"
[InternetShortcut]
URL="https://uga.teamdynamix.com/TDClient/2060/Portal/Requests/ServiceCatalog?CategoryID=3478"
IconFile="$env:windir\System32\ITsupport.ico"
IconIndex=0
"@

$requestITSupportPath = Join-Path -Path $publicDesktopPath -ChildPath "Request IT Support.url"
Set-Content -Path $requestITSupportPath -Value $shortcutContent
