# Using Full Flash Update (FFU) files to speed up Windows deployment
<p align="center">
  <img src="Image/Media/windows.png"/>
  <img src="Image/Media/powershell.png"/>
  <img src="Image/Media/hyper-v.png"/>
</p>

This repo is a fork of [rbalsleyMSFT](https://github.com/rbalsleymsft/FFU)'s FFU process that has been adapted for Windows deployments at the University of Georgia. [FFU](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/deploy-windows-using-full-flash-update--ffu?view=windows-11) is a sector-based imaging format that contains all the partitions of the drive that it is captured from. This can be contrasted with WIM, which is the [traditional imaging format](https://www.microsoft.com/en-us/download/details.aspx?id=13096) that is used with tools like Microsoft Deployment Toolkit, Configuration Manager, etc. A [WIM](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/capture-and-apply-windows-using-a-single-wim?view=windows-11) is a file-based imaging format that only contains the files from a single partition. WIMs are applied at the partition-level during deployment, whereas FFUs are applied at the drive-level. The main advantage of imaging with FFU files is that the deployment speed is much faster compared to WIM deployments due to being sector-based. This is significantly beneficial in mass deployment scenarios. For more information on these imaging formats, see [WIM vs. VHD vs. FFU: comparing imaging file formats](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/wim-vs-ffu-image-file-formats?view=windows-11).

The goal of this project is to provide a comprehensive Windows deployment solution using modern methods. This includes automating the process of building, capturing, and deploying a custom Windows image. As images quickly become out-of-date, maintaining or recreating them can become burdensome. Having an automated solution allows for any individual to quickly rebuild an up-to-date image. To broadly summarize, running the project will download Windows media from Microsoft, apply it to a VHDX file, and run it in a Hyper-V VM to install applications and apply customizations. Windows will then be [sysprepped](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep--generalize--a-windows-installation?view=windows-11), and once the VM shuts down, the FFU will be captured from the VHDX. The project can optionally prepare a deployment USB drive and copy the FFU, drivers, [provisioning packages](https://learn.microsoft.com/en-us/windows/configuration/provisioning-packages/provisioning-create-package), [Autopilot configuration files](https://learn.microsoft.com/en-us/autopilot/existing-devices), and other necessary components. Once the USB drive is booted into on a target device, the FFU will be applied to the drive automatically.

## Parent Project Contributions
I am a contributor to the [parent project](https://github.com/rbalsleymsft/FFU). My contributions include the following feature additions:
- Automated the download and installation of the Windows ADK to eliminate a manual project prerequisite. [PR 14](https://github.com/rbalsleyMSFT/FFU/pull/14)
- Automated the upgrade of an existing ADK installation to the latest version and added more robust handling of various ADK scenarios. [PR 18](https://github.com/rbalsleyMSFT/FFU/pull/18)
- Added procedures and optimizations to reduce the size of the captured FFU. [PR 25](https://github.com/rbalsleyMSFT/FFU/pull/25)

All contributions to the parent project are included in this fork. This repo also remains in sync with the latest updates from the parent project.

## Features Unique to This Fork
This fork contains unique functionality that would detract from either the goals or the generalized nature of the parent project. These include the following image customizations:
- Removing various in-box Windows apps commonly regarded as "bloatware"
- Applying a custom Windows theme and wallpaper
- Applying a custom lock screen
- Configuring the taskbar layout with pinned apps
- Configuring the public desktop
- Configuring various group policy settings that are desirable in enterprise/education environments

## Prerequisites

Hyper-V must be enabled. To enable Hyper-V with PowerShell, open PowerShell as an administrator and run the following command:
```ps1
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

Once the command finishes running, restart the computer.

## Getting Started

If you're not familiar with Github, you can click the Green code button above and select download zip. Extract the zip file and make sure to copy the FFUDevelopment folder to the root of your C: drive. That will make it easy to follow the guide and allow the scripts to work properly.

If extracted correctly, your c:\FFUDevelopment folder should look like the following. If it does, go to c:\FFUDevelopment\Docs\BuildDeployFFU.docx to get started.

![image](https://github.com/rbalsleyMSFT/FFU/assets/53497092/5400a203-9c2e-42b2-b24c-ab8dfd922ba1)
