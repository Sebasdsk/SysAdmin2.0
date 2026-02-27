# ==========================================
# FUNCIONES DHCP (WINDOWS SERVER)
# ==========================================

function Show-DhcpMenu {
    while ($true) {
        Clear-Host
        Write-Host "          MENÚ DHCP         "
        Write-Host "1. Instalar Rol DHCP"
        Write-Host "2. Configurar Ambito "
        Write-Host "3. Monitorear DHCP"
        Write-Host "4. Regresar al menú principal"
        
        $opcion = Read-Host "Opción"

        switch ($opcion) {
            '1' { Install-DhcpRole; Pause }
            '2' { Configure-DhcpInteractive; Pause }
            '3' { Monitor-Dhcp; Pause }
            '4' { return } # Retorna al Main.ps1
            Default { Write-Host "Opcion no valida." }
        }
    }
}

function Install-DhcpRole {
    Write-Host "--- Verificando Rol DHCP ---"
    $dhcp = Get-WindowsFeature -Name DHCP
    if ($dhcp.Installed) {
        Write-Host "El rol DHCP ya esta instalado." 
    } else {
        Write-Host "Instalando DHCP..."
        Install-WindowsFeature -Name DHCP -IncludeManagementTools
        Start-Service DHCPServer
    }
}

function Configure-DhcpInteractive {
    Write-Host "--- Configuracion del Ambito DHCP ---"
    $ScopeName = Read-Host "Nombre del Ambito (Ej. RedInterna)"
    $StartIP   = Read-Host "IP Inicial (Ej. 192.168.100.50)"
    $EndIP     = Read-Host "IP Final   (Ej. 192.168.100.150)"
    $Subnet    = Read-Host "Mascara    (Ej. 255.255.255.0)"
    $Gateway   = Read-Host "Gateway    (Ej. 192.168.100.1)"
    $Dns       = Read-Host "DNS Server (Ej. 192.168.100.10)"

    if (-not (Test-IPv4Format $StartIP) -or -not (Test-IPv4Format $EndIP)) {
        Write-Host "Error: Las IP ingresadas no tienen un formato valido." 
        return
    }

    Try {
        Add-DhcpServerv4Scope -Name $ScopeName -StartRange $StartIP -EndRange $EndIP -SubnetMask $Subnet -State Active -ErrorAction Stop
        Set-DhcpServerv4OptionValue -ScopeId $StartIP -OptionId 3 -Value $Gateway
        Set-DhcpServerv4OptionValue -ScopeId $StartIP -OptionId 6 -Value $Dns
        Restart-Service DHCPServer
        Write-Host "Ambito configurado correctamente."
    } Catch {
        Write-Host "Ocurrió un error (¿Quizás el ámbito ya existe?): $_" 
    }
}

function Monitor-Dhcp {
    Write-Host "--- Estado de DHCP ---"
    Get-Service DHCPServer | Select-Object Status, StartType, DisplayName | Format-Table
    Write-Host "--- Concesiones (Leases) ---"
    $scopes = Get-DhcpServerv4Scope
    foreach ($scope in $scopes) {
        Get-DhcpServerv4Lease -ScopeId $scope.ScopeId | Format-Table IPAddress, ClientId, HostName
    }
}