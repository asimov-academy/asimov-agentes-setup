#!/usr/bin/env bash
# shellcheck disable=SC2034  # PASSO_ATUAL e PASSO_TOTAL são lidas por passo(), em estado.sh
# Telas 1 e 2: boas-vindas com aceite e preparação da VPS vazia.

MEMORIA_MINIMA_KB=1800000
DISCO_MINIMO_KB=20000000

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
APT_OPCOES=(-y -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

tela_boas_vindas() {
  estado_tem aceite && return 0
  banner_asimov
  info "Prepara esta máquina para agentes de IA de atendimento."
  dica "Instala Docker, banco, HTTPS e a plataforma. Licença MIT, crédito à Asimov Academy."
  echo
  if ! confirma "Continuar?"; then
    dica "Cancelado. Nada foi alterado."
    exit 0
  fi
  estado_set aceite "$(date -Is)"
}

verifica_ubuntu() {
  # shellcheck disable=SC1091
  . /etc/os-release
  [ "${ID:-}" = "ubuntu" ] && [ "${VERSION_ID:-}" = "24.04" ]
}

verifica_recursos() {
  local memoria disco
  memoria=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  disco=$(df --output=avail -k / | tail -1 | tr -d ' ')
  echo "memória: ${memoria} kB, disco livre: ${disco} kB"
  [ "$memoria" -ge "$MEMORIA_MINIMA_KB" ] && [ "$disco" -ge "$DISCO_MINIMO_KB" ]
}

apt_update() { $SUDO apt-get -o DPkg::Lock::Timeout=600 update; }
apt_upgrade() { $SUDO apt-get "${APT_OPCOES[@]}" upgrade; }
apt_instala() { $SUDO apt-get "${APT_OPCOES[@]}" install "$@"; }

instala_docker() {
  if command -v docker >/dev/null 2>&1 && $SUDO docker compose version >/dev/null 2>&1; then
    return 0
  fi
  curl -fsSL https://get.docker.com -o /tmp/instala-docker.sh
  $SUDO sh /tmp/instala-docker.sh
  $SUDO systemctl enable --now docker
  $SUDO docker compose version
}

tela_iniciando() {
  banner_iniciando
  PASSO_ATUAL=0
  PASSO_TOTAL=8
  passo ubuntu "Ubuntu 24.04" \
    "Este setup só roda em Ubuntu 24.04. Reinstale a VPS com essa imagem." \
    --sem-repetir verifica_ubuntu
  passo recursos "Memória e disco" \
    "A VPS precisa de 2 GB de RAM e 20 GB livres. Aumente o plano." \
    --sem-repetir verifica_recursos
  passo update "Lista de pacotes" "Confira a internet da VPS: ping -c 3 archive.ubuntu.com" apt_update
  passo upgrade "Atualização do sistema" "Rode apt-get upgrade para ver o erro." apt_upgrade
  passo base "sudo, apt-utils e dialog" "Veja o log." apt_instala sudo apt-utils dialog
  passo ferramentas "jq, curl e dnsutils" "Veja o log." \
    apt_instala jq curl ca-certificates gnupg dnsutils openssl qrencode
  passo python "python3 e ufw" "Veja o log." apt_instala python3 ufw
  passo docker "Docker" \
    "Confira se a VPS alcança https://get.docker.com." instala_docker
}
