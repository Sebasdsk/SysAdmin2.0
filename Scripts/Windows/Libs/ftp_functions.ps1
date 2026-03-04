# ==========================================
# FUNCIONES FTP (WINDOWS IIS)
# ==========================================

function Show-FtpMenu {
    while ($true) {
        Clear-Host
        Write-Host "          MENÚ FTP (IIS)         "
        Write-Host "1. Instalar Rol FTP Server"
        Write-Host "2. Configurar Sitio y Grupos"
        Write-Host "3. Crear/Gestionar Usuarios"
        Write-Host "4. Regresar al menú principal"
        
        $opcion = Read-Host "Opción"

        switch ($opcion) {
            '1' { Install-FtpRole; Pause }
            '2' { Configure-FtpSite; Pause }
            '3' { Manage-FtpUsers; Pause }
            '4' { return } 
            Default { Write-Host "Opción no válida." }
        }
    }
}

function Install-FtpRole {
    Write-Host "--- Verificando Rol FTP ---"
    $ftp = Get-WindowsFeature -Name Web-Ftp-Server
    if ($ftp.Installed) {
        Write-Host "El servicio FTP ya está instalado."
    } else {
        Write-Host "Instalando IIS y Servicio FTP..."
        Install-WindowsFeature -Name Web-Ftp-Server -IncludeManagementTools
        Install-WindowsFeature -Name Web-Ftp-Ext # Extensibilidad para autenticación custom si fuera necesario
    }
}

