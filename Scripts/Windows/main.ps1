

# 1. Verificar permisos de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR CRÍTICO: Debes ejecutar este script como Administrador." -ForegroundColor Red
    Exit
}

# 2. Carga Dinámica de Librerías (Módulos)
$LibsPath = Join-Path -Path $PSScriptRoot -ChildPath "Libs"
if (Test-Path $LibsPath) {
    Write-Host "Cargando módulos..." -ForegroundColor Cyan
    Get-ChildItem -Path $LibsPath -Filter "*.ps1" | ForEach-Object {
        . $_.FullName  # El punto antes de la variable hace el "Dot Sourcing" (importar)
    }
} else {
    Write-Host "Error: No se encontró la carpeta Libs." -ForegroundColor Red
    Exit
}

# 3. MENÚ PRINCIPAL
while ($true) {
    Clear-Host
    Write-Host "======================================" -ForegroundColor Yellow
    Write-Host "  SISTEMA DE ADMINISTRACIÓN WINDOWS   " -ForegroundColor Yellow
    Write-Host "======================================" -ForegroundColor Yellow
    Write-Host "1. Menú DHCP"
    Write-Host "2. Menú DNS"
    Write-Host "3. Menú SSH"
    Write-Host "4. Salir"
    
    $opcion = Read-Host "Seleccione una opción"

    switch ($opcion) {
        '1' { Show-DhcpMenu }
        '2' { Show-DnsMenu }
        '3' { Show-SshMenu }
        '4' { 
            Write-Host "Saliendo del sistema..." -ForegroundColor Green
            Exit 
        }
        Default { 
            Write-Host "Opción no válida. Presione Enter para continuar." -ForegroundColor Red
            Pause
        }
    }
}