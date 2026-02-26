#!/bin/bash

# Definir la ruta de las librerías
LIB_DIR="./libs"

# Validar que el directorio existe
if [ -d "$LIB_DIR" ]; then
    echo "Cargando librerías..."
    # Iterar sobre cada archivo .sh en el directorio
    for libreria in "$LIB_DIR"/*.sh; do
        if [ -r "$libreria" ]; then
            source "$libreria"
            # Opcional: Imprimir qué se cargó (útil para debug)
            # echo "  [+] Módulo cargado: $(basename "$libreria")"
        fi
    done
else
    echo "Error: No se encuentra el directorio de librerías ($LIB_DIR)."
    exit 1
fi

# MENÚ PRINCIPAL
echo "Seleccione una opción:"
echo "1. Instalar y Configurar DHCP"
echo "2. Instalar y Configurar DNS"
echo "3. Configurar SSH"
read -p "Opción: " opcion

case $opcion in
    1)
        instalar_dhcp            # Función de libs/dhcp_functions.sh
        configurar_dhcp_interactivo
        monitorear_dhcp
        ;;
    2)
        validar_ip_estatica
        instalar_dns
        configurar_zona_dns
        validar_dns
        ;;
    3) configurar_ssh_linux;;
    *) echo "Opción no válida" ;;
esac