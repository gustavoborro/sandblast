# ==========================================
# Configuration
# ==========================================
# Replace with your external machine's receiving URL
$externalUrl = "http://20.206.201.113:8080/endpoint" 

# ==========================================
# Data Collection
# ==========================================
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
$cpuInfo = Get-CimInstance -ClassName Win32_Processor
$ramInfo = Get-CimInstance -ClassName Win32_ComputerSystem
$diskInfo = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object DriveType -eq 3
$netInfo = Get-NetIPAddress | Where-Object AddressFamily -eq "IPv4" | Where-Object InterfaceAlias -notlike "*Loopback*"

# Compile data into a custom object
$machineData = [PSCustomObject]@{
    ComputerName  = $env:COMPUTERNAME
    OS            = $osInfo.Caption
    OSVersion     = $osInfo.Version
    Architecture  = $osInfo.OSArchitecture
    Processor     = $cpuInfo.Name
    TotalMemoryGB = [math]::round($ramInfo.TotalPhysicalMemory / 1GB, 2)
    FreeSpaceGB   = [math]::round(($diskInfo.FreeSpace | Measure-Object -Sum).Sum / 1GB, 2)
    IPAddress     = $netInfo.IPAddress
    MACAddress    = (Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1).MacAddress
    Timestamp     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

# Convert to JSON
$jsonPayload = $machineData | ConvertTo-Json

# ==========================================
# Send to External Machine
# ==========================================
try {
    Invoke-RestMethod -Uri $externalUrl -Method Post -Body $jsonPayload -ContentType "application/json"
    Write-Host "Data successfully sent to $externalUrl" -ForegroundColor Green
} catch {
    Write-Host "Failed to send data. Error: $_" -ForegroundColor Red
}
