#!/bin/bash

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: Este script debe ejecutarse como root o con sudo"
   echo "Uso: sudo $0"
   exit 1
fi

################################################################################
# FUNCIONES DE VALIDACION
################################################################################

# Validar formato IPv4
validar_ipv4() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octetos <<< "$ip"
        [[ ${octetos[0]} -le 255 && ${octetos[1]} -le 255 && \
           ${octetos[2]} -le 255 && ${octetos[3]} -le 255 ]]
        return $?
    fi
    return 1
}

# Validar mascara de subred
validar_mascara() {
    local mascara=$1
    local mascaras_validas=(
        "255.0.0.0" "255.255.0.0" "255.255.255.0" 
        "255.255.255.128" "255.255.255.192" "255.255.255.224"
        "255.255.255.240" "255.255.255.248" "255.255.255.252"
    )
    
    for valida in "${mascaras_validas[@]}"; do
        if [[ "$mascara" == "$valida" ]]; then
            return 0
        fi
    done
    return 1
}

# Validar rango de IPs
validar_rango() {
    local ip_inicio=$1
    local ip_fin=$2
    
    local inicio_num=$(echo $ip_inicio | awk -F. '{print ($1 * 256^3) + ($2 * 256^2) + ($3 * 256) + $4}')
    local fin_num=$(echo $ip_fin | awk -F. '{print ($1 * 256^3) + ($2 * 256^2) + ($3 * 256) + $4}')
    
    [[ $inicio_num -lt $fin_num ]]
}

################################################################################
# FUNCIONES PRINCIPALES
################################################################################

# Verificar si DHCP esta instalado (Idempotencia)
verificar_dhcp_instalado() {
    dpkg -l | grep -q "^ii.*isc-dhcp-server"
}

# Verificar si el servicio esta activo
verificar_dhcp_activo() {
    systemctl is-active --quiet isc-dhcp-server
}

# Instalar servidor DHCP
instalar_dhcp() {
    echo "=== Instalacion del Servidor DHCP ==="
    echo ""
    
    if verificar_dhcp_instalado; then
        echo "El servidor DHCP ya esta instalado."
        return 0
    fi
    
    echo "Actualizando repositorios..."
    apt-get update -qq
    
    echo "Instalando isc-dhcp-server..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server > /dev/null 2>&1
    
    if verificar_dhcp_instalado; then
        echo "Servidor DHCP instalado correctamente."
        return 0
    else
        echo "ERROR: No se pudo instalar el servidor DHCP."
        return 1
    fi
}

# Configurar IP estatica persistente con Netplan
configurar_ip_estatica() {
    local ip=$1
    local mascara=$2
    local gateway=$3
    local dns=$4
    local interfaz=$5
    
    echo "=== Configuracion de IP Estatica ==="
    echo ""
    
    # Calcular prefix length desde mascara
    local prefix=$(echo $mascara | awk -F. '{
        split($0, octetos, ".")
        bits=0
        for (i in octetos) {
            mask = octetos[i]
            while (mask > 0) {
                bits += mask % 2
                mask = int(mask / 2)
            }
        }
        print bits
    }')
    
    # Crear archivo netplan
    local netplan_file="/etc/netplan/01-dhcp-server.yaml"
    
    echo "Creando configuracion Netplan en $netplan_file"
    
    cat > "$netplan_file" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${interfaz}:
      dhcp4: no
      addresses:
        - ${ip}/${prefix}
      routes:
        - to: default
          via: ${gateway}
      nameservers:
        addresses:
          - ${dns}
EOF
    
    echo "Aplicando configuracion de red..."
    if netplan apply 2>/dev/null; then
        echo "IP estatica configurada: $ip"
        echo "Configuracion persistente (sobrevive a reinicios)"
    else
        echo "Advertencia: Error al aplicar Netplan"
        echo "Aplicando configuracion temporal..."
        ifconfig $interfaz $ip netmask $mascara
        route add default gw $gateway 2>/dev/null
        echo "nameserver $dns" > /etc/resolv.conf
        echo "Nota: Esta configuracion se perdera al reiniciar"
    fi
}

