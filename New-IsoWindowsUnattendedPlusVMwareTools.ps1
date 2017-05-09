
#Description
#Windows server 2016 unattended installation with VMware tools.
#Build process automatized with PowerShell.
#PVSCI drivers are included in the ISO for an installation on top of "VMware paravirtual SCSI" controller.
#After the installation use "invoke-vmscript" to configure all settings needed in the OS.

#Notes
#Author: Christophe Calvet
#Based on the work of many others bloggers, complete list in the blog.
#Blog: http:/thecrazyconsultant/windows-server-2016-unattended-installation-plus-vmware-tools
 

# Prerequisites:
### 1) Windows 10
# SSD strongly recommended for a fast execution
### 2) Windows ADK installed in the default installation path. (Deployment Tools only)
# https://developer.microsoft.com/en-us/windows/hardware/windows-assessment-deployment-kit
# Use the one associated to your build
# To find your build: (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ReleaseId).ReleaseId
### 3) Download Windows ISO.
# Example with windows server 2016 evaluation:
# https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2016/
# 14393.0.161119-1705.RS1_REFRESH_SERVER_EVAL_X64FRE_EN-US.ISO
### 4) Create "autounattend.xml" for this Operating System.
# The autounattend.xml must be configured to launch the installation of VMware tools.
# Please see details in the blog.
### 5) Identify the URL of the VMware tools ISO matching the version to be installed in Windows.
# https://packages.vmware.com/tools/esx/index.html


###################RUN THE POWERSHELL SCRIPT AS ADMINISTRATOR#####################
#Disconnect all ISO already mounted if any.

New-Item -ItemType Directory -Path C:\CustomizedWindowsIso
New-Item -ItemType Directory -Path C:\CustomizedWindowsIso\FinalIso
New-Item -ItemType Directory -Path C:\CustomizedWindowsIso\UnattendXML

#To create a new ISO:
#1)Disconnect all ISO already mounted
#2)Modify user parameters
#3)Execute all commands below.

#Modify user parameters as needed.
$SourceWindowsIsoPath = 'C:\ALL ISO\Microsoft\14393.0.161119-1705.RS1_REFRESH_SERVER_EVAL_X64FRE_EN-US.ISO'
$VMwareToolsIsoUrl = "https://packages.vmware.com/tools/esx/6.5/windows/VMware-tools-windows-10.1.0-4449150.iso"
$AutoUnattendXmlPath = 'C:\CustomizedWindowsIso\UnattendXML\2016\autounattend.xml'
#By default the script will install 64 bits drivers for pvscsi but you can edit the relevant lines in the script for 32 bits.

#Clean DISM mount point if any. Linked to the PVSCSI drivers injection.
Clear-WindowsCorruptMountPoint
Dismount-WindowsImage -path 'C:\CustomizedWindowsIso\Temp\MountDISM' -discard

#The Temp folder is only needed during the creation of one ISO.
Remove-Item -Recurse -Force 'C:\CustomizedWindowsIso\Temp'

New-Item -ItemType Directory -Path C:\CustomizedWindowsIso\Temp
New-Item -ItemType Directory -Path C:\CustomizedWindowsIso\Temp\WorkingFolder
New-Item -ItemType Directory -Path C:\CustomizedWindowsIso\Temp\VMwareTools
New-Item -ItemType Directory -Path C:\CustomizedWindowsIso\Temp\MountDISM

