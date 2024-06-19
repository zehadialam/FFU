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
            Get-AppXProvisionedPackage -Online | Where-Object DisplayName -eq $provisionedAppName | Remove-AppxProvisionedPackage -Online -AllUsers
        }
    }
} catch {
    throw $_
}

Import-StartLayout -LayoutPath "D:\Customizations\taskbar.xml" -MountPath "C:\"

Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Session Manager\Configuration Manager" -Name "EnablePeriodicBackup" -Value 1 -Type "REG_DWORD"
# Configures the Chat icon on the taskbar
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Windows Chat" -Name "ChatIcon" -Value 3 -Type "REG_DWORD"
# Disable widgets
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0 -Type "REG_DWORD"
# Do not show Windows tips
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableSoftLanding" -Value 1 -Type "REG_DWORD"
# Turn off cloud consumer account state content
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableConsumerAccountStateContent" -Value 1 -Type "REG_DWORD"
# Turn off Microsoft consumer experiences
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1 -Type "REG_DWORD"
Copy-Item -Path "D:\Customizations\lockscreen.jpg" -Destination "C:\Windows\Web\Screen" -Force
# Set lock screen
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -Name "LockScreenImage" -Value "C:\Windows\Web\Screen\lockscreen.jpg" -Type "REG_SZ"
# Prevent changing lock screen and logon image
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -Name "NoChangingLockScreen" -Value 0 -Type "REG_DWORD"
# Turn off fun facts, tips, tricks, and more on lock screen
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Personalization" -Name "LockScreenOverlaysDisabled" -Value 1 -Type "REG_DWORD"

$themesFolder = "C:\Users\Default\AppData\Local\Microsoft\Windows\Themes"
if (-not (Test-Path $themesFolder -PathType Container)) {
    New-Item -Path $themesFolder -ItemType Directory
    Copy-Item -Path "D:\Customizations\oem.theme" -Destination $themesFolder -Force
}

# Use Windows Hello for Business
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\PassportForWork" -Name "Enabled" -Value 1 -Type "REG_DWORD"
# Do not start Windows Hello provisioning after sign-in
Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\PassportForWork" -Name "DisablePostLogonProvisioning" -Value 1 -Type "REG_DWORD"