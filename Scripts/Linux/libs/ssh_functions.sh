#!/bin/bash

# Función para instalar y configurar SSH
function configurar_ssh_linux() {
    echo "--- Iniciando configuración de SSH ---"
    
    # 1. Instalar el servicio
    if ! dpkg -s openssh-server >/dev/null 2>&1; then
        apt-get update
        apt-get install -y openssh-server
    else
        echo "OpenSSH ya está instalado."
    fi

    # 2. Habilitar en el arranque y asegurar ejecución
    systemctl enable ssh
    systemctl start ssh

    # 3. Validar estado
    if systemctl is-active --quiet ssh; then
        echo "SSH está activo y corriendo."
        echo "IP del servidor: $(hostname -I)"
    else
        echo "Error: SSH no se inició correctamente."
    fi
}x