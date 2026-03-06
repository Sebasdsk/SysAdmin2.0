#!/bin/bash

# ==========================================
# FUNCIONES DNS (BIND9) - ADAPTADO PRACTICA 3
# ==========================================

function Menu_DNS(){
    while true; do    
        echo "          MENÚ DNS (BIND9)            "
        echo "1. Validar e Instalar DNS"
        echo "2. Configurar Nueva Zona (Dominio Personalizado)"
        echo "3. Validar Configuración y Servicio"
        echo "4. Regresar al menú principal"
        read -p "Opción: " opcion
        
        case $opcion in
            1)
                instalar_dns
                ;;
            2)
                configurar_zona_interactiva
                ;;
            3) 
                validar_dns
                ;;
            4) 
                return 0 
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
    #
    if dpkg -s bind9 >/dev/null 2>&1; then
        echo "BIND9 ya está instalado."
    else
        echo "Instalando BIND9 y utilidades..."
        apt-get update
        apt-get install -y bind9 bind9utils bind9-doc
    fi
}

# 2. CONFIGURACIÓN DE ZONA (Lógica de Alberto adaptada)
function configurar_zona_interactiva() {
    echo "--- Configuración de Zonas DNS ---"
    
    # - Crear carpeta organizada para zonas
    echo "Creando carpeta de zonas si no existe..."
    mkdir -p /etc/bind/zones
    chown bind:bind /etc/bind/zones

    while true; do
        echo "-----------------------------------"
        # 1. Solicitar Dominio
        while true; do
            read -p "Introduzca el dominio (ej. miempresa.com): " dominio
            if [[ -n "$dominio" ]]; then
                break
            fi
            echo "El dominio no puede estar vacío."
        done

        # 2. Solicitar IP
        # En la práctica de Alberto se pide la IP destino.
        read -p "Introduzca la dirección IP del servidor (A record): " ip_destino
        
        # Validar formato de IP simple (regex básico)
        if [[ ! $ip_destino =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
             echo "Formato de IP inválido. Usando IP local detectada."
             ip_destino=$(hostname -I | awk '{print $1}')
             echo "IP asignada: $ip_destino"
        fi

        nombrearchzona="db.${dominio}"
        ruta="/etc/bind/zones/${nombrearchzona}"

        echo "Generando archivo de zona: $ruta"

        # Generación del archivo de zona
        cat > "${ruta}" << EOF
\$TTL 86400
@   IN  SOA ns1.${dominio}. admin.${dominio}. (
        $(date +%Y%m%d)01 ; Serial
        28800       ; Refresh
        7200        ; Retry
        864000      ; Expire
        86400 )     ; Minimum TTL
;
    IN  NS  ns1.${dominio}.
ns1 IN  A   ${ip_destino}
@   IN  A   ${ip_destino}
www IN  A   ${ip_destino}
EOF

        # Asignar permisos correctos
        chown bind:bind "${ruta}"

        # Configurar named.conf.local
        ZoneConfig="/etc/bind/named.conf.local"

        # Evitar duplicados
        if ! grep -q "zone \"${dominio}\"" "$ZoneConfig"; then
            cat >> "$ZoneConfig" <<EOF
zone "${dominio}" {
    type master;
    file "${ruta}";
};
EOF
            echo "Zona añadida a la configuración local."
        else
            echo "La zona ya existía en named.conf.local. Se actualizó el archivo db."
        fi

        # Verificación rápida
        named-checkconf
        if [ $? -eq 0 ]; then
            echo "Sintaxis válida. Reiniciando Bind9..."
            systemctl restart bind9
        else
            echo "Error en la configuración generada."
        fi

        # Preguntar si quiere agregar otro dominio (Loop de Alberto)
        read -p "¿Desea configurar otro dominio? (s/n): " respuesta
        if [[ "$respuesta" != "s" && "$respuesta" != "S" ]]; then
            break
        fi
    done
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