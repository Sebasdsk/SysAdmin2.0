function actualizar_sistema() {
    sudo apt update && sudo apt upgrade -y
}

function verificar_root(){
    if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root (sudo)."
  exit
fi
}