# Configurar interfaz en archivo default
configurar_interfaz() {
    local interfaz=$1
    
    echo "Configurando interfaz $interfaz en /etc/default/isc-dhcp-server"
    
    # Backup si no existe
    if [[ ! -f /etc/default/isc-dhcp-server.backup ]]; then
        cp /etc/default/isc-dhcp-server /etc/default/isc-dhcp-server.backup
    fi
    
    if grep -q "^INTERFACESv4=" /etc/default/isc-dhcp-server; then
        sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$interfaz\"/" /etc/default/isc-dhcp-server
    else
        echo "INTERFACESv4=\"$interfaz\"" >> /etc/default/isc-dhcp-server
    fi
    
    echo "Interfaz configurada."
}

# Generar archivo de configuracion DHCP
generar_configuracion_dhcp() {
    local network_id=$1
    local mascara=$2
    local rango_inicio=$3
    local rango_fin=$4
    local gateway=$5
    local dns=$6
    local lease_time=$7
    
    echo "=== Generacion de Configuracion DHCP ==="
    echo ""
    
    # Backup si existe
    if [[ -f /etc/dhcp/dhcpd.conf ]] && [[ ! -f /etc/dhcp/dhcpd.conf.backup ]]; then
        cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.backup
        echo "Backup creado: /etc/dhcp/dhcpd.conf.backup"
    fi
    
    # Calcular broadcast address
    local broadcast=$(echo $network_id | awk -F. '{print $1"."$2"."$3".255"}')
    
    cat > /etc/dhcp/dhcpd.conf << EOF
# Configuracion del Servidor DHCP
# Generado automaticamente
# Fecha: $(date)

# Tiempo de concesion por defecto
default-lease-time ${lease_time};

# Tiempo maximo de concesion
max-lease-time $((lease_time * 2));

# Este servidor es autoritativo para la red
authoritative;

# Configuracion de logging
log-facility local7;

# Definicion de la subred
subnet ${network_id} netmask ${mascara} {
    # Rango de direcciones IP disponibles
    range ${rango_inicio} ${rango_fin};
    
    # Opcion 3: Router/Gateway
    option routers ${gateway};
    
    # Opcion 6: Servidores DNS
    option domain-name-servers ${dns};
    
    # Direccion de broadcast
    option broadcast-address ${broadcast};
    
    # Mascara de subred
    option subnet-mask ${mascara};
}
EOF
    
    echo "Archivo de configuracion generado: /etc/dhcp/dhcpd.conf"
    
    # Validar sintaxis
    echo ""
    echo "Validando sintaxis del archivo de configuracion..."
    if dhcpd -t -cf /etc/dhcp/dhcpd.conf 2>/dev/null; then
        echo "Sintaxis del archivo correcta."
        return 0
    else
        echo "ERROR: Error en la sintaxis del archivo."
        echo "Ejecute 'dhcpd -t' para ver detalles del error."
        return 1
    fi
}

################################################################################
# FUNCIONES DE MONITOREO Y DIAGNOSTICO
################################################################################

# Mostrar estado del servicio
mostrar_estado() {
    echo "=== Estado del Servicio DHCP ==="
    echo ""
    
    if verificar_dhcp_activo; then
        echo "Estado: ACTIVO"
    else
        echo "Estado: INACTIVO"
    fi
    
    echo ""
    systemctl status isc-dhcp-server --no-pager | head -n 20
}

