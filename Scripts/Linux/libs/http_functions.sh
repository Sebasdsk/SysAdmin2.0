#!/bin/bash

# ==========================================
# FUNCIONES HTTP (Apache, Tomcat, Nginx)
# ==========================================

# Variables globales
servicio=""
version=""
puerto=""
versions=()

function Menu_HTTP() {
    while true; do
        clear
        echo "=================================="
        echo "        Instalador HTTP           "
        echo "=================================="
        echo "0. Instalar dependencias necesarias"
        echo "1. Seleccionar Servicio"
        echo "2. Seleccionar Versión"
        echo "3. Configurar Puerto"
        echo "4. Proceder con la Instalación"
        echo "5. Verificar servicios instalados"
        echo "6. Regresar al menú principal"
        echo "=================================="
        read -p "Seleccione una opción: " opcion_menu

        case $opcion_menu in
            0) 
                instalar_dependencias_http
                read -p "Presione Enter para continuar..."
                ;;
            1) 
                seleccionar_servicio
                read -p "Presione Enter para continuar..."
                ;;
            2) 
                seleccionar_version
                read -p "Presione Enter para continuar..."
                ;;
            3) 
                preguntar_puerto
                read -p "Presione Enter para continuar..."
                ;;
            4) 
                echo "=================================="
                echo "      Resumen de la instalación   "
                echo "=================================="
                echo "Servicio seleccionado: $servicio"
                echo "Versión seleccionada: $version"
                echo "Puerto configurado: $puerto"
                echo "=================================="

                read -p "¿Desea proceder con la instalación? (s/n): " confirmacion
                if [[ "$confirmacion" != "s" ]]; then
                    echo "Instalación cancelada."
                else
                    proceso_instalacion
                fi
                read -p "Presione Enter para continuar..."
                ;;
            5) 
                verificar_servicios
                read -p "Presione Enter para continuar..."
                ;;
            6) 
                return 0
                ;;
            *) 
                echo "Opción no válida. Intente de nuevo."
                read -p "Presione Enter para continuar..."
                ;;
        esac
    done
}

paquete_instalado() {
    dpkg -l | grep -qw "$1"
}

instalar_dependencias_http() {
    echo "Verificando e instalando dependencias necesarias para Apache, Tomcat y Nginx en Ubuntu..."
    sudo apt-get update -y

    # Dependencias generales
    for paquete in build-essential wget curl tar; do
        if paquete_instalado "$paquete"; then
            echo "$paquete ya está instalado."
        else
            sudo apt-get install -y "$paquete"
        fi
    done

    # Dependencias específicas de Apache
    for paquete in libapr1-dev libaprutil1-dev libpcre3 libpcre3-dev; do
        if paquete_instalado "$paquete"; then
            echo "$paquete ya está instalado."
        else
            sudo apt-get install -y "$paquete"
        fi
    done

    # Dependencias específicas de NGINX
    for paquete in libssl-dev zlib1g-dev; do
        if paquete_instalado "$paquete"; then
            echo "$paquete ya está instalado."
        else
            sudo apt-get install -y "$paquete"
        fi
    done

    # Dependencia de Tomcat (Java)
    if paquete_instalado "default-jdk"; then
        echo "default-jdk ya está instalado."
    else
        sudo apt-get install -y default-jdk
    fi

    # Configurar JAVA_HOME automáticamente si no está en /etc/environment
    if ! grep -q "JAVA_HOME" /etc/environment; then
        java_home_path=$(readlink -f $(which java) | sed "s:/bin/java::")
        echo "JAVA_HOME=\"$java_home_path\"" | sudo tee -a /etc/environment > /dev/null
        source /etc/environment
        echo "JAVA_HOME configurado automáticamente como: $JAVA_HOME"
    else
        echo "JAVA_HOME ya está configurado."
    fi

    echo "Verificación e instalación de dependencias completada."
}