function Configure-FtpSite {
    Import-Module WebAdministration
    $FtpRoot = "C:\inetpub\ftproot"
    $PhysicalRoot = "C:\FTP_DATA"

    # 1. Crear Grupos Locales
    foreach ($grp in @("reprobados", "recursadores")) {
        if (-not (Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $grp -Description "Grupo FTP $grp" | Out-Null
            Write-Host "Grupo $grp creado."
        }
    }

    # 2. Crear Estructura Física Real (Donde se guardan los datos)
    New-Item -Path "$PhysicalRoot\General" -ItemType Directory -Force | Out-Null
    New-Item -Path "$PhysicalRoot\Reprobados" -ItemType Directory -Force | Out-Null
    New-Item -Path "$PhysicalRoot\Recursadores" -ItemType Directory -Force | Out-Null

    # 3. Configurar Permisos NTFS en carpetas físicas
    # General: Todos leen, Grupos escriben
    $Acl = Get-Acl "$PhysicalRoot\General"
    # Regla: Reprobados Modify
    $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("reprobados", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $Acl.SetAccessRule($Ar)
    # Regla: Recursadores Modify
    $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("recursadores", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $Acl.SetAccessRule($Ar)
    # Regla: IUSR (Anonimo IIS) ReadAndExecute
    $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("IUSR", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    $Acl.SetAccessRule($Ar)
    Set-Acl "$PhysicalRoot\General" $Acl

    # Carpetas de Grupo
    foreach ($grp in @("reprobados", "recursadores")) {
        $path = "$PhysicalRoot\$grp"
        $Acl = Get-Acl $path
        # Reset herencia para ser estrictos
        $Acl.SetAccessRuleProtection($true, $false) 
        # Admin Full
        $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("Administradores", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.SetAccessRule($Ar)
        # Grupo Especifico Modify
        $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($grp, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.SetAccessRule($Ar)
        Set-Acl $path $Acl
    }

    # 4. Crear Sitio FTP con Aislamiento de Usuario (User Isolation)
    # Usamos "LocalUser" isolation mode. Esto requiere que la raiz sea C:\inetpub\ftproot\LocalUser\Public
    
    if (Test-Path "IIS:\Sites\SitioFTP") {
        Write-Host "El SitioFTP ya existe. Reiniciando configuración..."
        Remove-WebSite -Name "SitioFTP"
    }

    # Crear carpeta raiz de aislamiento
    New-Item -Path "$FtpRoot\LocalUser\Public" -ItemType Directory -Force | Out-Null

    # Crear el sitio
    New-WebFtpSite -Name "SitioFTP" -Port 21 -PhysicalPath $FtpRoot -Force
    
    # Habilitar autenticación anónima y básica
    Set-ItemProperty "IIS:\Sites\SitioFTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\SitioFTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    
    # Configurar Aislamiento de Usuario (Modo: Directorio de nombre de usuario)
    Set-ItemProperty "IIS:\Sites\SitioFTP" -Name ftpServer.userIsolation.mode -Value "Directory"

    # Permisos de autorización FTP (IIS)
    Add-WebConfiguration -Filter /system.ftpServer/security/authorization -Value @{accessType="Allow"; users="*"; permissions="Read,Write"} -PSPath "IIS:\Sites\SitioFTP"

    # Enlace virtual para el usuario Anónimo (Public) hacia General
    # En IIS User Isolation, "Anonymous" cae en "LocalUser\Public"
    # Borramos la carpeta física Public creada arriba y hacemos un Link
    Remove-Item "$FtpRoot\LocalUser\Public" -Force -Recurse
    New-Item -Path "$FtpRoot\LocalUser\Public" -ItemType Junction -Value "$PhysicalRoot\General" | Out-Null

    Write-Host "Sitio FTP Configurado. Modo Aislamiento de Usuario activo."
}

function Manage-FtpUsers {
    $FtpRoot = "C:\inetpub\ftproot"
    $PhysicalRoot = "C:\FTP_DATA"

    Write-Host "1. Crear Nuevo Usuario"
    Write-Host "2. Cambiar Grupo de Usuario"
    $sel = Read-Host "Opcion"

    if ($sel -eq '1') {
        $n = Read-Host "¿Cuantos usuarios?"
        1..$n | ForEach-Object {
            $u = Read-Host "Nombre Usuario"
            $p = Read-Host "Password" -AsSecureString
            $gOpt = Read-Host "Grupo (1: reprobados, 2: recursadores)"
            $grp = if ($gOpt -eq '1') { "reprobados" } else { "recursadores" }

            # Crear Usuario Windows
            if (-not (Get-LocalUser -Name $u -ErrorAction SilentlyContinue)) {
                New-LocalUser -Name $u -Password $p -PasswordNeverExpires -Description "FTP User" | Out-Null
            }
            Add-LocalGroupMember -Group $grp -Member $u

            # ESTRUCTURA DE DIRECTORIOS (User Isolation Logic)
            # IIS busca C:\inetpub\ftproot\LocalUser\<Usuario>
            $UserRoot = "$FtpRoot\LocalUser\$u"
            New-Item -Path $UserRoot -ItemType Directory -Force | Out-Null

            # 1. Crear Carpeta Personal REAL dentro de su root
            New-Item -Path "$UserRoot\$u" -ItemType Directory -Force | Out-Null
            # Permisos NTFS: Solo usuario y admin
            $Acl = Get-Acl "$UserRoot\$u"
            $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($u, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
            $Acl.SetAccessRule($Ar)
            Set-Acl "$UserRoot\$u" $Acl

            # 2. Crear JUNCTIONS (Enlaces) a las carpetas compartidas
            # Esto hace que aparezcan como carpetas normales al entrar
            New-Item -Path "$UserRoot\general" -ItemType Junction -Value "$PhysicalRoot\General" -Force | Out-Null
            New-Item -Path "$UserRoot\$grp" -ItemType Junction -Value "$PhysicalRoot\$grp" -Force | Out-Null

            Write-Host "Usuario $u creado con estructura: /$u, /general, /$grp"
        }
    } elseif ($sel -eq '2') {
        $u = Read-Host "Usuario a modificar"
        # Detectar grupo actual (simple check)
        $isRep = Get-LocalGroupMember -Group "reprobados" | Where-Object Name -like "*$u"
        
        if ($isRep) {
            $old = "reprobados"; $new = "recursadores"
        } else {
            $old = "recursadores"; $new = "reprobados"
        }

        $conf = Read-Host "Cambiar de $old a $new? (s/n)"
        if ($conf -eq 's') {
            Remove-LocalGroupMember -Group $old -Member $u
            Add-LocalGroupMember -Group $new -Member $u
            
            # Actualizar Junctions
            $UserRoot = "$FtpRoot\LocalUser\$u"
            Remove-Item "$UserRoot\$old" -Force -ErrorAction SilentlyContinue
            New-Item -Path "$UserRoot\$new" -ItemType Junction -Value "$PhysicalRoot\$new" -Force | Out-Null
            
            Write-Host "Grupo y carpetas actualizados."
        }
    }
}