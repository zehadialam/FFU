Install-Module Microsoft.Graph.Beta.DeviceManagement -confirm:$false -Force -AllowClobber
Import-Module Microsoft.Graph.Beta.DeviceManagement

Connect-MgGraph
 
$uri = "https://graph.microsoft.com/beta/deviceManagement/importedDeviceIdentities/importDeviceIdentityList"
 
$computerSystem = Get-Ciminstance -Class Win32_ComputerSystem 
$manufacturer = $computerSystem.Manufacturer
$model = $computerSystem.Model
$serialNumber = (Get-Ciminstance -Class Win32_BIOS).SerialNumber
 
$body = @{
    overwriteImportedDeviceIdentities = $false
    importedDeviceIdentities = @(
        @{
            importedDeviceIdentityType = "manufacturerModelSerial"
            importedDeviceIdentifier = "$manufacturer,$model,$serialNumber"
        }
    )
}
 
Invoke-MgGraphRequest -Uri $uri -Method POST -Body $body