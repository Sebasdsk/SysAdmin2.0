# ==========================================
# FUNCIONES HTTP (IIS, Apache, Tomcat)
# ==========================================

$global:servicio = ""
$global:version = ""
$global:puerto = ""
$global:versions = @()

function Show-HttpMenu {
    while ($true) {
        Clear-Host
        Write-Host "=================================="
        Write-Host "        Instalador HTTP           "
        Write-Host "=================================="
        Write-Host "0. Instalar dependencias necesarias"
        Write-Host "1. Seleccionar Servicio"
        Write-Host "2. Seleccionar Versión"
        Write-Host "3. Configurar Puerto"
        Write-Host "4. Proceder con la Instalación"
        Write-Host "5. Regresar al menú principal"
        Write-Host "=================================="
        $opcion_menu = Read-Host "Seleccione una opción"

        switch ($opcion_menu) {
            "0" { Install-HttpDependencies; Read-Host "Presione Enter para continuar..." }
            "1" { seleccionar_servicio; Read-Host "Presione Enter para continuar..." }
            "2" { seleccionar_version; Read-Host "Presione Enter para continuar..." }
            "3" { preguntar_puerto; Read-Host "Presione Enter para continuar..." }
            "4" {
                Write-Host "=================================="
                Write-Host "      Resumen de la instalación   "
                Write-Host "=================================="
                Write-Host "Servicio seleccionado: $global:servicio"
                Write-Host "Versión seleccionada: $global:version"
                Write-Host "Puerto configurado: $global:puerto"
                Write-Host "=================================="
                $confirmacion = Read-Host "¿Desea proceder con la instalación? (s/n)"
                if ($confirmacion -eq "s") {
                    proceso_instalacion
                } else {
                    Write-Host "Instalación cancelada."
                }
                Read-Host "Presione Enter para continuar..."
            }
            "5" { return }
            default { Write-Host "Opción no válida."; Read-Host "Presione Enter para continuar..." }
        }
    }
}

function Install-HttpDependencies {
    Write-Host "`n============================================"
    Write-Host "   Verificando e instalando dependencias...   "
    Write-Host "============================================"

    $vcInstalled = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" | 
                   Get-ItemProperty | 
                   Where-Object { $_.DisplayName -match "Visual C\+\+ (2015|2017|2019|2022) Redistributable" }

    if ($vcInstalled) {
        Write-Host "Visual C++ Redistributable ya está instalado."
    } else {
        Write-Host "Falta Visual C++. Descargando e instalando..."
        $vcUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
        $vcInstaller = "$env:TEMP\vc_redist.x64.exe"
        Invoke-WebRequest -Uri $vcUrl -OutFile $vcInstaller
        Start-Process -FilePath $vcInstaller -ArgumentList "/install /quiet /norestart" -NoNewWindow -Wait
        Write-Host "Visual C++ instalado."
    }

    $jdkBasePath = "C:\Java"
    $jdkInstallPath = Get-ChildItem -Path $jdkBasePath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^jdk21.*" } | Select-Object -ExpandProperty FullName -First 1

    if ($jdkInstallPath -and (Test-Path "$jdkInstallPath\bin\java.exe")) {
        Write-Host "Amazon Corretto JDK 21 ya está instalado en: $jdkInstallPath"
    } else {
        Write-Host "Falta JDK 21. Descargando e instalando..."
        $jdkUrl = "https://corretto.aws/downloads/latest/amazon-corretto-21-x64-windows-jdk.zip"
        $jdkZipPath = "$env:TEMP\Corretto21.zip"
        Invoke-WebRequest -Uri $jdkUrl -OutFile $jdkZipPath
        if (-Not (Test-Path $jdkBasePath)) { New-Item -ItemType Directory -Path $jdkBasePath | Out-Null }
        Expand-Archive -Path $jdkZipPath -DestinationPath $jdkBasePath -Force
        Remove-Item -Path $jdkZipPath -Force
        $jdkInstallPath = Get-ChildItem -Path $jdkBasePath -Directory | Where-Object { $_.Name -match "^jdk21.*" } | Select-Object -ExpandProperty FullName -First 1
    }

    [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkInstallPath, [System.EnvironmentVariableTarget]::Machine)
    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
    if ($currentPath -notlike "*$jdkInstallPath\bin*") {
        $newPath = "$currentPath;$jdkInstallPath\bin"
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, [System.EnvironmentVariableTarget]::Machine)
    }
    $env:JAVA_HOME = $jdkInstallPath
    $env:Path = "$env:Path;$jdkInstallPath\bin"
    Write-Host "JAVA_HOME configurado en: $env:JAVA_HOME"
}

function seleccionar_servicio {
    Write-Host "Seleccione el servicio que desea instalar:"
    Write-Host "1.- IIS"
    Write-Host "2.- Apache"
    Write-Host "3.- Tomcat"
    $opcion = Read-Host "Opción"

    switch ($opcion) {
        "1" { $global:servicio = "IIS"; obtener_versiones_IIS }
        "2" { $global:servicio = "Apache"; obtener_versiones_apache }
        "3" { $global:servicio = "Tomcat"; obtener_versiones_tomcat }
        default { Write-Host "Opción no válida."; seleccionar_servicio }
    }
}

function obtener_versiones_IIS {
    $iisVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).MajorVersion
    if ($iisVersion) {
        $global:version = "IIS $iisVersion.0"
    } else {
        $global:version = "IIS 10.0 (Versión predeterminada)"
    }
}

