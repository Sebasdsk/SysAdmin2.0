# ==========================================
# FUNCIONES DNS (WINDOWS SERVER)
# ==========================================

function Show-DnsMenu {
    while ($true) {
        Clear-Host
        Write-Host "          MENÚ DNS          "
        Write-Host "1. Instalar Rol DNS"
        Write-Host "2. Configurar Zona (reprobados.com)"
        Write-Host "3. Validar DNS"
        Write-Host "4. Regresar al menú principal"
        
        $opcion = Read-Host "Opción"

        switch ($opcion) {
            '1' { Install-DnsRole; Pause }
            '2' { Configure-DnsZone; Pause }
            '3' { Validate-Dns; Pause }
            '4' { return }
            Default { Write-Host "Opcion no valida." }
        }
    }
}


function Install-DnsRole {
    $dns = Get-WindowsFeature -Name DNS
    if ($dns.Installed) {
        Write-Host "El rol DNS ya esta instalado."
    } else {
        Install-WindowsFeature -Name DNS -IncludeManagementTools
        Write-Host "DNS Instalado."
    }
}

function Configure-DnsZone {
    $ZoneName = "reprobados.com"
    $ClientIP = Read-Host "Ingrese la IP del cliente para www.$ZoneName"

    if (-not (Get-DnsServerZone | Where-Object Name -eq $ZoneName)) {
        Add-DnsServerPrimaryZone -Name $ZoneName -ZoneFile "$ZoneName.dns"
        Write-Host "Zona $ZoneName creada."
    } else {
        Write-Host "La zona ya existe."
    }

    Try {
        Remove-DnsServerResourceRecord -ZoneName $ZoneName -Name "www" -RRType "A" -Force -ErrorAction SilentlyContinue
        Add-DnsServerResourceRecordA -ZoneName $ZoneName -Name "www" -IPv4Address $ClientIP
        Write-Host "Registro A (www) apuntando a $ClientIP creado exitosamente."
    } Catch {
        Write-Host "Error configurando registro: $_"
    }
}

function Validate-Dns {
    Write-Host "Probando resolución local de www.reprobados.com..."
    Resolve-DnsName -Name "www.reprobados.com" -Server 127.0.0.1 -ErrorAction SilentlyContinue | Format-Table
}