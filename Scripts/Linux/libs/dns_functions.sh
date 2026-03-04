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





# 1. INSTALACIÓN IDEMPOTENTE
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


# 2. CONFIGURACIÓN DE ZONA (reprobados.com)
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

# 3. VALIDACIÓN
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