# Listar concesiones activas
mostrar_concesiones() {
    echo "=== Concesiones DHCP Activas ==="
    echo ""
    
    if [[ ! -f /var/lib/dhcp/dhcpd.leases ]]; then
        echo "No se encontro el archivo de concesiones."
        return 1
    fi
    
    local total=$(grep -c "^lease" /var/lib/dhcp/dhcpd.leases)
    echo "Total de concesiones registradas: $total"
    echo ""
    
    if [[ $total -eq 0 ]]; then
        echo "No hay concesiones activas en este momento."
        return 0
    fi
    
    echo "IP Address        MAC Address         Hostname            Expira"
    echo "--------------------------------------------------------------------------------"
    
    awk '
    /^lease/ {
        ip = $2
        mac = ""
        hostname = ""
        expire = ""
        getline; while ($0 !~ /^}/) {
            if ($1 == "hardware") mac = $3
            if ($1 == "client-hostname") hostname = $2
            if ($1 == "ends") {
                expire = $3" "$4
                gsub(/[";]/, "", expire)
            }
            getline
        }
        gsub(/[";]/, "", hostname)
        gsub(/;/, "", mac)
        if (hostname == "") hostname = "-"
        printf "%-18s%-20s%-20s%s\n", ip, mac, hostname, expire
    }
    ' /var/lib/dhcp/dhcpd.leases | tail -n 20
}

# Mostrar configuracion actual
mostrar_configuracion() {
    echo "=== Configuracion Actual del Servidor DHCP ==="
    echo ""
    
    if [[ ! -f /etc/dhcp/dhcpd.conf ]]; then
        echo "No se encontro el archivo de configuracion."
        return 1
    fi
    
    echo "Archivo: /etc/dhcp/dhcpd.conf"
    echo ""
    grep -v "^#" /etc/dhcp/dhcpd.conf | grep -v "^$"
}

# Mostrar logs recientes
mostrar_logs() {
    echo "=== Logs Recientes del Servidor DHCP ==="
    echo ""
    
    if command -v journalctl &> /dev/null; then
        journalctl -u isc-dhcp-server -n 30 --no-pager
    else
        tail -n 30 /var/log/syslog | grep dhcpd
    fi
}

# Menu de monitoreo y diagnostico
menu_monitoreo() {
    while true; do
        echo ""
        echo "=========================================="
        echo "  Modulo de Monitoreo y Diagnostico"
        echo "=========================================="
        echo "1) Ver estado del servicio"
        echo "2) Listar concesiones activas"
        echo "3) Ver configuracion actual"
        echo "4) Ver logs recientes"
        echo "5) Validar sintaxis de configuracion"
        echo "6) Reiniciar servicio DHCP"
        echo "0) Volver al menu principal"
        echo ""
        read -p "Seleccione una opcion: " opcion
        
        case $opcion in
            1)
                mostrar_estado
                ;;
            2)
                mostrar_concesiones
                ;;
            3)
                mostrar_configuracion
                ;;
            4)
                mostrar_logs
                ;;
            5)
                echo "Validando sintaxis de configuracion..."
                if dhcpd -t -cf /etc/dhcp/dhcpd.conf; then
                    echo "Sintaxis correcta."
                else
                    echo "ERROR: Se encontraron errores en la configuracion."
                fi
                ;;
            6)
                echo "Reiniciando servicio DHCP..."
                systemctl restart isc-dhcp-server
                sleep 2
                if verificar_dhcp_activo; then
                    echo "Servicio reiniciado correctamente."
                else
                    echo "ERROR: El servicio no pudo iniciarse."
                    echo "Verifique los logs para mas detalles."
                fi
                ;;
            0)
                break
                ;;
            *)
                echo "Opcion invalida."
                ;;
        esac
        
        echo ""
        read -p "Presione ENTER para continuar..."
    done
}

################################################################################
# CONFIGURACION INTERACTIVA
################################################################################

