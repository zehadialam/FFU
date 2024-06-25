setlocal enabledelayedexpansion

REM Put each app install on a separate line
REM M365 Apps/Office ProPlus
REM d:\Office\setup.exe /configure d:\office\DeployFFU.xml
REM Install Defender Platform Update
REM Install Defender Definitions
REM Install Windows Security Platform Update
REM Install OneDrive Per Machine
REM Install Edge Stable
REM Add additional apps below here
REM Contoso App (Example)
REM msiexec /i d:\Contoso\setup.msi /qn /norestart
set "anyconnectfolder=D:\Cisco-AnyConnect"
for %%f in ("%anyconnectfolder%\*.msi") do (
    set "anyconnectinstaller=%%f"
)
if defined anyconnectinstaller (
    msiexec /i %anyconnectinstaller% /qn /norestart
)
@echo off
set "SKIP_MSSTORE=1"
if not defined SKIP_MSSTORE (
    set "msstore_folder=D:\MSStore"
    for /D %%d in ("%msstore_folder%\*") do (
        set "main_package="
        REM Find the main package file with .appxbundle or .msixbundle extension
        for %%f in ("%%d\*.appxbundle" "%%d\*.msixbundle") do (
            if exist "%%f" (
                set "main_package=%%f"
            )
        )
        if defined main_package (
            set "dependency_folder=%%d\Dependencies"
            set "dism_command=DISM /Online /Add-ProvisionedAppxPackage /PackagePath:!main_package!"
            for %%g in ("!dependency_folder!\*.appx") do (
                REM Concatenate the dependency package path to the command
                set "dism_command=!dism_command! /DependencyPackagePath:%%g"
            )
            set "license_option=/SkipLicense"
            for %%h in ("!dependency_folder!\*.xml") do (
                if exist "%%h" (
                    set "license_option=/LicensePath:%%h"
                )
            )
            set "dism_command=!dism_command! !license_option! /Region:All"
            echo !dism_command!
            !dism_command!
        )
    )
)
endlocal
@echo on
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Customizations\Set-ImageCustomizations.ps1
REM The below lines will remove the unattend.xml that gets the machine into audit mode. If not removed, the OS will get stuck booting to audit mode each time.
REM Also kills the sysprep process in order to automate sysprep generalize
del c:\windows\panther\unattend\unattend.xml /F /Q
del c:\windows\panther\unattend.xml /F /Q
taskkill /IM sysprep.exe
timeout /t 10
REM Run disk cleanup (cleanmgr.exe) with all options enabled: https://learn.microsoft.com/en-us/troubleshoot/windows-server/backup-and-storage/automating-disk-cleanup-tool
set rootkey=HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches
REM Per above doc, the Offline Pages Files subkey does not have stateflags value
for /f "tokens=*" %%K in ('reg query "%rootkey%"') do (
    echo %%K | findstr /i /c:"Offline Pages Files"
    if errorlevel 1 (
        reg add "%%K" /v StateFlags0000 /t REG_DWORD /d 2 /f
    )
)
cleanmgr.exe /sagerun:0
REM Remove the StateFlags0000 registry value
for /f "tokens=*" %%K in ('reg query "%rootkey%"') do (
    echo %%K | findstr /i /c:"Offline Pages Files"
    if errorlevel 1 (
        reg delete "%%K" /v StateFlags0000 /f
    )
)
powershell -Command "Get-EventLog -List | ForEach-Object { Clear-EventLog $_.Log }"
REM Sysprep/Generalize
c:\windows\system32\sysprep\sysprep.exe /quiet /generalize /oobe
