#!/usr/bin/env bash
# Inventário e reconciliação. Marcador não é prova de serviço saudável.
trava_instalacao() {
  [ "${ASIMOV_LOCK:-}" = 1 ] && return 0
  command -v flock >/dev/null || erro_fatal "Falta flock (util-linux)" "Instale util-linux e rode novamente."
  exec 9>"$DIR_ESTADO/instalacao.lock"
  flock -n 9 || erro_fatal "Outra instalação está em andamento" "Reconecte com: tmux attach -t asimov-instalacao"
  export ASIMOV_LOCK=1
}

inventario_instalacao() {
  restaura_proxy || erro_fatal "Configuração do proxy pendente" "Confira o backup indicado no estado antes de continuar."
  secao "Conferindo a VPS"
  info "O progresso salvo será conferido. Dados, credenciais e aplicações existentes serão preservados."
  $SUDO ss -ltnpH '( sport = :80 or sport = :443 or sport = :8000 )' 2>/dev/null || true
  if command -v docker >/dev/null 2>&1; then
    $SUDO docker ps -a --filter label=com.docker.compose.project=asimov \
      --format '  {{.Names}}: {{.Status}} | {{.Ports}}' || return 1
  fi
  # Uma instalação com dados e sem chave não pode gerar outra chave e perder acesso aos dados.
  local volumes="" chave id arquivos
  if command -v docker >/dev/null 2>&1; then
    for id in $($SUDO docker ps -aq --filter label=com.docker.compose.project=asimov); do
      arquivos=$($SUDO docker inspect --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$id") || return 1
      [[ "$arquivos" == "$RAIZ_PROJETO/deploy/docker-compose.yml" || "$arquivos" == "$RAIZ_PROJETO/deploy/docker-compose.yml,"* ]] ||
        erro_fatal "Já existe outro projeto Docker chamado asimov" "Use o diretório original da instalação. Nenhum contêiner foi alterado."
    done
    volumes=$($SUDO docker volume ls -q --filter label=com.docker.compose.project=asimov) || return 1
  fi
  if [ -n "$volumes" ]; then
    for chave in POSTGRES_PASSWORD CHAVE_CRIPTOGRAFIA CHAVE_API_ADMIN; do
      [ -n "$(env_get "$chave")" ] || erro_fatal "Há dados do Asimov, mas falta $chave" \
        "Restaure o .env do backup antes de continuar. Nenhuma chave foi substituída."
    done
  fi
}

# Checagens não usam a API de outra aplicação que por acaso esteja na porta esperada.
servico_rodando() {
  local id
  id=$(dc ps -q "$1") || return 1
  [ -n "$id" ] || return 1
  [ "$($SUDO docker inspect --format '{{.State.Running}}' "$id")" = true ]
}

confere_passo() {
  case "$1" in
    ubuntu) verifica_ubuntu ;;
    recursos|update|upgrade|firewall) return 0 ;;
    base) dpkg-query -W -f='${Status}\n' sudo apt-utils dialog 2>/dev/null | awk '$0 != "install ok installed" { ruim=1 } END { exit ruim }' ;;
    ferramentas) command -v jq >/dev/null && command -v curl >/dev/null && command -v dig >/dev/null && command -v qrencode >/dev/null ;;
    python) command -v python3 >/dev/null && command -v ufw >/dev/null ;;
    docker) $SUDO docker info >/dev/null 2>&1 && $SUDO docker compose version >/dev/null 2>&1 ;;
    agente_codigo) if [ "$(env_get AGENTE_CODIGO)" = codex ]; then command -v codex >/dev/null; else command -v claude >/dev/null || [ -x "$HOME/.local/bin/claude" ]; fi ;;
    segredos) local chave; for chave in POSTGRES_USER POSTGRES_DB POSTGRES_PASSWORD CHAVE_API_ADMIN CHAVE_CRIPTOGRAFIA WAHA_API_KEY; do [ -n "$(env_get "$chave")" ] || return 1; done ;;
    imagens) local registro; registro=$(env_get ASIMOV_REGISTRO); $SUDO docker image inspect "${registro:-ghcr.io/asimov-academy}/agentes-backend:v$VERSAO" >/dev/null 2>&1 ;;
    # Ações idempotentes: reaplicar confere configuração, migrações e timers atuais.
    *) return 1 ;;
  esac
}

confere_api_local() {
  servico_rodando api || return 1
  espera_url "$API_LOCAL/health" 24
}

confere_https() {
  local sub=$1 codigo=000 resultado=0 corpo
  servico_rodando caddy || { echo "O Caddy do Asimov não está rodando."; return 1; }
  corpo=$(mktemp) || return 1
  for _ in $(seq 1 24); do
    resultado=0
    codigo=$(curl -sS -o "$corpo" -w '%{http_code}' --connect-timeout 5 --max-time 10 "https://$sub/health") || resultado=$?
    if [ "$resultado" -eq 0 ] && [ "$codigo" = 200 ] &&
        jq -e '.api == "ok" and .banco == "ok" and .redis == "ok" and (.worker == "ok" or .worker == "aguardando")' "$corpo" >/dev/null 2>&1; then
      rm -f "$corpo"
      return 0
    fi
    printf 'HTTPS: tentativa %s/24, curl=%s HTTP=%s\n' "$_" "$resultado" "$codigo"
    sleep 5
  done
  rm -f "$corpo"
  case "$resultado" in
    6) echo "DNS: o domínio não foi resolvido." ;;
    7|28) echo "Conexão: confira encaminhamento no proxy e firewall da VPS/provedor." ;;
    60) echo "TLS: certificado ausente, inválido ou de outro domínio." ;;
    *) echo "HTTPS respondeu HTTP $codigo. Confira o proxy e a saúde da API; não é necessariamente erro de certificado." ;;
  esac
  echo "Diagnóstico: cd $RAIZ_PROJETO && source deploy/compose.sh && dc ps"
  return 1
}