configurar_servidor() {
    echo "=========================================="
    echo "  Configuracion del Servidor DHCP"
    echo "=========================================="
    echo ""
    
    # Detectar y seleccionar interfaz
    echo "Interfaces de red disponibles:"
    echo ""
    ip -o link show | awk -F': ' '!/lo/ {print "  - "$2}'
    echo ""
    
    INTERFAZ=$(ip -o link show | awk -F': ' '!/lo|vir|docker/ {print $2; exit}')
    
    if [[ -z "$INTERFAZ" ]]; then
        read -p "Ingrese el nombre de la interfaz de red: " INTERFAZ
    else
        echo "Interfaz detectada: $INTERFAZ"
        read -p "Usar esta interfaz? (s/n) [s]: " confirmar
        confirmar=${confirmar:-s}
        if [[ "$confirmar" != "s" ]]; then
            read -p "Ingrese el nombre de la interfaz: " INTERFAZ
        fi
    fi
    
    echo ""
    echo "Ingrese los parametros de configuracion de red:"
    echo ""
    
    # IP estatica del servidor
    while true; do
        read -p "IP estatica del servidor (ej: 192.168.100.10): " IP_ESTATICA
        if validar_ipv4 "$IP_ESTATICA"; then
            break
        else
            echo "ERROR: Direccion IP invalida."
        fi
    done
    
    # Direccion de red
    while true; do
        read -p "Direccion de red (ej: 192.168.100.0): " NETWORK_ID
        if validar_ipv4 "$NETWORK_ID"; then
            break
        else
            echo "ERROR: Direccion de red invalida."
        fi
    done
    
    # Mascara de subred
    while true; do
        read -p "Mascara de subred (ej: 255.255.255.0): " SUBNET_MASK
        if validar_ipv4 "$SUBNET_MASK" && validar_mascara "$SUBNET_MASK"; then
            break
        else
            echo "ERROR: Mascara de subred invalida."
        fi
    done
    
    # Rango de IPs
    while true; do
        read -p "IP inicial del rango DHCP (ej: 192.168.100.50): " RANGE_START
        if ! validar_ipv4 "$RANGE_START"; then
            echo "ERROR: IP invalida."
            continue
        fi
        
        read -p "IP final del rango DHCP (ej: 192.168.100.150): " RANGE_END
        if ! validar_ipv4 "$RANGE_END"; then
            echo "ERROR: IP invalida."
            continue
        fi
        
        if validar_rango "$RANGE_START" "$RANGE_END"; then
            break
        else
            echo "ERROR: Rango invalido (IP inicial debe ser menor que IP final)."
        fi
    done
    
    # Gateway
    while true; do
        read -p "Puerta de enlace/gateway (ej: 192.168.100.1): " GATEWAY
        if validar_ipv4 "$GATEWAY"; then
            break
        else
            echo "ERROR: Direccion IP invalida."
        fi
    done
    
    # DNS
    while true; do
        read -p "Servidor DNS (ej: 8.8.8.8 o IP del DNS local): " DNS_SERVER
        if validar_ipv4 "$DNS_SERVER"; then
            break
        else
            echo "ERROR: Direccion IP invalida."
        fi
    done
    
    # Tiempo de concesion
    while true; do
        read -p "Tiempo de concesion en segundos (ej: 7200 = 2 horas): " LEASE_TIME
        if [[ "$LEASE_TIME" =~ ^[0-9]+$ ]] && [[ $LEASE_TIME -gt 0 ]]; then
            break
        else
            echo "ERROR: Debe ser un numero positivo."
        fi
    done
    
    # Resumen de configuracion
    echo ""
    echo "=========================================="
    echo "  Resumen de Configuracion"
    echo "=========================================="
    echo "Interfaz:              $INTERFAZ"
    echo "IP del servidor:       $IP_ESTATICA"
    echo "Red:                   $NETWORK_ID"
    echo "Mascara:               $SUBNET_MASK"
    echo "Rango DHCP:            $RANGE_START - $RANGE_END"
    echo "Gateway:               $GATEWAY"
    echo "DNS:                   $DNS_SERVER"
    echo "Lease time:            $LEASE_TIME segundos"
    echo "=========================================="
    echo ""
    
    read -p "Desea continuar con esta configuracion? (s/n): " confirmar
    if [[ "$confirmar" != "s" ]]; then
        echo "Configuracion cancelada."
        return 1
    fi
    
    echo ""
    
    # Aplicar configuracion
    configurar_ip_estatica "$IP_ESTATICA" "$SUBNET_MASK" "$GATEWAY" "$DNS_SERVER" "$INTERFAZ"
    echo ""
    
    configurar_interfaz "$INTERFAZ"
    echo ""
    
    if ! generar_configuracion_dhcp "$NETWORK_ID" "$SUBNET_MASK" "$RANGE_START" "$RANGE_END" "$GATEWAY" "$DNS_SERVER" "$LEASE_TIME"; then
        echo ""
        echo "ERROR: La configuracion no pudo completarse debido a errores."
        return 1
    fi
    
    # Reiniciar y habilitar servicio
    echo ""
    echo "Reiniciando servicio DHCP..."
    systemctl restart isc-dhcp-server
    systemctl enable isc-dhcp-server
    
    sleep 2
    
    echo ""
    if verificar_dhcp_activo; then
        echo "=========================================="
        echo "  Configuracion Completada"
        echo "=========================================="
        echo ""
        echo "El servidor DHCP esta configurado y en ejecucion."
        echo ""
        echo "Comandos utiles:"
        echo "  Ver estado:     systemctl status isc-dhcp-server"
        echo "  Ver logs:       journalctl -u isc-dhcp-server -f"
        echo "  Ver leases:     cat /var/lib/dhcp/dhcpd.leases"
        echo "  Ver config:     cat /etc/dhcp/dhcpd.conf"
        echo ""
        echo "Para probar desde un cliente:"
        echo "  sudo dhclient -r [interfaz]"
        echo "  sudo dhclient [interfaz]"
        echo ""
        return 0
    else
        echo "=========================================="
        echo "  Error en la Configuracion"
        echo "=========================================="
        echo ""
        echo "El servicio DHCP no pudo iniciarse."
        echo "Revise los logs para mas informacion:"
        echo "  journalctl -xeu isc-dhcp-server"
        echo ""
        return 1
    fi
}

