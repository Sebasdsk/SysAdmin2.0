# ==========================================
# FUNCIONES SSH (WINDOWS SERVER)
# ==========================================

function Show-SshMenu {
    while ($true) {
        Clear-Host
        Write-Host "          MENÚ SSH (WINDOWS)          " 
        Write-Host "1. Instalar y Configurar OpenSSH"
        Write-Host "2. Validar Estado y Conexión"
        Write-Host "3. Regresar al menú principal"
        
        $opcion = Read-Host "Opción"

        switch ($opcion) {
            '1' { Install-SshServer; Pause }
            '2' { Validate-Ssh; Pause }
            '3' { return } # Regresa al Main.ps1
            Default { Write-Host "Opción no válida." }
        }
    }
}

function Install-SshServer {
    Write-Host "--- Instalación y Configuración de OpenSSH ---" 
    
    # 1. Verificar e instalar la característica OpenSSH
    # Usamos Get-WindowsCapability porque en Windows Server 2019/2022 SSH viene como "Capability", no como "Feature" normal
    $sshCheck = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    
    if ($sshCheck.State -ne 'Installed') {
        Write-Host "Instalando característica OpenSSH Server (puede tardar un momento)..." 
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
        Write-Host "Instalación completada." 
    } else {
        Write-Host "OpenSSH Server ya se encuentra instalado." 
    }

    # 2. Configurar el servicio (Auto-Start)
    Write-Host "Configurando el servicio sshd..."
    Set-Service -Name sshd -StartupType 'Automatic'
    Start-Service sshd
    Write-Host "Servicio sshd en ejecución y configurado para arranque automático." 

    # 3. Asegurar Regla de Firewall para el Puerto 22
    # OpenSSH a veces la crea, pero asegurarla garantiza la idempotencia y cumple tu rúbrica
    $fwRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if (-not $fwRule) {
        Write-Host "Creando regla de firewall para permitir el puerto 22..." 
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        Write-Host "Regla de firewall creada." 
    } else {
        Write-Host "La regla de firewall para SSH ya está configurada correctamente." 
    }
}

function Validate-Ssh {
    Write-Host "--- Estado del Servicio SSH ---" 
    Get-Service sshd | Select-Object Status, Name, DisplayName, StartType | Format-Table -AutoSize
    
    Write-Host "--- Información de Conexión ---" 
    
    # Reutilizamos la función Get-InternalInterface de Common.ps1 para dar la IP correcta de la VM
    $nic = Get-InternalInterface
    if ($nic) {
        $ipInfo = Get-NetIPAddress -InterfaceAlias $nic.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ipInfo) {
            Write-Host "Puedes conectarte desde el cliente usando:" 
            Write-Host "ssh Administrador@$($ipInfo.IPAddress)" 
        }
    } else {
        Write-Host "No se pudo determinar la IP de la red interna automáticamente."
    }
    
    # Comprobar que el puerto realmente está "Listening" (Escuchando)
    $portCheck = Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue
    if ($portCheck) {
        Write-Host "`nEl servidor está escuchando activamente en el puerto 22." 
    } else {
        Write-Host "`nADVERTENCIA: No se detecta escucha en el puerto 22. Verifica el servicio." 
    }
}