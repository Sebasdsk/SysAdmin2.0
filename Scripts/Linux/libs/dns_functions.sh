#!/bin/bash

# ==========================================
# FUNCIONES DNS (BIND9) - reprobados.com
# ==========================================

function Menu_DNS(){
    while true; do    
        echo "          MENÚ DNS (BIND9)            "
        echo "1. Validar IP e Instalar DNS"
        echo "2. Configurar Zona (reprobados.com)"
        echo "3. Validar y Monitorear DNS"
        echo "4. Regresar al menú principal"
        read -p "Opción: " opcion
        
        case $opcion in
            1)
                validar_ip_estatica
                instalar_dns
                ;;
            2)
                configurar_zona_dns
                ;;
            3) 
                validar_dns
                ;;
            4) 
                return 0 # Regresa al main.sh
                ;;
            *) 
                echo "Opción no válida"
                ;;
        esac
    done
}

# (Mantén el resto de tus funciones aquí abajo sin cambios: validar_ip_estatica, instalar_dns, etc.)

# 1. VALIDACIÓN PREVIA DE RED (IP FIJA)
function validar_ip_estatica() {
    echo "--- Verificando configuración de red ---"
    
    # Identificar interfaz dura
    IFACE="enp0s8"
    
    # Detectar IP actual ESPECÍFICAMENTE de la interfaz interna (enp0s8)
    CURRENT_IP=$(ip -4 addr show "$IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    
    if [ -z "$CURRENT_IP" ]; then
        echo "La interfaz $IFACE no tiene IP actualmente."
    else
        echo "IP actual detectada en $IFACE: $CURRENT_IP"
    fi
    
    read -p "¿Es esta una IP estática correcta para el servidor DNS? (s/n): " confirm
    
    if [[ "$confirm" != "s" ]]; then
        echo "Configurando IP Estática..."
        read -p "Ingrese IP Estática deseada (ej. 192.168.100.10): " static_ip
        read -p "Mascara (ej. 24): " mask
        # En una red interna pura, el gateway no suele ser estrictamente necesario para el server, 
        # pero si la rúbrica lo pide, lo dejamos.
        read -p "Gateway (ej. 192.168.100.1): " gateway
        read -p "DNS (ej. 8.8.8.8): " dns
        
        # CORRECCIÓN CLAVE: Usar un archivo 02-... para NO borrar el 01 (el del puente)
        cat > /etc/netplan/02-red-interna.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
      addresses:
        - $static_ip/$mask
      routes:
        - to: default
          via: $gateway
      nameservers:
        addresses: [$dns]
EOF
        echo "Aplicando cambios de red..."
        netplan apply
        echo "Red interna configurada. Nueva IP: $static_ip"
    else
        echo "IP confirmada. Procediendo..."
    fi
}

# 2. INSTALACIÓN IDEMPOTENTE
function instalar_dns() {
    echo "--- Verificando servicio BIND9 ---"
    if dpkg -s bind9 >/dev/null 2>&1; then
        echo "BIND9 ya está instalado."
    else
        echo "Instalando BIND9 y utilidades..."
        apt-get update
        apt-get install -y bind9 bind9utils bind9-doc
    fi
}


# 3. CONFIGURACIÓN DE ZONA (reprobados.com)
function configurar_zona_dns() {
    echo "--- Configurando Zona 'reprobados.com' ---"
    
    read -p "Ingrese la IP del CLIENTE (para www.reprobados.com): " cliente_ip
    
    # CORRECCIÓN CLAVE: Obtener la IP estrictamente de enp0s8
    SERVER_IP=$(ip -4 addr show "enp0s8" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

    if [ -z "$SERVER_IP" ]; then
         echo "Error: No se detectó IP en enp0s8. Por favor revisa la configuración de red."
         return 1
    fi

    # Configurar named.conf.local
    if ! grep -q "reprobados.com" /etc/bind/named.conf.local; then
        cat >> /etc/bind/named.conf.local <<EOF

zone "reprobados.com" {
    type master;
    file "/var/cache/bind/db.reprobados.com";
};
EOF
        echo "Zona añadida a named.conf.local"
    fi

    # Crear archivo de zona
    SERIAL=$(date +%Y%m%d01)
    
    cat > /var/cache/bind/db.reprobados.com <<EOF
;
; BIND data file for reprobados.com
;
\$TTL    604800
@       IN      SOA     ns1.reprobados.com. root.reprobados.com. (
                              $SERIAL     ; Serial
                         604800     ; Refresh
                          86400     ; Retry
                        2419200     ; Expire
                         604800 )   ; Negative Cache TTL
;
@       IN      NS      ns1.reprobados.com.
@       IN      A       $SERVER_IP
ns1     IN      A       $SERVER_IP
www     IN      A       $cliente_ip
EOF

    echo "Archivo de zona creado en /var/cache/bind/db.reprobados.com"
    
    # Reiniciar servicio
    systemctl restart bind9
}

# 4. VALIDACIÓN
function validar_dns() {
    echo "--- Validando configuración DNS ---"
    named-checkconf
    if [ $? -eq 0 ]; then
        echo "Sintaxis de configuración: OK"
    else
        echo "Error de sintaxis en BIND."
    fi
    
    echo "Estado del servicio:"
    systemctl status bind9 --no-pager | grep "Active:"
}