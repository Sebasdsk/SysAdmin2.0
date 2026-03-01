
function Get-InternalInterface {
    # Busca la interfaz que NO tiene un Default Gateway configurado (suele ser la Red Interna en VMs)
    # y que este conectada (Up)
    $InternalNIC = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ipInfo = Get-NetIPConfiguration -InterfaceAlias $_.Name
        if (-not $ipInfo.IPv4DefaultGateway) {
            $_
        }
    } | Select-Object -First 1

    if ($InternalNIC) {
        return $InternalNIC
    } else {
        Write-Warning "No se pudo detectar automaticamente la red interna."
        Get-NetAdapter | Select-Object Name, InterfaceDescription, Status | Format-Table
        $nicName = Read-Host "Por favor, escribe el Nombre (Name) de la interfaz interna"
        return Get-NetAdapter -Name $nicName -ErrorAction SilentlyContinue
    }
}

function Test-IPv4Format ($IP) {
    $Regex = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
    return $IP -match $Regex
}


function Set-StaticIpInternal {
    Write-Host "--- Configuracion de Red Interna ---"
    $nic = Get-InternalInterface
    
    if (-not $nic) { return }

    Write-Host "Interfaz interna detectada: $($nic.Name)"
    
    $ipInfo = Get-NetIPAddress -InterfaceAlias $nic.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipInfo) {
        Write-Host "IP Actual en $($nic.Name): $($ipInfo.IPAddress)"
    } else {
        Write-Host "La interfaz no tiene IP asignada actualmente."
    }

    $resp = Read-Host "¿Deseas configurar una nueva IP Estatica en esta interfaz? (s/n)"
    if ($resp -eq 's') {
        $ip = Read-Host "Ingrese IP (Ej. 192.168.100.10)"
        $prefix = Read-Host "Prefijo de red (Ej. 24 para 255.255.255.0)"
        
        Try {
            # Limpiar IP vieja si existe
            Remove-NetIPAddress -InterfaceAlias $nic.Name -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
            # Asignar nueva
            New-NetIPAddress -InterfaceAlias $nic.Name -IPAddress $ip -PrefixLength $prefix -ErrorAction Stop | Out-Null
            Write-Host "IP configurada correctamente."
        } Catch {
            Write-Host "Error al configurar la IP: $_"
        }
    }
}
