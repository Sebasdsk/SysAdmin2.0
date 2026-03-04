#!/bin/bash

# ==========================================
# FUNCIONES FTP (VSFTPD)
# ==========================================

FTP_DATA="/srv/ftp_data"   # Donde se guardan los datos reales
FTP_ANON="/srv/ftp_anon"   # Raíz visual para el usuario anónimo

function Menu_FTP(){
    while true; do    
        echo "          MENÚ FTP (VSFTPD)            "
        echo "1. Instalar y Configurar VSFTPD"
        echo "2. Crear Usuarios FTP (Masivo)"
        echo "3. Cambiar Grupo de Usuario"
        echo "4. Monitorear Estado e IP"
        echo "5. Regresar al menú principal"
        read -p "Opción: " opcion
        
        case $opcion in
            1)
                instalar_ftp
                configurar_vsftpd_conf
                ;;
            2)
                crear_usuarios_ftp
                ;;
            3) 
                cambiar_grupo_ftp
                ;;
            4)
                monitorear_ftp
                ;;
            5) 
                return 0
                ;;
            *) 
                echo "Opción no válida"
                ;;
        esac
    done
}

function instalar_ftp() {
    echo "--- Verificando servicio VSFTPD ---"
    if dpkg -s vsftpd >/dev/null 2>&1; then
        echo "VSFTPD ya está instalado."
    else
        echo "Instalando vsftpd..."
        apt-get update
        apt-get install -y vsftpd acl
    fi

    # 1. Crear estructura de datos REAL
    mkdir -p "$FTP_DATA/general"
    mkdir -p "$FTP_DATA/reprobados"
    mkdir -p "$FTP_DATA/recursadores"

    # 2. Crear estructura visual para ANÓNIMO
    # Esto soluciona que solo vean "/" vacía. Ahora verán "/general"
    mkdir -p "$FTP_ANON/general"
    
    # Montaje Bind para anónimo (Si ya está montado, evitar duplicados)
    if ! mount | grep -q "$FTP_ANON/general"; then
        mount --bind "$FTP_DATA/general" "$FTP_ANON/general"
    fi

    # Crear grupos del sistema
    groupadd -f reprobados
    groupadd -f recursadores

    # 3. Configurar Permisos
    # General: Leíble por todos (incluido 'ftp' user), escribible por grupos alumnos
    chmod 775 "$FTP_DATA/general"
    setfacl -R -m u:ftp:rx "$FTP_DATA/general"      # Usuario anónimo
    setfacl -R -m g:reprobados:rwx "$FTP_DATA/general"
    setfacl -R -m g:recursadores:rwx "$FTP_DATA/general"
    
    # Carpetas de Grupo (Privadas para el grupo)
    chgrp reprobados "$FTP_DATA/reprobados"
    chmod 2770 "$FTP_DATA/reprobados" # SGID y rwx para grupo
    
    chgrp recursadores "$FTP_DATA/recursadores"
    chmod 2770 "$FTP_DATA/recursadores" # SGID y rwx para grupo

    echo "Estructura de directorios y permisos aplicada."
}

function configurar_vsftpd_conf() {
    echo "--- Configurando vsftpd.conf ---"
    cp /etc/vsftpd.conf /etc/vsftpd.conf.bak.$(date +%F_%T)

    cat > /etc/vsftpd.conf <<EOF
listen=NO
listen_ipv6=YES
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES

# --- JAULA CHROOT ---
chroot_local_user=YES
allow_writeable_chroot=YES

# --- CONFIGURACIÓN ANÓNIMA ---
# Apuntamos a la carpeta wrapper para que vean 'general' dentro
anon_root=$FTP_ANON
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO

# --- SEGURIDAD ---
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO
EOF

    systemctl restart vsftpd
    echo "VSFTPD configurado y reiniciado."
}

function crear_usuarios_ftp() {
    read -p "¿Cuántos usuarios deseas crear? " n
    
    for (( i=1; i<=n; i++ )); do
        echo "-----------------------------------"
        echo "Creando Usuario $i de $n"
        read -p "Nombre de usuario: " username
        read -p "Contraseña: " password
        
        while true; do
            read -p "Grupo (1: reprobados, 2: recursadores): " grp_opt
            case $grp_opt in
                1) grupo="reprobados"; break ;;
                2) grupo="recursadores"; break ;;
                *) echo "Opción inválida";;
            esac
        done

        # Crear usuario si no existe
        if id "$username" &>/dev/null; then
            echo "El usuario $username ya existe."
        else
            useradd -m -s /bin/bash -g "$grupo" "$username"
            echo "$username:$password" | chpasswd
        fi

        # Configurar estructura visual en el HOME del usuario
        USER_HOME="/home/$username"
        
        # 1. Carpeta Personal (Real)
        mkdir -p "$USER_HOME/$username"
        chown "$username:$grupo" "$USER_HOME/$username"
        chmod 755 "$USER_HOME/$username"

        # 2. Carpeta General (Montaje Bind)
        mkdir -p "$USER_HOME/general"
        umount "$USER_HOME/general" 2>/dev/null
        mount --bind "$FTP_DATA/general" "$USER_HOME/general"

        # 3. Carpeta de Grupo (Montaje Bind)
        mkdir -p "$USER_HOME/$grupo"
        umount "$USER_HOME/$grupo" 2>/dev/null
        mount --bind "$FTP_DATA/$grupo" "$USER_HOME/$grupo"

        echo "Usuario $username listo. Estructura creada."
    done
}

function cambiar_grupo_ftp() {
    read -p "Ingrese usuario a modificar: " user
    if ! id "$user" &>/dev/null; then
        echo "Error: Usuario no existe."
        return
    fi

    current_group=$(id -gn "$user")
    echo "Grupo actual: $current_group"
    
    if [ "$current_group" == "reprobados" ]; then
        new_group="recursadores"
    else
        new_group="reprobados"
    fi

    read -p "¿Cambiar a grupo '$new_group'? (s/n): " confirm
    if [ "$confirm" == "s" ]; then
        # Desmontar carpeta del grupo viejo
        umount "/home/$user/$current_group" 2>/dev/null
        rmdir "/home/$user/$current_group" 2>/dev/null
        
        # Cambiar grupo sistema
        usermod -g "$new_group" "$user"
        
        # Montar carpeta grupo nuevo
        mkdir -p "/home/$user/$new_group"
        mount --bind "$FTP_DATA/$new_group" "/home/$user/$new_group"
        
        # Actualizar permisos carpeta personal
        chown "$user:$new_group" "/home/$user/$user"
        
        echo "Grupo actualizado a $new_group."
    fi
}

function monitorear_ftp() {
    echo "========================================="
    echo "       MONITOREO DEL SERVIDOR FTP        "
    echo "========================================="
    
    echo -e "\n--- 1. Direcciones IP del Servidor ---"
    echo "Conéctate usando alguna de estas IPs:"
    hostname -I
    
    echo -e "\n--- 2. Estado del Servicio (Systemd) ---"
    if systemctl is-active --quiet vsftpd; then
        echo "ESTADO: ACTIVO (Running)"
    else
        echo "ESTADO: INACTIVO O FALLIDO"
    fi

    
    echo "========================================="
    read -p "Presiona Enter para continuar..."
}