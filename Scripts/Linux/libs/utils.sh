function actualizar_sistema() {
    sudo apt update && sudo apt upgrade -y
}

function verificar_root(){
    if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root (sudo)."
  exit
fi
}

function validar_ip_estatica() {
    echo "--- Verificando configuración de red ---"
    
    # Identificar interfaz dura
    IFACE="enp0s8"
    
    # Detectar IP actual ESPECÍFICAMENTE de la interfaz interna (enp0s8)
    CURRENT_IP=$(ip -4 addr show "$IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    
    if [ -z "$CURRENT_IP" ]; then
        echo "La interfaz $IFACE no tiene IP actualmente."
    else
        echo "IP actual detectada en $IFACE: $CURRENT_IP"
    fi
    
    read -p "¿Es esta una IP estática correcta para el servidor DNS? (s/n): " confirm
    
    if [[ "$confirm" != "s" ]]; then
        echo "Configurando IP Estática..."
        read -p "Ingrese IP Estática deseada (ej. 192.168.100.10): " static_ip
        read -p "Mascara (ej. 24): " mask
        # En una red interna pura, el gateway no suele ser estrictamente necesario para el server, 
        # pero si la rúbrica lo pide, lo dejamos.
        read -p "Gateway (ej. 192.168.100.1): " gateway
        read -p "DNS (ej. 8.8.8.8): " dns
        
        # CORRECCIÓN CLAVE: Usar un archivo 02-... para NO borrar el 01 (el del puente)
        cat > /etc/netplan/02-red-interna.yaml <<EOF
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
        echo "Aplicando cambios de red..."
        netplan apply
        echo "Red interna configurada. Nueva IP: $static_ip"
    else
        echo "IP confirmada. Procediendo..."
    fi
}