#Prepare path for the Windows ISO destination file
$SourceWindowsIsoFullName = $SourceWindowsIsoPath.split("\")[-1]
$DestinationWindowsIsoPath = 'C:\CustomizedWindowsIso\FinalIso\' +  ($SourceWindowsIsoFullName -replace ".iso","") + '-CUSTOM.ISO'

#Download VMware Tools ISO  
$VMwareToolsIsoFullName = $VMwareToolsIsoUrl.split("/")[-1]
$VMwareToolsIsoPath =  "C:\CustomizedWindowsIso\Temp\VMwareTools\" + $VMwareToolsIsoFullName 
(New-Object System.Net.WebClient).DownloadFile($VMwareToolsIsoUrl, $VMwareToolsIsoPath)

#Reminder Disconnect all ISO already mounted 

# mount the source Windows iso.
$MountSourceWindowsIso = mount-diskimage -imagepath $SourceWindowsIsoPath -passthru
# get the drive letter assigned to the iso.
$DriveSourceWindowsIso = ($MountSourceWindowsIso | get-volume).driveletter + ':'

#Mount VMware tools ISO
$MountVMwareToolsIso = mount-diskimage -imagepath $VMwareToolsIsoPath -passthru
# get the drive letter assigned to the iso.
$DriveVMwareToolsIso = ($MountVMwareToolsIso  | get-volume).driveletter + ':'

# Copy the content of the Source Windows Iso to a Working Folder
copy-item $DriveSourceWindowsIso\* -Destination 'C:\CustomizedWindowsIso\Temp\WorkingFolder' -force -recurse

# remove the read-only attribtue from the extracted files.
get-childitem 'C:\CustomizedWindowsIso\Temp\WorkingFolder' -recurse | %{ if (! $_.psiscontainer) { $_.isreadonly = $false } }

#Copy VMware tools exe in a custom folder in the future ISO
New-Item -ItemType Directory -Path 'C:\CustomizedWindowsIso\Temp\WorkingFolder\CustomFolder'
#For 64 bits by default.
copy-item "$DriveVMwareToolsIso\setup64.exe" -Destination 'C:\CustomizedWindowsIso\Temp\WorkingFolder\CustomFolder'
#For 32 bits comment above line and uncomment line below.
#copy-item "$DriveVMwareToolsIso\setup.exe" -Destination 'C:\CustomizedWindowsIso\TempWorkingFolder\CustomFolder'


#Inject PVSCSI Drivers in boot.wim and install.vim

#For 64 bits
$pvcsciPath = $DriveVMwareToolsIso + '\Program Files\VMware\VMware Tools\Drivers\pvscsi\Win8\amd64\pvscsi.inf'
#For 32 bits
#$pvcsciPath = $DriveVMwareToolsIso + '\Program Files\VMware\VMware Tools\Drivers\pvscsi\Win8\i386\pvscsi.inf'


#Optional check all Image Index for boot.wim
Get-WindowsImage -ImagePath 'C:\CustomizedWindowsIso\Temp\WorkingFolder\sources\boot.wim'

#Modify all images in "boot.wim"
#Example for windows 2016 iso:
# Microsoft Windows PE (x64)
# Microsoft Windows Setup (x64)

Get-WindowsImage -ImagePath 'C:\CustomizedWindowsIso\Temp\WorkingFolder\sources\boot.wim' | foreach-object {
	Mount-WindowsImage -ImagePath 'C:\CustomizedWindowsIso\Temp\WorkingFolder\sources\boot.wim' -Index ($_.ImageIndex) -Path 'C:\CustomizedWindowsIso\Temp\MountDISM'
	Add-WindowsDriver -path 'C:\CustomizedWindowsIso\Temp\MountDISM' -driver $pvcsciPath -ForceUnsigned
	Dismount-WindowsImage -path 'C:\CustomizedWindowsIso\Temp\MountDISM' -save
}

#Optional check all Image Index for install.wim
Get-WindowsImage -ImagePath 'C:\CustomizedWindowsIso\Temp\WorkingFolder\sources\install.wim'

#Modify all images in "install.wim"
#Example for windows 2016 iso:
# Windows Server 2016 SERVERSTANDARDCORE
# Windows Server 2016 SERVERSTANDARD
# Windows Server 2016 SERVERDATACENTERCORE
# Windows Server 2016 SERVERDATACENTER

Get-WindowsImage -ImagePath 'C:\CustomizedWindowsIso\Temp\WorkingFolder\sources\install.wim' | foreach-object {
	Mount-WindowsImage -ImagePath 'C:\CustomizedWindowsIso\Temp\WorkingFolder\sources\install.wim' -Index ($_.ImageIndex) -Path 'C:\CustomizedWindowsIso\Temp\MountDISM'
	Add-WindowsDriver -path 'C:\CustomizedWindowsIso\Temp\MountDISM' -driver $pvcsciPath -ForceUnsigned
	Dismount-WindowsImage -path 'C:\CustomizedWindowsIso\Temp\MountDISM' -save
}

#Add the autaunattend xml for a basic configuration AND the installation of VMware tools.
copy-item $AutoUnattendXmlPath -Destination 'C:\CustomizedWindowsIso\Temp\WorkingFolder\autounattend.xml'


#Maybe in a future update of the script
#Add all patches in the ISO  with ADD-WINDOWS PACKAGE


#Now copy the content of the working folder in the new custom windows ISO.

$OcsdimgPath = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg'
$oscdimg  = "$OcsdimgPath\oscdimg.exe"
$etfsboot = "$OcsdimgPath\etfsboot.com"
$efisys   = "$OcsdimgPath\efisys.bin"

$data = '2#p0,e,b"{0}"#pEF,e,b"{1}"' -f $etfsboot, $efisys
start-process $oscdimg -args @("-bootdata:$data",'-u2','-udfver102', 'C:\CustomizedWindowsIso\Temp\WorkingFolder', $DestinationWindowsIsoPath) -wait -nonewwindow

#Mount this ISO in a new VM and enjoy.
