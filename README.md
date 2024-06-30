# Using Full Flash Update (FFU) files to speed up Windows deployment
<div style="text-align: center;">
    <img src="/Image/Media/windows.png" alt="Image 1" style="display: inline-block; margin: 0 10px;" />
    <img src="/Image/Media/powershell.png" alt="Image 2" style="display: inline-block; margin: 0 10px;" />
    <img src="/Image/Media/hyper-v.png" alt="Image 3" style="display: inline-block; margin: 0 10px;" />
</div>

This repo is a fork of [rbalsleyMSFT](https://github.com/rbalsleymsft/FFU)'s FFU process that has been adapted for the University of Georgia's Windows deployments. FFU is a sector-based imaging format that contains all the partitions of the drive that it is captured from. This is contrasted with WIM, which is the traditional imaging format that is used with tools like Microsoft Deployment Toolkit, Configuration Manager, etc. WIMs are a file-based imaging format and they only contain the files from the OS partition. WIMs are applied at the partition-level during deployment, whereas FFUs are applied at the drive-level. The main advantage of imaging with FFU files is that the deployment speed is much faster compared to WIM deployments due to being sector-based. This is significantly beneficial in mass deployment scenarios. For more information on these imaging formats, see [WIM vs. VHD vs. FFU: comparing imaging file formats](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/wim-vs-ffu-image-file-formats?view=windows-11).

The goal of this project is to automate the process of building, capturing, and deploying a custom Windows image. As images quickly become out-of-date, maintaining an image can become burdensome. Having an automated solution allows for any individual to quickly recreate an up-to-date image. To broadly summarize, running the project will download Windows media from Microsoft, apply it to a VHDX file, and run it in a Hyper-V VM to install applications and apply customizations. Windows will then be sysprepped, and once the VM shuts down, the FFU will be captured from the VHDX. Optionally, the project can also prepare a deployment USB drive and copy the FFU, drivers, provisioning packages, Autopilot configuration files, and other necessary components. Once the USB drive is booted into on a target device, the FFU will be applied to the drive automatically.

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
