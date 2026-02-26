#!/bin/bash

# ==========================================
# FUNCIONES DNS (BIND9) - reprobados.com
# ==========================================

# 1. VALIDACIÓN PREVIA DE RED (IP FIJA)
function validar_ip_estatica() {
    echo "--- Verificando configuración de red ---"
    # Detectar IP actual
    CURRENT_IP=$(hostname -I | awk '{print $1}')
    
    echo "IP actual detectada: $CURRENT_IP"
    read -p "¿Es esta una IP estática correcta para el servidor DNS? (s/n): " confirm
    
    if [[ "$confirm" != "s" ]]; then
        echo "Configurando IP Estática..."
        read -p "Ingrese IP Estática deseada (ej. 192.168.100.10): " static_ip
        read -p "Mascara (ej. 24): " mask
        read -p "Gateway (ej. 192.168.100.1): " gateway
        read -p "DNS (ej. 8.8.8.8): " dns
        
        # Identificar interfaz
        IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
        
        # Generar configuración Netplan (Compatible con Ubuntu 20.04/22.04)
        cat > /etc/netplan/01-netcfg.yaml <<EOF
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
        echo "Aplicando cambios de red... (Si cambia la IP, la conexión SSH podría caerse)"
        netplan apply
        echo "Red configurada. Nueva IP: $static_ip"
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
    SERVER_IP=$(hostname -I | awk '{print $1}')

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
    # Serial usa fecha + contador: YYYYMMDD01
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