seleccionar_servicio() {
    echo "Seleccione el servicio que desea instalar:"
    echo "1.- Apache"
    echo "2.- Tomcat"
    echo "3.- Nginx"
    read -p "Opción: " opcion

    case $opcion in
        1)
            servicio="Apache"
            obtener_versiones_apache
            ;;
        2)
            servicio="Tomcat"
            obtener_versiones_tomcat
            ;;
        3)
            servicio="Nginx"
            obtener_versiones_nginx
            ;;
        *)
            echo "Opción no válida. Intente de nuevo."
            ;;
    esac
}

seleccionar_version() {
    if [[ -z "$servicio" ]]; then
        echo "Debe seleccionar un servicio antes de elegir la versión."
        return
    fi

    echo "Seleccione la versión de $servicio:"
    echo "1.- Versión Estable (LTS): ${versions[0]}"
    echo "2.- Versión de Desarrollo: ${versions[1]}"
    read -p "Opción: " opcion

    case $opcion in
        1)
            version=${versions[0]}
            echo "Versión seleccionada: $version"
            ;;
        2)
            version=${versions[1]}
            echo "Versión seleccionada: $version"
            ;;
        *)
            echo "Opción no válida."
            ;;
    esac
}

es_puerto_restringido() {
    local puerto=$1
    local puertos_restringidos=(1 7 9 11 13 15 17 19 20 21 22 23 25 37 42 43 53 69 77 79 87 95 101 102 103 104 109 110 111 113 115 117 118 119 123 135 137 139 143 161 177 179 389 427 443 445 465 512 513 514 515 526 530 531 532 540 548 554 556 563 587 601 636 989 990 993 995 1723 2049 6667)

    for p in "${puertos_restringidos[@]}"; do
        if [[ "$puerto" -eq "$p" ]]; then
            return 0
        fi
    done
    return 1
}

verificar_puerto_en_uso() {
    local puerto=$1
    if ss -tuln 2>/dev/null | grep -q "LISTEN.*:$puerto "; then
        return 0
    else
        return 1
    fi
}

preguntar_puerto() {
    while true; do
        read -p "Ingrese el puerto para el servicio (debe estar entre 1 y 65535): " puerto

        if [[ "$puerto" =~ ^[0-9]+$ ]] && (( puerto >= 1 && puerto <= 65535 )); then
            if es_puerto_restringido "$puerto"; then
                echo "El puerto $puerto está en la lista de puertos restringidos. Intente con otro."
                continue
            fi

            if verificar_puerto_en_uso "$puerto"; then
                echo "El puerto $puerto está ocupado. Intente con otro."
            else
                echo "El puerto $puerto está disponible."
                break
            fi
        else
            echo "Entrada inválida. Ingrese un número de puerto entre 1 y 65535."
        fi
    done
}

habilitar_puerto_firewall() {
    local puerto=$1

    if [ -z "$puerto" ]; then
        echo "Error: No se proporcionó un puerto."
        return 1
    fi

    if command -v ufw &> /dev/null; then
        if sudo ufw status | grep -q "$puerto"; then
            echo "El puerto $puerto ya está permitido en el firewall (UFW)."
        else
            sudo ufw allow "$puerto"/tcp
            echo "El puerto $puerto ha sido habilitado en el firewall (UFW)."
        fi
    elif command -v firewall-cmd &> /dev/null; then
        if sudo firewall-cmd --list-ports | grep -q "$puerto/tcp"; then
            echo "El puerto $puerto ya está permitido en el firewall (firewalld)."
        else
            sudo firewall-cmd --add-port="$puerto"/tcp --permanent
            sudo firewall-cmd --reload
            echo "El puerto $puerto ha sido habilitado en el firewall (firewalld)."
        fi
    else
        echo "No se encontró un gestor de firewall compatible (UFW o firewalld)."
        return 1
    fi
}

comando_existente() {
    command -v "$1" > /dev/null 2>&1
}

