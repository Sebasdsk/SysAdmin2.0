# ==========================================
# FUNCIONES DNS (WINDOWS SERVER)
# ==========================================

function Show-DnsMenu {
    while ($true) {
        Clear-Host
        Write-Host "======================================" -ForegroundColor Magenta
        Write-Host "          MENÚ DNS (WINDOWS)          " -ForegroundColor Magenta
        Write-Host "======================================" -ForegroundColor Magenta
        Write-Host "1. Validar IP Estática (Red Interna)"
        Write-Host "2. Instalar Rol DNS"
        Write-Host "3. Configurar Zona (reprobados.com)"
        Write-Host "4. Validar DNS"
        Write-Host "5. Regresar al menú principal"
        
        $opcion = Read-Host "Opción"

        switch ($opcion) {
            '1' { Set-StaticIpInternal; Pause }
            '2' { Install-DnsRole; Pause }
            '3' { Configure-DnsZone; Pause }
            '4' { Validate-Dns; Pause }
            '5' { return }
            Default { Write-Host "Opción no válida." }
        }
    }
}

function Set-StaticIpInternal {
    Write-Host "--- Configuración de Red Interna ---"
    $nic = Get-InternalInterface
    
    if (-not $nic) { return }

    Write-Host "Interfaz interna detectada: $($nic.Name)" -ForegroundColor Green
    
    $ipInfo = Get-NetIPAddress -InterfaceAlias $nic.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipInfo) {
        Write-Host "IP Actual en $($nic.Name): $($ipInfo.IPAddress)"
    } else {
        Write-Host "La interfaz no tiene IP asignada actualmente."
    }

    $resp = Read-Host "¿Deseas configurar una nueva IP Estática en esta interfaz? (s/n)"
    if ($resp -eq 's') {
        $ip = Read-Host "Ingrese IP (Ej. 192.168.100.10)"
        $prefix = Read-Host "Prefijo de red (Ej. 24 para 255.255.255.0)"
        
        Try {
            # Limpiar IP vieja si existe
            Remove-NetIPAddress -InterfaceAlias $nic.Name -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
            # Asignar nueva
            New-NetIPAddress -InterfaceAlias $nic.Name -IPAddress $ip -PrefixLength $prefix -ErrorAction Stop | Out-Null
            Write-Host "IP configurada correctamente." -ForegroundColor Green
        } Catch {
            Write-Host "Error al configurar la IP: $_" -ForegroundColor Red
        }
    }
}

function Install-DnsRole {
    $dns = Get-WindowsFeature -Name DNS
    if ($dns.Installed) {
        Write-Host "El rol DNS ya está instalado." -ForegroundColor Green
    } else {
        Install-WindowsFeature -Name DNS -IncludeManagementTools
        Write-Host "DNS Instalado." -ForegroundColor Green
    }
}

function Configure-DnsZone {
    $ZoneName = "reprobados.com"
    $ClientIP = Read-Host "Ingrese la IP del cliente para www.$ZoneName"

    if (-not (Get-DnsServerZone | Where-Object Name -eq $ZoneName)) {
        Add-DnsServerPrimaryZone -Name $ZoneName -ZoneFile "$ZoneName.dns"
        Write-Host "Zona $ZoneName creada." -ForegroundColor Green
    } else {
        Write-Host "La zona ya existe."
    }

    Try {
        Remove-DnsServerResourceRecord -ZoneName $ZoneName -Name "www" -RRType "A" -Force -ErrorAction SilentlyContinue
        Add-DnsServerResourceRecordA -ZoneName $ZoneName -Name "www" -IPv4Address $ClientIP
        Write-Host "Registro A (www) apuntando a $ClientIP creado exitosamente." -ForegroundColor Green
    } Catch {
        Write-Host "Error configurando registro: $_" -ForegroundColor Red
    }
}

function Validate-Dns {
    Write-Host "Probando resolución local de www.reprobados.com..."
    Resolve-DnsName -Name "www.reprobados.com" -Server 127.0.0.1 -ErrorAction SilentlyContinue | Format-Table
}