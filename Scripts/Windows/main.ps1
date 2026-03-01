

# 1. Verificar permisos de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR CRITICO: Debes ejecutar este script como Administrador."  
    Exit
}

# 2. Carga Dinámica de Librerías (Módulos)
$LibsPath = Join-Path -Path $PSScriptRoot -ChildPath "Libs"
if (Test-Path $LibsPath) {
    Write-Host "Cargando modulos..."  
    Get-ChildItem -Path $LibsPath -Filter "*.ps1" | ForEach-Object {
        . $_.FullName  # El punto antes de la variable hace el "Dot Sourcing" (importar)
    }
} else {
    Write-Host "Error: No se encontro la carpeta Libs." 
    Exit
}

# 3. MENÚ PRINCIPAL
while ($true) {
    Clear-Host
    Write-Host "  MENU PRINCIPAL   "
    Write-Host "1. Configurar La IP estatica de la red interna"      
    Write-Host "2. DHCP"
    Write-Host "3. DNS"
    Write-Host "4. SSH"
    Write-Host "5. Salir"
    
    $opcion = Read-Host "Seleccione una opcion"

    switch ($opcion) {
        '1' { Set-StaticIpInternal}
        '2' { Show-DhcpMenu }
        '3' { Show-DnsMenu }
        '4' { Show-SshMenu }
        '5' { 
            Write-Host "Saliendo del sistema..." 
            Exit 
        }
        Default {
            Write-Host "Opcion no valida. Presione Enter para continuar." 
            Pause
        }
    }
}