proceso_instalacion() {
    if [[ -z "$servicio" || -z "$version" || -z "$puerto" ]]; then
        echo "Debe seleccionar el servicio, la versión y el puerto antes de proceder con la instalación."
        return
    fi

    if ! comando_existente "gcc" || ! comando_existente "make" || ! comando_existente "wget" || ! comando_existente "curl"; then
        echo "Faltan dependencias esenciales para la instalación."
        echo "Por favor, ejecute la opción 0 del menú antes de continuar."
        return 1
    fi

    echo "Iniciando instalación silenciosa de $servicio versión $version en el puerto $puerto..."

    case $servicio in
        "Apache") instalar_apache ;;
        "Tomcat") instalar_tomcat ;;
        "Nginx") instalar_nginx ;;
        *) echo "Servicio desconocido."; return 1 ;;
    esac

    echo "Instalación completada para $servicio versión $version en el puerto $puerto."

    unset servicio
    unset version
    unset puerto
}

instalar_apache() {
    echo "Descargando e instalando Apache versión $version..."
    wget -q "https://downloads.apache.org/httpd/httpd-$version.tar.gz" -O "/tmp/httpd-$version.tar.gz"
    tar -xzf "/tmp/httpd-$version.tar.gz" -C /tmp
    cd "/tmp/httpd-$version" || exit 1

    ./configure --prefix=/usr/local/apache2 --enable-so > /dev/null
    make > /dev/null
    sudo make install > /dev/null

    sudo sed -i "s/Listen 80/Listen $puerto/" /usr/local/apache2/conf/httpd.conf
    /usr/local/apache2/bin/apachectl start
    habilitar_puerto_firewall "$puerto"

    cat <<EOF | sudo tee /usr/local/apache2/htdocs/index.html > /dev/null
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>PERO QUE DISTINGUIDO PEDRI</title>
    <style>body {text-align: center; background-color: #004c98; color: white;} img {width: 300px; margin: 0 20px;}</style>
</head>
<body>
    <h1>PERO QUE DISTINGUIDO PEDRI</h1>
    <marquee behavior="scroll" direction="left" scrollamount="10">
        <img src="https://upload.wikimedia.org/wikipedia/en/4/47/FC_Barcelona_%28crest%29.svg">
    </marquee>
</body>
</html>
EOF
}

instalar_tomcat() {
    echo "Descargando e instalando Tomcat versión $version..."
    mayor=$(echo "$version" | cut -d'.' -f1)
    url="https://dlcdn.apache.org/tomcat/tomcat-$mayor/v$version/bin/apache-tomcat-$version.tar.gz"

    wget -q "$url" -O "/tmp/tomcat-$version.tar.gz"
    if [[ -d "/opt/tomcat" ]]; then sudo rm -rf /opt/tomcat; fi
    sudo mkdir -p /opt/tomcat
    sudo tar -xzf "/tmp/tomcat-$version.tar.gz" -C /opt/tomcat --strip-components=1

    sudo sed -i "s/Connector port=\"8080\"/Connector port=\"$puerto\"/" /opt/tomcat/conf/server.xml
    /opt/tomcat/bin/startup.sh
    habilitar_puerto_firewall "$puerto"
}

instalar_nginx() {
    echo "Descargando e instalando NGINX versión $version..."
    wget -q "https://nginx.org/download/nginx-$version.tar.gz" -O "/tmp/nginx-$version.tar.gz"
    if [[ -d "/usr/local/nginx" ]]; then sudo rm -rf /usr/local/nginx; fi
    
    tar -xzf "/tmp/nginx-$version.tar.gz" -C /tmp
    cd "/tmp/nginx-$version" || exit 1

    ./configure --prefix=/usr/local/nginx > /dev/null
    make > /dev/null
    sudo make install > /dev/null

    sudo sed -i "s/listen       80;/listen       $puerto;/" /usr/local/nginx/conf/nginx.conf
    /usr/local/nginx/sbin/nginx
    habilitar_puerto_firewall "$puerto"
}

obtener_versiones_apache() {
    html=$(curl -s "https://httpd.apache.org/download.cgi")
    versions_raw=$(echo "$html" | grep -oP 'httpd-\d+\.\d+\.\d+' | sed 's/httpd-//')
    version_lts=$(echo "$versions_raw" | grep '^2\.4' | head -n 1)
    version_dev=$(echo "$versions_raw" | grep '^2\.5' | head -n 1)
    [[ -z "$version_dev" ]] && version_dev="No disponible"
    versions=("$version_lts" "$version_dev")
}

obtener_urls_tomcat() {
    html=$(curl -s "https://tomcat.apache.org/index.html")
    urls=$(echo "$html" | grep -oP 'https://tomcat.apache.org/download-\d+\.cgi')
    tomcat_url_lts=""
    tomcat_url_dev=""

    while read -r url; do
        version_number=$(echo "$url" | grep -oP '\d+')
        if [[ "$version_number" -lt 11 ]]; then tomcat_url_lts="$url"; fi
        if [[ "$version_number" -eq 11 ]]; then tomcat_url_dev="$url"; fi
    done <<< "$urls"
}

obtener_versiones_tomcat() {
    obtener_urls_tomcat
    html_lts=$(curl -s "$tomcat_url_lts")
    version_lts=$(echo "$html_lts" | grep -oP 'v\d+\.\d+\.\d+' | head -n 1 | sed 's/v//')
    html_dev=$(curl -s "$tomcat_url_dev")
    version_dev=$(echo "$html_dev" | grep -oP 'v\d+\.\d+\.\d+' | head -n 1 | sed 's/v//')
    versions=("$version_lts" "$version_dev")
}

obtener_versiones_nginx() {
    html=$(curl -s "https://nginx.org/en/download.html")
    version_mainline=$(echo "$html" | grep -A5 "Mainline version" | grep -oP 'nginx-\d+\.\d+\.\d+' | head -n1 | sed 's/nginx-//')
    mainline_major_minor=$(echo "$version_mainline" | cut -d '.' -f1,2)
    version_stable=$(echo "$html" | grep -A5 "Stable version" | grep -oP 'nginx-\d+\.\d+\.\d+' | grep -v "${mainline_major_minor}\." | head -n1 | sed 's/nginx-//')
    versions=("$version_stable" "$version_mainline")
}

verificar_servicios() {
    echo -e "\n=================================="
    echo "   Verificando servicios HTTP    "
    echo "=================================="

    if [[ -f "/usr/local/apache2/bin/httpd" || -f "/usr/sbin/apache2" || -f "/usr/sbin/httpd" ]]; then
        echo "Apache está instalado"
        apache_version=$(/usr/local/apache2/bin/httpd -v 2>/dev/null | grep "Server version" | awk '{print $3}')
        [[ -z "$apache_version" ]] && apache_version=$(/usr/sbin/apache2 -v 2>/dev/null | grep "Server version" | awk '{print $3}')
        apache_puertos=$(sudo ss -tlnp | grep httpd | awk '{print $4}' | grep -oE '[0-9]+$' | tr '\n' ', ')
        echo "   Versión: ${apache_version:-No encontrada}"
        echo "   Puertos: ${apache_puertos%, }"
    fi

    if [[ -f "/usr/local/nginx/sbin/nginx" || -f "/usr/sbin/nginx" || -f "/usr/local/sbin/nginx" ]]; then
        echo "Nginx está instalado"
        nginx_version=$(/usr/local/nginx/sbin/nginx -v 2>&1 | awk -F/ '{print $2}')
        [[ -z "$nginx_version" ]] && nginx_version=$(/usr/sbin/nginx -v 2>&1 | awk -F/ '{print $2}')
        nginx_puertos=$(sudo ss -tlnp | grep -E 'nginx|/usr/local/nginx/sbin/nginx' | awk '{print $4}' | grep -oE '[0-9]+$' | tr '\n' ', ')
        echo "   Versión: ${nginx_version:-No encontrada}"
        echo "   Puertos: ${nginx_puertos%, }"
    fi

    if [[ -d "/opt/tomcat" || -d "/usr/local/tomcat" ]]; then
        echo "Tomcat está instalado"
        tomcat_version=$(/opt/tomcat/bin/version.sh 2>/dev/null | grep "Server number" | awk '{print $3}')
        tomcat_puertos=$(sudo ss -tlnp | grep java | awk '{print $4}' | grep -oE '[0-9]+$' | tr '\n' ', ')
        echo "   Versión: ${tomcat_version:-No encontrada}"
        echo "   Puertos: ${tomcat_puertos%, }"
    fi
}