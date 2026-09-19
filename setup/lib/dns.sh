#!/usr/bin/env bash
# Tela 4: bot.<domínio> precisa apontar para esta VPS antes de emitir o certificado.
#
# Toda consulta aqui termina com `|| true`: domínio sem registro é o caso normal desta tela,
# e com `set -e` um grep sem resultado derrubaria o setup em silêncio.

INTERVALO_DNS=15

ip_publico() {
  curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null ||
    curl -4 -fsS --max-time 10 https://ifconfig.me 2>/dev/null || true
}

# Primeiro os servidores oficiais do domínio (é neles que o Let's Encrypt confere e onde o
# registro novo aparece na hora). Depois, resolvedores públicos: um só pode ficar minutos
# preso numa resposta antiga de "domínio não existe".
RESOLVEDORES_PUBLICOS=(8.8.8.8 1.1.1.1 9.9.9.9)

_consulta() { # _consulta TIPO NOME SERVIDOR
  { dig +short +time=3 +tries=1 "$1" "$2" "@$3" 2>/dev/null | grep -E "$4" | tail -1; } || true
}

servidores_oficiais() {
  local dominio=$1 resolvedor ns
  for resolvedor in "${RESOLVEDORES_PUBLICOS[@]}"; do
    ns=$({ dig +short +time=3 +tries=1 NS "$dominio" "@$resolvedor" 2>/dev/null | grep -E '\.$'; } || true)
    if [ -n "$ns" ]; then
      printf '%s\n' "$ns"
      return 0
    fi
  done
}

# consulta_dns TIPO NOME DOMINIO_BASE PADRAO
consulta_dns() {
  local tipo=$1 nome=$2 dominio=$3 padrao=$4 servidor resposta
  for servidor in $(servidores_oficiais "$dominio") "${RESOLVEDORES_PUBLICOS[@]}"; do
    resposta=$(_consulta "$tipo" "$nome" "$servidor" "$padrao")
    if [ -n "$resposta" ]; then
      printf '%s' "$resposta"
      return 0
    fi
  done
}

ip_do_dominio() { consulta_dns A "$1" "$2" '^[0-9.]+$'; }

ipv6_do_dominio() { consulta_dns AAAA "$1" "$2" ':'; }

ip_da_cloudflare() {
  local faixas
  faixas=$(curl -fsS --max-time 10 https://www.cloudflare.com/ips-v4 2>/dev/null) || return 1
  python3 - "$1" "$faixas" <<'PY'
import ipaddress, sys
ip = ipaddress.ip_address(sys.argv[1])
sys.exit(0 if any(ip in ipaddress.ip_network(f.strip()) for f in sys.argv[2].split() if f.strip()) else 1)
PY
}

instrucoes_dns() {
  local ip=$1 dominio=$2
  aviso "Precisa de um registro DNS: $(destaque "bot.$dominio") apontando para o IP $(destaque "$ip")."
  echo
  info "No painel do domínio $(destaque "$dominio"), crie:"
  echo
  printf '    %sTipo%s %sA%s   %sNome%s %sbot%s   %sValor%s %s%s%s   %sTTL%s %s300%s\n' \
    "$CINZA" "$NORMAL" "$NEGRITO" "$NORMAL" "$CINZA" "$NORMAL" "$NEGRITO" "$NORMAL" \
    "$CINZA" "$NORMAL" "$NEGRITO" "$ip" "$NORMAL" "$CINZA" "$NORMAL" "$NEGRITO" "$NORMAL"
  echo
  dica "Hostinger: Domínios > $dominio > DNS / Nameservers. Cloudflare: proxy desligado (nuvem cinza)."
  echo
}

tela_dns() {
  estado_tem dns_ok && return 0
  local sub dominio ip resolvido ipv6 resposta situacao anterior=""
  sub=$(env_get SUBDOMINIO_BOT)
  dominio=$(env_get DOMINIO_BASE)
  secao "Domínio"

  ip=$(ip_publico)
  [ -n "$ip" ] || erro_fatal "Não consegui descobrir o IP público da VPS" "Confira a internet da VPS."

  resolvido=$(ip_do_dominio "$sub" "$dominio")
  [ "$resolvido" = "$ip" ] || instrucoes_dns "$ip" "$dominio"

  while true; do
    resolvido=$(ip_do_dominio "$sub" "$dominio")
    ipv6=$(ipv6_do_dominio "$sub" "$dominio")

    if [ "$resolvido" = "$ip" ] && [ -z "$ipv6" ]; then
      printf '\r\033[K'
      ok "$(destaque "$sub") aponta para esta VPS"
      estado_set dns_ok "$(date -Is)"
      return 0
    fi

    # Avisos só quando a situação muda; a espera fica numa linha só.
    if [ "$resolvido" = "$ip" ]; then
      situacao="ipv6:$ipv6"
    elif [ -n "$resolvido" ] && ip_da_cloudflare "$resolvido"; then
      situacao="cloudflare"
    elif [ -n "$resolvido" ]; then
      situacao="outro:$resolvido"
    else
      situacao="vazio"
    fi
    if [ "$situacao" != "$anterior" ]; then
      printf '\r\033[K'
      case "$situacao" in
        ipv6:*) aviso "Apague o registro AAAA de $sub ($ipv6): ele atrapalha o certificado." ;;
        cloudflare) aviso "Desligue o proxy da Cloudflare no registro bot (nuvem cinza)." ;;
        outro:*) aviso "O registro bot aponta para $resolvido. Troque o valor para $ip." ;;
      esac
      anterior=$situacao
    fi

    printf '\r\033[K  %s⟳%s Aguardando o DNS %s(checado às %s · Enter checa agora · S sai)%s ' \
      "$CIANO" "$NORMAL" "$CINZA" "$(date +%H:%M:%S)" "$NORMAL"
    resposta=""
    if IFS= read -r -t "$INTERVALO_DNS" resposta <&3; then
      if [[ "$resposta" =~ ^[Ss]$ ]]; then
        dica "Quando o domínio apontar, rode o mesmo comando: o setup continua daqui."
        exit 0
      fi
      # O Enter desceu o cursor; volta para reescrever a mesma linha.
      printf '\033[1A'
    fi
  done
}
