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
    echo "1. Configurar Direccion IP estatica (Red Interna)"
    echo "2. Instalar y Configurar DHCP"
    echo "3. Instalar y Configurar DNS"
    echo "4. Configurar SSH"
    echo "5. Instalar y configurar FTP"
    echo "6. Salir"
    read -p "Opción: " opcion

    case $opcion in
        1)
            validar_dns
            ;;
        2)
            Menu_DHCP
            ;;
        3)
            Menu_DNS
            ;;
        4) 
            configurar_ssh_linux
            ;;
        5)
            Menu_FTP
            ;;
        6) 
            exit
            ;;

        *) echo "Opción no válida" ;;
    esac
done