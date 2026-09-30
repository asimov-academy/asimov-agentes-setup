#!/usr/bin/env bash
# shellcheck disable=SC2034  # API_LOCAL é usado pelas telas.
# Proxy existente continua dono das portas públicas. O gateway Asimov mantém /admin privado.
porta_ocupada() {
  [ -n "$($SUDO ss -ltnH "sport = :$1" 2>/dev/null)" ]
}

porta_do_asimov() {
  local porta=$1 servico=$2 id
  id=$($SUDO docker ps -q --filter label=com.docker.compose.project=asimov \
    --filter "label=com.docker.compose.service=$servico" 2>/dev/null) || return 1
  [ -n "$id" ] || return 1
  $SUDO docker port "$id" 2>/dev/null | awk -v p="$porta" '$NF ~ (":" p "$") { achou=1 } END { exit !achou }'
}

escolhe_porta_local() {
  local chave=$1 padrao=$2 servico=$3 porta
  porta=$(env_get "$chave"); porta=${porta:-$padrao}
  [[ "$porta" =~ ^[0-9]{1,5}$ ]] && [ "$porta" -ge 1024 ] && [ "$porta" -lt 65535 ] || return 1
  if porta_ocupada "$porta" && ! porta_do_asimov "$porta" "$servico"; then
    aviso "A porta $porta já está em uso por outra aplicação."
    while porta_ocupada "$porta"; do porta=$((porta + 1)); [ "$porta" -lt 65535 ] || return 1; done
  fi
  env_set "$chave" "$porta"
}

prepara_rede() {
  local modo ocupada=0 porta
  for porta in 80 443; do
    if porta_ocupada "$porta" && ! porta_do_asimov "$porta" caddy; then ocupada=1; fi
  done
  modo=$(env_get ASIMOV_PROXY)
  if [ "$ocupada" = 1 ] && [ "$modo" != externo ]; then
    info "Vou aproveitar a configuração existente, preservando suas aplicações."
    modo=externo
  fi
  modo=${modo:-proprio}
  case "$modo" in proprio|externo) ;; *) return 1 ;; esac
  env_set ASIMOV_PROXY "$modo"
  escolhe_porta_local ASIMOV_PORTA_API 8000 api || return 1
  API_LOCAL="http://127.0.0.1:$(env_get ASIMOV_PORTA_API)"
  if [ "$modo" = externo ]; then
    escolhe_porta_local ASIMOV_PORTA_HTTP 18080 caddy || return 1
    escolhe_porta_local ASIMOV_PORTA_HTTPS 18443 caddy || return 1
    env_set ASIMOV_HTTP_BIND "127.0.0.1:$(env_get ASIMOV_PORTA_HTTP)"
    env_set ASIMOV_HTTPS_BIND "127.0.0.1:$(env_get ASIMOV_PORTA_HTTPS)"
    env_set ASIMOV_ESQUEMA http
  else
    env_set ASIMOV_HTTP_BIND 80
    env_set ASIMOV_HTTPS_BIND 443
    env_set ASIMOV_ESQUEMA https
  fi
}

# Arquivo próprio importável pelo Caddy do host, também serve de referência para outros proxies.
gera_proxy_externo() {
  local sub painel porta
  sub=$(env_get SUBDOMINIO_BOT); painel=$(env_get SUBDOMINIO_APP)
  porta=$(env_get ASIMOV_PORTA_HTTP)
  # Endereço é dado validado no onboarding. Recusa caracteres de configuração mesmo ao retomar.
  [[ "$sub" =~ ^[a-zA-Z0-9.-]+$ ]] || return 1
  [[ -z "$painel" || "$painel" =~ ^[a-zA-Z0-9.-]+$ ]] || return 1
  {
    printf '# Gerado pelo Asimov. O gateway interno bloqueia /admin.\n'
    printf '%s {\n reverse_proxy 127.0.0.1:%s\n}\n' "$sub" "$porta"
    if [ -n "$painel" ] && painel_ligado; then
      printf '%s {\n reverse_proxy 127.0.0.1:%s\n}\n' "$painel" "$porta"
    fi
  } >"$RAIZ_PROJETO/deploy/proxy-externo.caddy"
}

