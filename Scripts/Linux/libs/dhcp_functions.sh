#!/bin/bash

# ==========================================
# FUNCIONES DHCP (ISC-DHCP-SERVER)
# ==========================================

function Menu_DHCP(){
while true; do    
    echo "Bienvenido al DHCP" 
    echo "Seleccione una opcion"
    echo "1. Instalar y Configurar DHCP"
    echo "2. Monitorear el DHCP"
    echo "3. Salir"
    read -p "Opcion: " opcion
    case $opcion in
        1)
            instalar_dhcp
            configurar_dhcp_interactivo
            ;;
        2)
            monitorear_dhcp
            ;;
        3) 
            return 0
            ;;
        *) 
            echo "opcion no valida"
            ;;

    esac
done
}


# 1. INSTALACIÓN IDEMPOTENTE
function instalar_dhcp() {
    echo "--- Verificando servicio DHCP ---"
    if dpkg -s isc-dhcp-server >/dev/null 2>&1; then
        echo "El servicio 'isc-dhcp-server' ya está instalado."
    else
        echo "Instalando isc-dhcp-server..."
        # DEBIAN_FRONTEND=noninteractive evita preguntas durante la instalación
        DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server
    fi
}

# 2. CONFIGURACIÓN DINÁMICA (WIZARD)
function configurar_dhcp_interactivo() {
    echo "--- Configuración del Ámbito DHCP ---"
    
    # Solicitud de datos (con valores por defecto sugeridos entre paréntesis)
    read -p "Nombre del Ámbito (Ej. RedInterna): " scope_name
    read -p "IP de Red (Ej. 192.168.100.0): " net_ip
    read -p "Máscara de Red (Ej. 255.255.255.0): " net_mask
    read -p "Rango Inicio (Ej. 192.168.100.50): " range_start
    read -p "Rango Fin (Ej. 192.168.100.150): " range_end
    read -p "Gateway (Ej. 192.168.100.1): " gateway
    read -p "DNS Primario (IP Servidor Práctica 1): " dns_server
    
    # Validación básica de nulos (se puede mejorar con Regex para IPs)
    if [[ -z "$net_ip" || -z "$range_start" ]]; then
        echo "Error: Faltan datos obligatorios."
        return 1
    fi

    # Backup de seguridad
    cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak.$(date +%F_%T)

    # Escritura de configuración
    echo "Generando archivo de configuración..."
    cat > /etc/dhcp/dhcpd.conf <<EOF
default-lease-time 600;
max-lease-time 7200;
authoritative;

subnet $net_ip netmask $net_mask {
    range $range_start $range_end;
    option routers $gateway;
    option domain-name-servers $dns_server;
    option domain-name "$scope_name";
}
EOF


    PREF_INTERFAZ="enp0s8"
    if ip link show "$PREF_INTERFAZ" >/dev/null 2>&1; then
        INTERFAZ="$PREF_INTERFAZ"
    else
        # Si no existe, usar la lógica anterior (ruta por defecto o primera no-loopback)
        INTERFAZ=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
        if [ -z "$INTERFAZ" ]; then
            INTERFAZ=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
        fi
    fi

    sed -i "s/INTERFACESv4=.*/INTERFACESv4=\"$INTERFAZ\"/" /etc/default/isc-dhcp-server

    # Validar sintaxis antes de reiniciar
    if dhcpd -t -cf /etc/dhcp/dhcpd.conf > /dev/null 2>&1; then
        systemctl restart isc-dhcp-server
        echo "Servicio DHCP configurado y reiniciado correctamente en interfaz $INTERFAZ."
    else
        echo "Error: La configuración generada no es válida. Restaurando backup..."
        cp /etc/dhcp/dhcpd.conf.bak.* /etc/dhcp/dhcpd.conf
    fi
}

# 3. MONITOREO Y ESTADO
function monitorear_dhcp() {
    echo "--- Estado del Servicio ---"
    systemctl status isc-dhcp-server --no-pager
    
    echo -e "\n--- Concesiones Activas (Leases) ---"
    if [ -f /var/lib/dhcp/dhcpd.leases ]; then
        # Muestra IP, MAC y Hostname de las concesiones
        grep -E "lease |hardware ethernet|client-hostname" /var/lib/dhcp/dhcpd.leases | tail -n 15
    else
        echo "No se encontró archivo de leases."
    fi
}