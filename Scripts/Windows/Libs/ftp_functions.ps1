# ==========================================
# FUNCIONES FTP (IIS) 
# ==========================================

function Show-FtpMenu {
    do {
        Clear-Host
        Write-Host "=================================="
        Write-Host "     Administrador de FTP"
        Write-Host "=================================="
        Write-Host "1. Instalar y Configurar FTP Completo"
        Write-Host "2. Crear grupos locales"
        Write-Host "3. Crear usuario FTP"
        Write-Host "4. Eliminar usuario FTP"
        Write-Host "5. Configurar autenticación y permisos"
        Write-Host "6. Reiniciar sitio FTP"
        Write-Host "7. Regresar al menú principal"
        Write-Host "=================================="
        
        $opcion = Read-Host "Seleccione una opción"

        switch ($opcion) {
            1 {
                Write-Host "Iniciando instalación y configuración completa de FTP..." -ForegroundColor Cyan

                Instalar-Caracteristicas
                Crear-Estructura-FTP
                Crear-Sitio-FTP
                Configurar-TLS
                Configurar-UserIsolation
                Configurar-Autenticacion-Permisos

                Write-Host "Configuración completa de FTP finalizada." -ForegroundColor Green
                Pause
            }
            2 { 
                Crear-Grupos-Locales 
                Pause
            }
            3 { 
                Crear-Usuario-FTP 
                Pause
            }
            4 { 
                $nombreUsuario = Read-Host "Ingrese el nombre de usuario a eliminar"
                Eliminar-Usuario-FTP -nombreUsuario $nombreUsuario
                Pause
            }
            5 { 
                Configurar-Autenticacion-Permisos 
                Pause
            }
            6 { 
                Reiniciar-FTP 
                Pause
            }
            7 { 
                Write-Host "Regresando al menú principal..." 
                return
            }
            default {
                Write-Host "Opción no válida. Por favor, seleccione una opción entre 1 y 7." -ForegroundColor Red
                Pause
            }
        }
    } while ($true)
}

# ==========================================
# LÓGICA Y FUNCIONALIDADES
# ==========================================

function Instalar-Caracteristicas {
    Write-Host "Instalando el servidor web y el servidor FTP con todas sus características..."
    Install-WindowsFeature Web-Server -IncludeAllSubFeature
    Install-WindowsFeature Web-FTP-Server -IncludeAllSubFeature
}

function Crear-Estructura-FTP {
    Write-Host "Creando estructura de carpetas base para FTP..."
    New-Item -ItemType Directory -Path C:\FTP -Force | Out-Null
    New-Item -ItemType Directory -Path C:\FTP\grupos -Force | Out-Null
    New-Item -ItemType Directory -Path C:\FTP\grupos\reprobados -Force | Out-Null
    New-Item -ItemType Directory -Path C:\FTP\grupos\recursadores -Force | Out-Null
    New-Item -ItemType Directory -Path C:\FTP\LocalUser -Force | Out-Null
    New-Item -ItemType Directory -Path C:\FTP\LocalUser\Public -Force | Out-Null
    New-Item -ItemType Directory -Path C:\FTP\LocalUser\Public\general -Force | Out-Null
}

