#!/bin/bash

# ==========================================
# FUNCIONES FTP (VSFTPD)
# ==========================================

FTP_ROOT="/srv/ftp_data"

function Menu_FTP(){
    while true; do    
        echo "          MENÚ FTP (VSFTPD)            "
        echo "1. Instalar y Configurar VSFTPD"
        echo "2. Crear Usuarios FTP (Masivo)"
        echo "3. Cambiar Grupo de Usuario"
        echo "4. Regresar al menú principal"
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

    # Crear estructura base física
    mkdir -p "$FTP_ROOT/general"
    mkdir -p "$FTP_ROOT/reprobados"
    mkdir -p "$FTP_ROOT/recursadores"

    # Crear grupos del sistema
    groupadd -f reprobados
    groupadd -f recursadores

    # Permisos base: General es leíble por todos (incluido anónimo ftp), escribible por usuarios logueados
    # Usaremos ACLs para facilitar esto
    chmod 775 "$FTP_ROOT/general"
    setfacl -m u:ftp:rx "$FTP_ROOT/general"      # Usuario anónimo
    setfacl -m g:reprobados:rwx "$FTP_ROOT/general"
    setfacl -m g:recursadores:rwx "$FTP_ROOT/general"
    
    # Permisos carpetas de grupo
    chgrp reprobados "$FTP_ROOT/reprobados"
    chmod 2770 "$FTP_ROOT/reprobados" # SGID
    
    chgrp recursadores "$FTP_ROOT/recursadores"
    chmod 2770 "$FTP_ROOT/recursadores" # SGID

    echo "Estructura base creada en $FTP_ROOT"
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
# Jaula chroot
chroot_local_user=YES
allow_writeable_chroot=YES
# Ruta para anónimos
anon_root=$FTP_ROOT/general
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
# Seguridad
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
        echo "--- Usuario $i de $n ---"
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

        # Crear usuario con home específica
        if id "$username" &>/dev/null; then
            echo "El usuario $username ya existe. Saltando creación base..."
        else
            useradd -m -s /bin/bash -g "$grupo" "$username"
            echo "$username:$password" | chpasswd
        fi

        # Configurar estructura visual en el HOME del usuario
        USER_HOME="/home/$username"
        
        # 1. Carpeta Personal
        mkdir -p "$USER_HOME/$username"
        chown "$username:$grupo" "$USER_HOME/$username"
        chmod 755 "$USER_HOME/$username"

        # 2. Carpeta General (Mount Bind)
        mkdir -p "$USER_HOME/general"
        # Desmontar si ya existe para evitar duplicados
        umount "$USER_HOME/general" 2>/dev/null
        mount --bind "$FTP_ROOT/general" "$USER_HOME/general"

        # 3. Carpeta de Grupo (Mount Bind)
        mkdir -p "$USER_HOME/$grupo"
        umount "$USER_HOME/$grupo" 2>/dev/null
        mount --bind "$FTP_ROOT/$grupo" "$USER_HOME/$grupo"

        # IMPORTANTE: Persistencia básica de mounts (se perderá al reiniciar el server si no se agrega a fstab, 
        # pero para el script lo hacemos "live").
        
        echo "Usuario $username configurado en grupo $grupo."
        echo "Estructura creada: /general, /$grupo, /$username"
    done
}

function cambiar_grupo_ftp() {
    read -p "Ingrese usuario a modificar: " user
    if ! id "$user" &>/dev/null; then
        echo "Usuario no existe."
        return
    fi

    current_group=$(id -gn "$user")
    echo "Grupo actual: $current_group"
    
    if [ "$current_group" == "reprobados" ]; then
        new_group="recursadores"
    else
        new_group="reprobados"
    fi

    read -p "Cambiar a grupo '$new_group'? (s/n): " confirm
    if [ "$confirm" == "s" ]; then
        # Desmontar carpeta del grupo viejo
        umount "/home/$user/$current_group" 2>/dev/null
        rmdir "/home/$user/$current_group" 2>/dev/null
        
        # Cambiar grupo sistema
        usermod -g "$new_group" "$user"
        
        # Montar carpeta grupo nuevo
        mkdir -p "/home/$user/$new_group"
        mount --bind "$FTP_ROOT/$new_group" "/home/$user/$new_group"
        
        # Actualizar permisos carpeta personal
        chown "$user:$new_group" "/home/$user/$user"
        
        echo "Grupo actualizado a $new_group y carpetas re-mapeadas."
    fi
}