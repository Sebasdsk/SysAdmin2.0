#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root (sudo)."
  exit
fi

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
            echo "Módulo cargado: $(basename "$libreria")"
        fi
    done
else
    echo "Error: No se encuentra el directorio de librerías ($LIB_DIR)."
    exit 1
fi

# MENÚ PRINCIPAL
while true; do 
    echo "Seleccione una opción:"
    echo "1. Instalar y Configurar DHCP"
    echo "2. Instalar y Configurar DNS"
    echo "3. Configurar SSH"
    echo "4. Salir"
    read -p "Opción: " opcion

    case $opcion in
        1)
            Menu_DHCP
            ;;
        2)
            Menu_DNS
            ;;
        3) 
            configurar_ssh_linux;;
        4) 
            exit;;

        *) echo "Opción no válida" ;;
    esac
done