function Crear-Sitio-FTP {
    Write-Host "Creando el sitio FTP si no existe..."
    if (-not (Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP" -Force
    } else {
        Write-Host "El sitio 'FTP' ya existe."
    }
}

function Configurar-UserIsolation {
    Write-Host "Configurando User Isolation..."
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/siteDefaults/ftpServer/userIsolation" `
        -Name "mode" -Value "IsolateAllDirectories"
}

function Crear-Grupos-Locales {
    Write-Host "Creando grupos locales..."
    $SistemaUsuarios = [ADSI]"WinNT://$env:ComputerName"

    $grupos = @("reprobados", "recursadores")
    foreach ($grupo in $grupos) {
        if (-not (Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
            $grupoObj = $SistemaUsuarios.Create("Group", $grupo)
            $grupoObj.SetInfo()
            $grupoObj.Description = "Usuarios con acceso a $grupo"
            $grupoObj.SetInfo()
            Write-Host "Grupo $grupo creado exitosamente."
        } else {
            Write-Host "El grupo $grupo ya existe."
        }
    }
}

function Crear-Usuario-FTP {
    $gruposRequeridos = @("reprobados", "recursadores")
    $gruposFaltantes = @()

    foreach ($grupo in $gruposRequeridos) {
        if (-not (Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
            $gruposFaltantes += $grupo
        }
    }

    if ($gruposFaltantes.Count -gt 0) {
        Write-Host "No se pueden crear usuarios porque faltan los siguientes grupos locales: $($gruposFaltantes -join ', ')"
        Write-Host "Ejecuta la opción 'Crear grupos locales' antes de crear usuarios." -ForegroundColor Red
        return
    }

    do {
        do {
            $nombreUsuario = Read-Host "Introduce el nombre del usuario (máximo 20 caracteres, o escribe 'salir' para terminar)"

            if ($nombreUsuario -eq "salir") { return }

            if (-not (Validar-NombreUsuario -nombreUsuario $nombreUsuario)) {
                $nombreUsuario = $null
                continue
            }

        } while (-not $nombreUsuario)

        do {
            $claveUsuario = Read-Host "Introduce la contraseña (8 caracteres, 1 mayúscula, 1 minúscula, 1 dígito y 1 carácter especial)"
            if (-not (comprobarPassword -clave $claveUsuario)) {
                Write-Host "La contraseña no cumple con los requisitos, intenta de nuevo."
            }
        } while (-not (comprobarPassword -clave $claveUsuario))

        do {
            Write-Host "Selecciona el grupo para el usuario:"
            Write-Host "1) Reprobados"
            Write-Host "2) Recursadores"
            $grupoSeleccionado = Read-Host "Elige 1 o 2"

            if ($grupoSeleccionado -eq "1") {
                $grupoFTP = "reprobados"
                $rutaGrupo = "C:\FTP\grupos\reprobados"
                break
            } elseif ($grupoSeleccionado -eq "2") {
                $grupoFTP = "recursadores"
                $rutaGrupo = "C:\FTP\grupos\recursadores"
                break
            } else {
                Write-Host "Opción inválida. Selecciona 1 o 2."
            }
        } while ($true)

        # Crear el usuario
        $securePassword = ConvertTo-SecureString -String $claveUsuario -AsPlainText -Force
        New-LocalUser -Name $nombreUsuario -Password $securePassword -Description "Usuario FTP" -AccountNeverExpires | Out-Null

        # Agregar usuario al grupo correspondiente
        Add-LocalGroupMember -Group $grupoFTP -Member $nombreUsuario

        # Crear carpetas de usuario
        $rutaUsuario = "C:\FTP\LocalUser\$nombreUsuario"
        New-Item -ItemType Directory -Path $rutaUsuario -Force | Out-Null
        New-Item -ItemType Directory -Path "$rutaUsuario\$nombreUsuario" -Force | Out-Null

        # Crear enlaces simbólicos
        Crear-Symlink "$rutaUsuario\general" "C:\FTP\LocalUser\Public\general"
        Crear-Symlink "$rutaUsuario\$grupoFTP" $rutaGrupo

        Write-Host "Usuario $nombreUsuario creado y vinculado correctamente a general y $grupoFTP."
        
        $otro = Read-Host "¿Deseas crear otro usuario? (s/n)"
        if ($otro -ne 's') { break }

    } while ($true)
}

function Crear-Symlink {
    param([string]$target, [string]$destination)
    if (Test-Path $target) { Remove-Item $target -Force }
    cmd /c mklink /D $target $destination | Out-Null
}

function Configurar-Autenticacion-Permisos {
    Write-Host "Configurando autenticación y permisos FTP..."

    Set-ItemProperty -Path "IIS:\Sites\FTP" -Name ftpServer.Security.authentication.basicAuthentication.enabled -Value $true
    Set-ItemProperty -Path "IIS:\Sites\FTP" -Name ftpServer.Security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty -Path "IIS:\Sites\FTP" -Name ftpServer.Security.authentication.anonymousAuthentication.userName -Value "IUSR"
    Set-ItemProperty -Path "IIS:\Sites\FTP" -Name ftpServer.Security.authentication.anonymousAuthentication.password -Value ""

    Clear-WebConfiguration "/system.ftpServer/security/authorization" -PSPath "IIS:\"

    Add-WebConfiguration "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Value @{
        accessType = "Allow";
        roles = "reprobados, recursadores";
        permissions = 3
    } -Location "FTP"

    Add-WebConfiguration "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Value @{
        accessType = "Allow";
        users = "IUSR";
        permissions = 1
    } -Location "FTP"
    
    Write-Host "Autenticación y permisos configurados."
}

function Configurar-TLS {
    Set-ItemProperty -Path "IIS:\Sites\FTP" -Name "ftpServer.security.ssl.controlChannelPolicy" -Value 0
    Set-ItemProperty -Path "IIS:\Sites\FTP" -Name "ftpServer.security.ssl.dataChannelPolicy" -Value 0
}

function Reiniciar-FTP {
    Restart-WebItem "IIS:\Sites\FTP"
    Write-Host "Sitio FTP reiniciado."
}

function comprobarPassword {
    param ([string]$clave)
    $regex = "^(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*[^A-Za-z0-9]).{8,16}$"
    return ($clave -match $regex)
}

function Validar-NombreUsuario {
    param ([string]$nombreUsuario)

    $nombresReservados = @("CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9")
    $caracteresInvalidos = '[<>:"/\\|?*]'

    if ([string]::IsNullOrWhiteSpace($nombreUsuario)) {
        Write-Host "El nombre de usuario no puede estar vacío."
        return $false
    }
    if ($nombreUsuario.Length -gt 20) {
        Write-Host "El nombre de usuario no puede tener más de 20 caracteres."
        return $false
    }
    if ($nombreUsuario -match $caracteresInvalidos) {
        Write-Host "El nombre de usuario contiene caracteres no permitidos (< > : "" / \ | ? *)."
        return $false
    }
    if ($nombreUsuario -match '^\s|\s$') {
        Write-Host "El nombre de usuario no puede comenzar ni terminar con un espacio."
        return $false
    }
    if ($nombreUsuario -match '\.$') {
        Write-Host "El nombre de usuario no puede terminar con un punto."
        return $false
    }
    if ($nombreUsuario -in $nombresReservados) {
        Write-Host "El nombre de usuario '$nombreUsuario' es un nombre reservado por Windows."
        return $false
    }
    if (Get-LocalUser -Name $nombreUsuario -ErrorAction SilentlyContinue) {
        Write-Host "El usuario '$nombreUsuario' ya existe."
        return $false
    }
    return $true
}

function Eliminar-Usuario-FTP {
    param ([string]$nombreUsuario, [switch]$Force)

    Write-Host "ADVERTENCIA: Asegúrate de que el usuario '$nombreUsuario' no esté conectado por FTP." -ForegroundColor Yellow

    if ([string]::IsNullOrWhiteSpace($nombreUsuario)) {
        Write-Host "ERROR: Debes proporcionar un nombre de usuario válido." -ForegroundColor Red
        return
    }

    $usuario = Get-LocalUser -Name $nombreUsuario -ErrorAction SilentlyContinue
    if (-not $usuario) {
        Write-Host "ERROR: El usuario '$nombreUsuario' no existe." -ForegroundColor Red
        return
    }

    if (-not $Force) {
        $confirmacion = Read-Host "¿Estás seguro que deseas eliminar al usuario '$nombreUsuario' y su directorio? (S/N)"
        if ($confirmacion -ne 'S') {
            Write-Host "Operación cancelada." -ForegroundColor Yellow
            return
        }
    }

    try {
        Remove-LocalUser -Name $nombreUsuario -ErrorAction Stop
        Write-Host "Usuario '$nombreUsuario' eliminado del sistema." -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: No se pudo eliminar el usuario '$nombreUsuario'. Detalle: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    $rutaUsuario = "C:\FTP\LocalUser\$nombreUsuario"

    if (Test-Path $rutaUsuario) {
        try {
            $items = Get-ChildItem -Path $rutaUsuario -Force -ErrorAction Stop
            foreach ($item in $items) {
                if ($item.LinkType -eq 'SymbolicLink') {
                    Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                }
            }
            Remove-Item -Path $rutaUsuario -Recurse -Force -ErrorAction Stop
            Write-Host "Directorio '$rutaUsuario' eliminado correctamente." -ForegroundColor Green
        }
        catch {
            Write-Host "ERROR al eliminar el directorio '$rutaUsuario': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}