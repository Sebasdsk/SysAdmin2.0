

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
    Write-Host "1. DHCP"
    Write-Host "2. DNS"
    Write-Host "3. SSH"
    Write-Host "4. Salir"
    
    $opcion = Read-Host "Seleccione una opcion"

    switch ($opcion) {
        '1' { Show-DhcpMenu }
        '2' { Show-DnsMenu }
        '3' { Show-SshMenu }
        '4' { 
            Write-Host "Saliendo del sistema..." 
            Exit 
        }
        Default {
            Write-Host "Opcion no valida. Presione Enter para continuar." 
            Pause
        }
    }
}