################################################################################
# MENU PRINCIPAL
################################################################################

menu_principal() {
    while true; do
        clear
        echo "=========================================="
        echo "  SERVIDOR DHCP - Ubuntu"
        echo "  Script de Configuracion"
        echo "=========================================="
        echo ""
        
        # Verificar estado del sistema
        if verificar_dhcp_instalado; then
            if verificar_dhcp_activo; then
                echo "Estado: Instalado y en ejecucion"
            else
                echo "Estado: Instalado pero detenido"
            fi
        else
            echo "Estado: No instalado"
        fi
        
        echo ""
        echo "1) Instalar servidor DHCP"
        echo "2) Configurar servidor DHCP"
        echo "3) Modulo de Monitoreo y Diagnostico"
        echo "4) Desinstalar servidor DHCP"
        echo "0) Salir"
        echo ""
        read -p "Seleccione una opcion: " opcion
        
        case $opcion in
            1)
                instalar_dhcp
                read -p "Presione ENTER para continuar..."
                ;;
            2)
                if ! verificar_dhcp_instalado; then
                    echo "ERROR: Debe instalar el servidor DHCP primero (opcion 1)."
                    read -p "Presione ENTER para continuar..."
                    continue
                fi
                configurar_servidor
                read -p "Presione ENTER para continuar..."
                ;;
            3)
                if ! verificar_dhcp_instalado; then
                    echo "ERROR: Debe instalar el servidor DHCP primero (opcion 1)."
                    read -p "Presione ENTER para continuar..."
                    continue
                fi
                menu_monitoreo
                ;;
            4)
                echo ""
                echo "ADVERTENCIA: Esto eliminara completamente el servidor DHCP."
                read -p "Esta seguro? Escriba 'SI' para confirmar: " confirmar
                
                if [[ "$confirmar" == "SI" ]]; then
                    echo "Deteniendo servicio..."
                    systemctl stop isc-dhcp-server
                    systemctl disable isc-dhcp-server
                    
                    echo "Desinstalando paquete..."
                    apt-get purge -y isc-dhcp-server
                    apt-get autoremove -y
                    
                    echo "Servidor DHCP desinstalado."
                else
                    echo "Operacion cancelada."
                fi
                read -p "Presione ENTER para continuar..."
                ;;
            0)
                echo ""
                echo "Saliendo del script..."
                exit 0
                ;;
            *)
                echo "Opcion invalida."
                sleep 1
                ;;
        esac
    done
}

################################################################################
# EJECUCION PRINCIPAL
################################################################################

clear
echo "=========================================="
echo "  Servidor DHCP - Script de Configuracion"
echo "  Ubuntu Server"
echo "=========================================="
echo ""
echo "Sistema: $(lsb_release -d | cut -f2)"
echo "Kernel: $(uname -r)"
echo "Fecha: $(date)"
echo ""
read -p "Presione ENTER para continuar..."

menu_principal