# ==========================================
# FUNCIONES DNS (WINDOWS SERVER) - ADAPTADO PRACTICA 3
# ==========================================

function Show-DnsMenu {
    while ($true) {
        Clear-Host
        Write-Host "          MENÚ DNS          "
        Write-Host "1. Instalar Rol DNS"
        Write-Host "2. Configurar Nueva Zona (Dinámica)"
        Write-Host "3. Validar DNS (nslookup local)"
        Write-Host "4. Regresar al menú principal"
        
        $opcion = Read-Host "Opción"

        switch ($opcion) {
            '1' { Install-DnsRole; Pause }
            '2' { Configure-DnsZone-Interactive; Pause }
            '3' { Validate-Dns; Pause }
            '4' { return }
            Default { Write-Host "Opción no válida." }
        }
    }
}

function Install-DnsRole {
    # y
    $dns = Get-WindowsFeature -Name DNS
    if ($dns.Installed) {
        Write-Host "El rol DNS ya está instalado." -ForegroundColor Green
    } else {
        Write-Host "Instalando DNS..."
        Install-WindowsFeature -Name DNS -IncludeManagementTools
        Write-Host "DNS Instalado." -ForegroundColor Green
    }
}

function Configure-DnsZone-Interactive {
    # Lógica adaptada de
    
    $iteracion = $true

    do {
        Write-Host "--- Configuración de Nueva Zona ---" -ForegroundColor Cyan
        
        # 1. Solicitar Dominio
        do {
            $dominio = Read-Host "Ingrese el dominio deseado (ej. miempresa.com)"
            if ([string]::IsNullOrEmpty($dominio)) {
                Write-Host "El dominio no puede ser vacío." -ForegroundColor Red
            } else {
                break
            }
        } while ($true)

        # 2. Solicitar IP
        # Usamos regex de validación simple como en la práctica de Alberto
        $regex = "^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$"
        do {
            $ip = Read-Host "Ingrese la dirección IP a la que apuntará el dominio"
            if ($ip -match $regex) {
                break
            } else {
                Write-Host "Formato de IP no válido." -ForegroundColor Red
            }
        } while ($true)

        # 3. Crear Zona Primaria
        #
        Try {
            if (-not (Get-DnsServerZone | Where-Object Name -eq $dominio)) {
                Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns" -DynamicUpdate NonsecureAndSecure -ErrorAction Stop
                Write-Host "Zona $dominio creada correctamente." -ForegroundColor Green
            } else {
                Write-Host "La zona $dominio ya existe. Agregando registros..." -ForegroundColor Yellow
            }

            # 4. Crear Registros A (@ y www)
            # Registro Raíz (@)
            Add-DnsServerResourceRecordA -Name "@" -ZoneName $dominio -IPv4Address $ip -ErrorAction SilentlyContinue
            # Registro WWW
            Add-DnsServerResourceRecordA -Name "www" -ZoneName $dominio -IPv4Address $ip -ErrorAction SilentlyContinue
            
            Write-Host "Registros A (@ y www) creados apuntando a $ip" -ForegroundColor Green

        } Catch {
            Write-Host "Error durante la configuración: $_" -ForegroundColor Red
        }

        # Reiniciar servicio para asegurar cambios
        Restart-Service -Name DNS
        Write-Host "Servicio DNS reiniciado."

        # 5. Preguntar si continuar
        $res = Read-Host "¿Quiere registrar otro dominio? (S/N)"
        if ($res -ne "S" -and $res -ne "s") {
            $iteracion = $false
        }

    } while ($iteracion)
}

function Validate-Dns {
    $dom = Read-Host "Ingrese dominio a probar (ej. www.miempresa.com)"
    if ([string]::IsNullOrEmpty($dom)) { $dom = "www.reprobados.com" }
    
    Write-Host "Probando resolución local de $dom..."
    Resolve-DnsName -Name $dom -Server 127.0.0.1 -ErrorAction SilentlyContinue | Format-Table
}