# dominio_no_caddyfile ARQUIVO DOMINIO: o domínio é endereço de site no próprio arquivo, colado à
# mão, e não no bloco que o Asimov importa.
dominio_no_caddyfile() {
  local arquivo=$1 dominio=${2//./\\.}
  $SUDO grep -Eq "(^|[[:space:],])(https?://)?${dominio}(:[0-9]+)?[[:space:]]*([,{]|$)" "$arquivo" 2>/dev/null
}

# situacao_caddy_host: proprio (o Caddy do Asimov tem as portas 80 e 443), sem_integracao (outro
# proxy, ajustado fora daqui), integrado, manual (o domínio colado à mão no Caddyfile) ou perdido:
# a linha `import` ou o bloco do Asimov sumiram. Perdido deixa o domínio sem HTTPS, e o Chatwoot e o
# WhatsApp oficial param de alcançar os agentes sem nenhum aviso do lado de cá.
situacao_caddy_host() {
  local config snippet sub
  [ "$(env_get ASIMOV_PROXY)" = externo ] || { echo proprio; return 0; }
  estado_tem proxy_host_integrado || { echo sem_integracao; return 0; }
  config=$(estado_get proxy_host_caddyfile || true)
  config=${config:-/etc/caddy/Caddyfile}
  snippet="$(dirname "$config")/asimov.caddy"
  sub=$(env_get SUBDOMINIO_BOT)
  if $SUDO grep -qxF "import $snippet" "$config" 2>/dev/null &&
      $SUDO grep -q '^# Gerado pelo Asimov\.' "$snippet" 2>/dev/null &&
      $SUDO grep -qF "$sub {" "$snippet" 2>/dev/null; then
    echo integrado
  elif dominio_no_caddyfile "$config" "$sub"; then
    echo manual
  else
    echo perdido
  fi
}

# Recupera só a transação do Asimov. Nenhuma configuração alheia é apagada.
restaura_proxy() {
  local backup config_caddy destino
  backup=$(estado_get proxy_transacao)
  [ -n "$backup" ] || return 0
  [[ "$backup" == "$DIR_ESTADO"/caddy-antes.* ]] && [ -f "$backup/alvo" ] || return 1
  config_caddy=$(cat "$backup/alvo"); destino="$(dirname "$config_caddy")/asimov.caddy"
  # Alteração posterior de terceiro exige conciliação, nunca restauração cega.
  if ! $SUDO cmp -s "$config_caddy" "$backup/Caddyfile" &&
      ! $SUDO cmp -s "$config_caddy" "$backup/candidato"; then
    echo "O Caddyfile mudou depois da interrupção. Compare com $backup antes de retomar." >&2
    return 1
  fi
  if [ -e "$destino" ] && ! $SUDO cmp -s "$destino" "$backup/asimov.caddy" &&
      ! $SUDO cmp -s "$destino" "$backup/snippet-novo"; then
    echo "O bloco Asimov mudou depois da interrupção. Compare com $backup." >&2
    return 1
  fi
  $SUDO cp -p "$backup/Caddyfile" "$config_caddy.restaurado" &&
    $SUDO mv -f "$config_caddy.restaurado" "$config_caddy" || return 1
  if [ -f "$backup/asimov.caddy" ]; then
    $SUDO cp -p "$backup/asimov.caddy" "$destino.restaurado" &&
      $SUDO mv -f "$destino.restaurado" "$destino" || return 1
  else
    $SUDO rm -f "$destino" || return 1
  fi
  $SUDO caddy validate --config "$config_caddy" --adapter caddyfile >>"$LOG" 2>&1 || return 1
  if $SUDO systemctl is-active --quiet caddy; then
    $SUDO systemctl reload caddy >>"$LOG" 2>&1 || return 1
  else
    $SUDO systemctl start caddy >>"$LOG" 2>&1 || return 1
  fi
  estado_remove proxy_transacao
}

# Candidato validado antes de substituir; transação persistida sobrevive até a SIGKILL/reboot.
integra_caddy_host() (
  # Sem argumento, o Caddyfile da última integração; na primeira, o padrão do pacote.
  local config_caddy=${1:-} destino backup comando candidato snippet
  [ -n "$config_caddy" ] || config_caddy=$(estado_get proxy_host_caddyfile || true)
  config_caddy=${config_caddy:-/etc/caddy/Caddyfile}
  destino="$(dirname "$config_caddy")/asimov.caddy"
  command -v caddy >/dev/null || return 1
  $SUDO systemctl is-active --quiet caddy || return 1
  comando=$($SUDO systemctl show caddy -p ExecStart --value) || return 1
  [[ "$comando" == *"--config $config_caddy "* || "$comando" == *"--config=$config_caddy "* ]] || return 1
  [ -f "$config_caddy" ] && [ ! -L "$config_caddy" ] && [ ! -L "$destino" ] || return 1
  restaura_proxy || return 1
  # Domínio colado à mão no Caddyfile: importar o bloco do Asimov o definiria duas vezes, e o Caddy
  # recusaria o arquivo inteiro, travando a atualização. O que já funciona fica como está (código 3).
  if dominio_no_caddyfile "$config_caddy" "$(env_get SUBDOMINIO_BOT)"; then
    estado_set proxy_host_caddyfile "$config_caddy"
    estado_set proxy_host_integrado 1
    return 3
  fi
  backup=$(mktemp -d "$DIR_ESTADO/caddy-antes.XXXXXX") || return 1
  printf '%s\n' "$config_caddy" >"$backup/alvo"
  $SUDO cp -p "$config_caddy" "$backup/Caddyfile" || return 1
  if [ -e "$destino" ]; then
    $SUDO grep -q '^# Gerado pelo Asimov\.' "$destino" || return 1
    $SUDO cp -p "$destino" "$backup/asimov.caddy" || return 1
  fi
  candidato=$($SUDO mktemp "${config_caddy}.XXXXXX") || return 1
  snippet=$($SUDO mktemp "${destino}.XXXXXX") || return 1
  trap 'if estado_tem proxy_transacao; then restaura_proxy || true; fi; $SUDO rm -f "$candidato" "$snippet"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  $SUDO install -m 644 "$RAIZ_PROJETO/deploy/proxy-externo.caddy" "$snippet" || return 1
  # Valida junto dos sites existentes, trocando só o import de propriedade do Asimov.
  # shellcheck disable=SC2016  # $0 pertence ao awk.
  $SUDO awk -v alvo="$destino" -v novo="$snippet" '
    $0 == "import " alvo { print "import " novo; achou=1; next }
    { print }
    END { if (!achou) print "\nimport " novo }
  ' "$config_caddy" | $SUDO tee "$candidato" >/dev/null || return 1
  $SUDO caddy validate --config "$candidato" --adapter caddyfile >>"$LOG" 2>&1 || return 1
  # Volta o import para o nome definitivo, já validado com os mesmos bytes.
  # shellcheck disable=SC2016  # $0 pertence ao awk.
  $SUDO awk -v temporario="$snippet" -v alvo="$destino" '
    $0 == "import " temporario { print "import " alvo; next } { print }
  ' "$candidato" >"$backup/candidato" || return 1
  $SUDO install -m 644 "$backup/candidato" "$candidato" || return 1
  cp "$RAIZ_PROJETO/deploy/proxy-externo.caddy" "$backup/snippet-novo" || return 1
  estado_set proxy_transacao "$backup"
  $SUDO mv -f "$snippet" "$destino" && $SUDO mv -f "$candidato" "$config_caddy" || return 1
  $SUDO systemctl reload caddy >>"$LOG" 2>&1 || return 1
  estado_remove proxy_transacao
  estado_set proxy_host_caddyfile "$config_caddy"
  estado_set proxy_host_integrado 1
)

# integra_caddy_ou_explica: 0 com a integração feita ou com o domínio já colado à mão, que fica como
# está; qualquer outro código é falha, com a configuração anterior preservada.
integra_caddy_ou_explica() {
  local codigo=0
  integra_caddy_host || codigo=$?
  if [ "$codigo" = 3 ]; then
    aviso "O Caddy da VPS já tem $(env_get SUBDOMINIO_BOT) colado à mão, fora do Asimov: deixei como está."
    dica "Se ele parar de responder, apague esse bloco do Caddyfile e rode asimov diagnostico."
    return 0
  fi
  return "$codigo"
}

# repara_caddy_host: a integração sumiu (outra ferramenta regravou o Caddyfile, backup restaurado,
# edição à mão). Refaz pela mesma transação da instalação, que valida antes de trocar e preserva os
# outros sites. Não mexe em nada sem o operador confirmar.
repara_caddy_host() {
  [ "$(situacao_caddy_host)" = perdido ] || return 0
  falha "O Caddy da VPS perdeu o endereço $(destaque "$(env_get SUBDOMINIO_BOT)")."
  dica "Sem ele, o Chatwoot e o WhatsApp oficial não alcançam os agentes. O teste no terminal continua funcionando."
  confirma "Refazer a integração agora? Os outros sites da VPS ficam como estão." || return 0
  if gera_proxy_externo && integra_caddy_ou_explica; then
    ok "Integração refeita."
  else
    falha "Não consegui refazer: a configuração anterior foi preservada. Veja $LOG."
    return 1
  fi
}

configura_proxy_externo() {
  [ "$(env_get ASIMOV_PROXY)" = externo ] || return 0
  gera_proxy_externo || return 1
  if estado_tem proxy_host_integrado; then
    integra_caddy_ou_explica || erro_fatal "Não consegui atualizar o proxy existente" "A configuração anterior foi preservada. Veja $LOG."
    return 0
  fi
  if command -v caddy >/dev/null && $SUDO systemctl is-active --quiet caddy; then
    info "Preparando o acesso seguro, preservando os sites existentes..."
    integra_caddy_ou_explica || erro_fatal "Não foi possível preparar o acesso automaticamente" \
      "A instalação está salva. Peça ao suporte para conferir $LOG e rode novamente."
    return 0
  fi
  # Um encaminhamento já feito pelo administrador pode ser reaproveitado.
  if confere_https "$(env_get SUBDOMINIO_BOT)" >>"$LOG" 2>&1; then return 0; fi
  {
    echo "Proxy existente sem integração automática."
    echo "Referência: $RAIZ_PROJETO/deploy/proxy-externo.caddy"
    echo "Encaminhe os domínios ao gateway 127.0.0.1:$(env_get ASIMOV_PORTA_HTTP), preservando Host."
    echo "Proxy em contêiner precisa alcançar o host. Nunca exponha a API administrativa."
  } >>"$LOG"
  erro_fatal "Esta VPS precisa de um ajuste para liberar o acesso" \
    "Suas aplicações foram preservadas. Envie $LOG ao suporte e depois rode novamente."
}
