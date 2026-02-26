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
echo "1. Configurar Acceso Remoto (SSH)"
echo "2. Instalar y Configurar DNS"
echo "3. Instalar y Configurar DHCP"
read -p "Opción: " opcion

case $opcion in
    1) configurar_ssh_linux ;;  # Llamada a función importada
    2) instalar_configurar_dns ;;
    3) instalar_configurar_dhcp ;;
    *) echo "Opción no válida" ;;
esac