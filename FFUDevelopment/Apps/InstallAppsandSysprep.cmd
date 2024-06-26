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
set "SKIP_MSSTORE=false"
if /i "%SKIP_MSSTORE%"=="true" (
    echo Skipping MS Store installation due to SKIP_MSSTORE flag.
    goto :remaining
)
set "basepath=D:\MSStore"
for /r "%basepath%" %%F in (*.appxbundle *.msixbundle) do (
    set "mainpackage=%%F"
    set "dependenciesfolder=%%~dpFDependencies"
    if exist "!dependenciesfolder!" (
        set "dism_command=DISM /Online /Add-ProvisionedAppxPackage /PackagePath:"!mainpackage!""
        for %%G in ("!dependenciesfolder!\*.appx") do (
            set "dism_command=!dism_command! /DependencyPackagePath:"%%G""
        )
        set "license_option=/SkipLicense"
        for %%H in ("!dependenciesfolder!\*.xml") do (
            if exist "%%H" (
                set "license_option=/LicensePath:"%%H""
            )
        )
        set "dism_command=!dism_command! !license_option! /Region:All"
        echo !dism_command!
        !dism_command!
        echo Installation completed for package: !mainpackage!
    )
)
:remaining
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
