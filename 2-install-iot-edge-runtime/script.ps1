
# Reference: https://learn.microsoft.com/en-us/azure/lab-services/how-to-enable-nested-virtualization-template-vm-using-script#enable-nested-virtualization-by-using-a-script
write-Host "Enable nested virtualization by using a script" -NoNewline

Set-ExecutionPolicy bypass -force

Invoke-WebRequest 'https://aka.ms/azlabs/scripts/hyperV-powershell' -Outfile SetupForNestedVirtualization.ps1 


powershell.exe -noprofile -executionpolicy bypass -file .\SetupForNestedVirtualization.ps1
.\SetupForNestedVirtualization.ps1

Set-ExecutionPolicy default -force

# Reference:
write-Host "Install and start the IoT Edge runtime" -NoNewline

# enable Hyper-V
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# download IoT Edge for Linux on Windows
$msiPath = $([io.Path]::Combine($env:TEMP, 'AzureIoTEdge.msi'))

$ProgressPreference = 'SilentlyContinue'

Invoke-WebRequest "https://aka.ms/AzEFLOWMSI_1_4_LTS_X64" -OutFile $msiPath

# Install IoT Edge for Linux on Windows on your device
Start-Process -Wait msiexec -ArgumentList "/i","$([io.Path]::Combine($env:TEMP, 'AzureIoTEdge.msi'))","/qn"

# Set the execution policy on the target device to AllSigned if it is not already
Get-ExecutionPolicy -List

Set-ExecutionPolicy -ExecutionPolicy AllSigned -Force

# Create the IoT Edge for Linux on Windows deployment
Deploy-Eflow

# Provision your device using the device connection string
Provision-EflowVm -provisioningType ManualConnectionString -devConnString "<CONNECTION_STRING_HERE>"​