function obtener_versiones_apache {
    $html = Invoke-WebRequest -Uri "https://httpd.apache.org/download.cgi" -UseBasicParsing
    $versionsRaw = [regex]::Matches($html.Content, "httpd-(\d+\.\d+\.\d+)") | ForEach-Object { $_.Groups[1].Value }
    $versionLTS = ($versionsRaw | Where-Object { $_ -match "^2\.4\.\d+$" } | Select-Object -First 1)
    $versionDev = ($versionsRaw | Where-Object { $_ -match "^2\.5\.\d+$" } | Select-Object -First 1)
    if (-not $versionDev) { $versionDev = "No disponible" }
    $global:versions = @($versionLTS, $versionDev)
}

function obtener_versiones_tomcat {
    $html = Invoke-WebRequest -Uri "https://tomcat.apache.org/index.html" -UseBasicParsing
    $urls = [regex]::Matches($html.Content, "https://tomcat.apache.org/download-(\d+)\.cgi") | ForEach-Object { $_.Value }
    foreach ($url in $urls) {
        $v = [regex]::Match($url, "\d+").Value
        if ([int]$v -lt 11) { $global:tomcat_url_lts = $url }
        if ([int]$v -eq 11) { $global:tomcat_url_dev = $url }
    }
    $htmlLTS = Invoke-WebRequest -Uri $global:tomcat_url_lts -UseBasicParsing
    $versionLTS = [regex]::Match($htmlLTS.Content, "v(\d+\.\d+\.\d+)").Groups[1].Value
    $htmlDev = Invoke-WebRequest -Uri $global:tomcat_url_dev -UseBasicParsing
    $versionDev = [regex]::Match($htmlDev.Content, "v(\d+\.\d+\.\d+)").Groups[1].Value
    $global:versions = @($versionLTS, $versionDev)
}

function seleccionar_version {
    if ($global:servicio -eq "IIS") { $global:version = "IIS (Predeterminada)"; return }
    if ($global:servicio -eq "Apache") { $global:version = "2.4.63"; return }

    Write-Host "1.- Versión Estable (LTS): $($global:versions[0])"
    Write-Host "2.- Versión de Desarrollo: $($global:versions[1])"
    $opcion = Read-Host "Opción"
    if ($opcion -eq "1") { $global:version = $global:versions[0] } else { $global:version = $global:versions[1] }
}

function preguntar_puerto {
    while ($true) {
        $puerto = Read-Host "Ingrese el puerto para el servicio"
        if ($puerto -match "^\d+$" -and [int]$puerto -ge 1 -and [int]$puerto -le 65535) {
            $global:puerto = $puerto
            break
        }
    }
}

function habilitar_puerto_firewall {
    $reglaExistente = Get-NetFirewallRule | Where-Object { $_.DisplayName -eq "Puerto $global:puerto" }
    if (-not $reglaExistente) {
        New-NetFirewallRule -DisplayName "Puerto $global:puerto" -Direction Inbound -Protocol TCP -LocalPort $global:puerto -Action Allow | Out-Null
    }
}

function proceso_instalacion {
    switch ($global:servicio) {
        "IIS" {
            Install-WindowsFeature -Name Web-Server -IncludeAllSubFeature -ErrorAction Stop
            Set-Service -Name W3SVC -StartupType Automatic
            New-WebBinding -Name "Default Web Site" -Protocol "http" -IPAddress "*" -Port $global:puerto
            Restart-Service W3SVC
            habilitar_puerto_firewall
        }
        "Apache" {
            $url = "https://www.apachelounge.com/download/VS17/binaries/httpd-$global:version-250207-win64-VS17.zip"
            $destinoZip = "$env:USERPROFILE\Downloads\apache-$global:version.zip"
            Invoke-WebRequest -Uri $url -OutFile $destinoZip -UseBasicParsing
            Expand-Archive -Path $destinoZip -DestinationPath "C:\" -Force
            (Get-Content "C:\Apache24\conf\httpd.conf") -replace "Listen 80", "Listen $global:puerto" | Set-Content "C:\Apache24\conf\httpd.conf"
            Start-Process -FilePath "C:\Apache24\bin\httpd.exe" -ArgumentList '-k', 'install', '-n', 'Apache24' -NoNewWindow -Wait
            Start-Service -Name "Apache24"
            habilitar_puerto_firewall
        }
        "Tomcat" {
            $majorVersion = ($global:version -split "\.")[0]
            $url = "https://dlcdn.apache.org/tomcat/tomcat-${majorVersion}/v$global:version/bin/apache-tomcat-$global:version-windows-x64.zip"
            $destinoZip = "$env:USERPROFILE\Downloads\tomcat-$global:version.zip"
            Invoke-WebRequest -Uri $url -OutFile $destinoZip -UseBasicParsing
            Expand-Archive -Path $destinoZip -DestinationPath "C:\" -Force
            $subcarpeta = Get-ChildItem -Path "C:\" | Where-Object { $_.PSIsContainer -and $_.Name -match "apache-tomcat-" }
            Rename-Item -Path $subcarpeta.FullName -NewName "Tomcat"
            (Get-Content "C:\Tomcat\conf\server.xml") -replace 'Connector port="8080"', "Connector port=`"$global:puerto`"" | Set-Content "C:\Tomcat\conf\server.xml"
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"C:\Tomcat\bin\service.bat`" install" -WorkingDirectory "C:\Tomcat\bin" -NoNewWindow -Wait
            Start-Service -Name "Tomcat$majorVersion"
            habilitar_puerto_firewall
        }
    }
    $global:servicio = $null; $global:version = $null; $global:puerto = $null
}