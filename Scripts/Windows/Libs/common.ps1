
function Get-InternalInterface {
    # Busca la interfaz que NO tiene un Default Gateway configurado (suele ser la Red Interna en VMs)
    # y que esté conectada (Up)
    $InternalNIC = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ipInfo = Get-NetIPConfiguration -InterfaceAlias $_.Name
        if (-not $ipInfo.IPv4DefaultGateway) {
            $_
        }
    } | Select-Object -First 1

    if ($InternalNIC) {
        return $InternalNIC
    } else {
        Write-Warning "No se pudo detectar automáticamente la red interna."
        Get-NetAdapter | Select-Object Name, InterfaceDescription, Status | Format-Table
        $nicName = Read-Host "Por favor, escribe el Nombre (Name) de la interfaz interna"
        return Get-NetAdapter -Name $nicName -ErrorAction SilentlyContinue
    }
}

function Test-IPv4Format ($IP) {
    $Regex = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
    return $IP -match $Regex
}