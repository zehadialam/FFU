# Using Full Flash Update (FFU) files to speed up Windows deployment

This repo is a fork of [rbalsleyMSFT](https://github.com/rbalsleymsft/FFU)'s FFU process that has been adapted for the University of Georgia's Windows deployments. FFUs are sector-based files that contain all the partitions of the drive that they are captured from. This is contrasted with WIM files, which is the traditional imaging format that is used with tools like Microsoft Deployment Toolkit, Configuration Manager, etc. WIMs only contain the files from the OS partition and they are also applied at the partition-level during deployment, whereas FFUs are applied at the drive-level upon deployment. The main advantage of imaging with FFU files is that the deployment speed is much faster compared to WIM deployments. This is significantly beneficial in mass deployment scenarios. For more information on these imaging formats, see [WIM vs. VHD vs. FFU: comparing imaging file formats](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/wim-vs-ffu-image-file-formats?view=windows-11).

The goal of this project is to automate the process of building, capturing, and deploying a custom Windows image, as this can often be a time-consuming process to carry out manually. As images quickly become out-of-date, maintaining an image can become burdensome. Having an automated solution allows for any individual to quickly recreate an up-to-date image. To broadly summarize, running the project will download Windows media from Microsoft and applying it to a VHDX file and run it in a Hyper-V VM to install applications and apply customizations. Windows will then be sysprepped, and once the VM shuts down, the FFU will be captured from the VHDX. Optionally, the project can also prepare a deployment USB drive and copy the FFU, drivers, provisioning packages, Autopilot configuration files, and other necessary components. Once the USB drive is booted into on a target device, the FFU will be applied to the drive automatically.

# Prerequisites

Hyper-V must be enabled. To enable Hyper-V with PowerShell, open PowerShell as an administrator and run the following command:
```ps1
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

Once the command finishes running, restart the computer.

# Getting Started

If you're not familiar with Github, you can click the Green code button above and select download zip. Extract the zip file and make sure to copy the FFUDevelopment folder to the root of your C: drive. That will make it easy to follow the guide and allow the scripts to work properly.

If extracted correctly, your c:\FFUDevelopment folder should look like the following. If it does, go to c:\FFUDevelopment\Docs\BuildDeployFFU.docx to get started.

![image](https://github.com/rbalsleyMSFT/FFU/assets/53497092/5400a203-9c2e-42b2-b24c-ab8dfd922ba1)
