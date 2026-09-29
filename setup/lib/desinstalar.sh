#!/usr/bin/env bash
# Tela: `asimov desinstalar`. Tira da VPS o que o instalador pôs, e só isso.
#
# Sai: contêineres, volumes, redes e imagens do projeto `asimov`; os timers do backup e da WAHA; o
# comando `asimov`; a integração com o Caddy da VPS (a linha `import` e o `asimov.caddy`); o login no
# registro das imagens; a pasta do projeto (com o .env e os prompts) e o estado em ~/.asimov.
# Fica: Docker, Node, uv e os pacotes do sistema, que a VPS pode usar para outra coisa, a conta do
# Claude Code ou do Codex, que é do operador, e, se ele quiser, os backups.
#
# Cada etapa aceita o que já saiu: interrompida, `asimov desinstalar` de novo continua. A pasta do
# projeto sai por último, porque é nela que o comando mora.

DIR_SYSTEMD="${DIR_SYSTEMD:-/etc/systemd/system}"
LINK_COMANDO="${LINK_COMANDO:-/usr/local/bin/asimov}"
PASTA_DO_SISTEMA="${PASTA_DO_SISTEMA:-/var/lib/asimov}"
PALAVRA_PARA_DESINSTALAR="desinstalar"
UNIDADES_DO_ASIMOV=(asimov-backup.timer asimov-waha.timer asimov-backup.service asimov-waha.service)
# Imagens do Asimov e as de uso geral que o Compose dele puxou. Imagem em uso por outro contêiner
# recusa a remoção, e isso é o certo: ela é de outra aplicação da VPS.
IMAGENS_DO_ASIMOV='^(ghcr\.io/asimov-academy/agentes-|devlikeapro/waha:|pgvector/pgvector:pg16$|redis:7-alpine$|caddy:2-alpine$)'
SESSAO_DO_INSTALADOR="asimov-instalacao"

fluxo_desinstalar() {
  local guardar=0 apagar_backups=0 confirmacao=""
  mkdir -p "$DIR_ESTADO"
  secao "Desinstalar o Asimov"
  info "Sai da VPS tudo o que o Asimov instalou: agentes, conversas, contatos, prompts,"
  info "conexões dos canais, o pareamento do WhatsApp, contêineres, imagens e o comando asimov."
  dica "Ficam o Docker, os pacotes do sistema e a sua conta do Claude Code ou do Codex."
  echo
  aviso "Não tem volta."
  echo
  if confirma "Guardar um backup antes (banco, .env, prompts e conhecimento)?"; then
    guardar=1
  elif [ -d "$PASTA_DO_SISTEMA/backups" ] &&
    confirma "Apagar também os backups que já existem em $PASTA_DO_SISTEMA/backups?" false; then
    apagar_backups=1
  fi
  echo
  pergunta confirmacao "Para confirmar, digite $PALAVRA_PARA_DESINSTALAR"
  if [ "$confirmacao" != "$PALAVRA_PARA_DESINSTALAR" ]; then
    info "Nada foi removido."
    return 0
  fi
  echo

  if [ "$guardar" = 1 ]; then
    etapa_desinstalar "Backup" desinstala_backup || {
      confirma "O backup falhou. Desinstalar mesmo assim, sem backup?" false || {
        info "Nada foi removido. O log está em $LOG."
        return 0
      }
    }
  fi
  etapa_desinstalar "Timers do backup e da WAHA" desinstala_timers || falha_ao_desinstalar
  etapa_desinstalar "Contêineres, volumes e imagens" desinstala_docker || falha_ao_desinstalar
  etapa_desinstalar "Integração com o Caddy da VPS" desinstala_caddy_host || falha_ao_desinstalar
  etapa_desinstalar "Login no registro das imagens" desinstala_registro || falha_ao_desinstalar
  etapa_desinstalar "Sessão do instalador" desinstala_sessao || falha_ao_desinstalar
  etapa_desinstalar "Comando asimov" desinstala_comando || falha_ao_desinstalar
  # O log mora no estado, que sai agora: daqui para frente, só a tela.
  if ! desinstala_pastas "$apagar_backups" >/dev/null 2>&1; then
    falha "Pastas do projeto"
    info "Apague à mão: $RAIZ_PROJETO e $DIR_ESTADO"
    return 1
  fi
  ok "Pastas do projeto e estado"

  echo
  ok "Asimov removido da VPS."
  if [ "$apagar_backups" = 0 ] && [ -d "$PASTA_DO_SISTEMA/backups" ]; then
    info "Backups em $PASTA_DO_SISTEMA/backups (o .env de lá decifra o banco: guarde com cuidado)."
  fi
  echo
  info "Para instalar de novo:"
  info "$(destaque "bash <(curl -sSL $URL_INSTALL)")"
  echo
  dica "No celular do WhatsApp, em Aparelhos conectados, desconecte a VPS."
  dica "No Chatwoot, o bot do agente continua cadastrado até você apagar."
}

# etapa_desinstalar "descrição" comando...: mostra o andamento; a saída do comando vai para o log.
etapa_desinstalar() {
  local descricao=$1
  shift
  printf '  %s…%s %s' "$CIANO" "$NORMAL" "$descricao"
  printf '\n===== %s: desinstalar, %s =====\n' "$(date -Is)" "$descricao" >>"$LOG"
  if "$@" >>"$LOG" 2>&1; then
    printf '\r\033[K'
    ok "$descricao"
    return 0
  fi
  printf '\r\033[K'
  falha "$descricao"
  return 1
}

falha_ao_desinstalar() {
  erro_fatal "A desinstalação parou no meio" \
    "Rode asimov desinstalar de novo: o que já saiu fica de fora, e o resto continua."
}

desinstala_backup() {
  $SUDO env HOME="$HOME" "$RAIZ_PROJETO/deploy/backup.sh"
}

desinstala_timers() {
  local unidade
  if command -v systemctl >/dev/null 2>&1; then
    for unidade in "${UNIDADES_DO_ASIMOV[@]}"; do
      $SUDO systemctl disable --now "$unidade" || true
    done
  fi
  for unidade in "${UNIDADES_DO_ASIMOV[@]}"; do
    $SUDO rm -f "$DIR_SYSTEMD/$unidade" || return 1
  done
  if command -v systemctl >/dev/null 2>&1; then
    $SUDO systemctl daemon-reload || true
  fi
}

# Pelo rótulo do Compose, e não pelo `dc down`: funciona mesmo sem o .env, com perfil desligado ou
# com o arquivo do Compose de outra versão.
desinstala_docker() {
  local filtro="label=com.docker.compose.project=asimov" itens=() imagem
  command -v docker >/dev/null 2>&1 || return 0
  mapfile -t itens < <($SUDO docker ps -aq --filter "$filtro")
  [ "${#itens[@]}" = 0 ] || $SUDO docker rm -f "${itens[@]}" || return 1
  mapfile -t itens < <($SUDO docker volume ls -q --filter "$filtro")
  [ "${#itens[@]}" = 0 ] || $SUDO docker volume rm "${itens[@]}" || return 1
  mapfile -t itens < <($SUDO docker network ls -q --filter "$filtro")
  [ "${#itens[@]}" = 0 ] || $SUDO docker network rm "${itens[@]}" || return 1
  mapfile -t itens < <($SUDO docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -E "$IMAGENS_DO_ASIMOV" || true)
  for imagem in "${itens[@]}"; do
    $SUDO docker image rm "$imagem" || true
  done
}

# O Caddyfile que recebeu o `import`: o registrado na integração, ou o padrão do pacote.
caddyfile_integrado() {
  local alvo
  for alvo in "$DIR_ESTADO"/caddy-antes.*/alvo; do
    if [ -f "$alvo" ]; then
      cat "$alvo"
      return 0
    fi
  done
  printf '/etc/caddy/Caddyfile'
}

# Tira só o que é do Asimov: a linha `import` exata e o snippet com o cabeçalho dele. O resto do
# Caddyfile é de outras aplicações e fica como está.
desinstala_caddy_host() {
  local config snippet candidato
  config=$(caddyfile_integrado)
  snippet="$(dirname "$config")/asimov.caddy"
  if $SUDO test -f "$config" && $SUDO grep -qxF "import $snippet" "$config"; then
    candidato=$($SUDO mktemp "$config.XXXXXX") || return 1
    # shellcheck disable=SC2016  # $0 pertence ao awk.
    $SUDO awk -v linha="import $snippet" '$0 != linha' "$config" | $SUDO tee "$candidato" >/dev/null || {
      $SUDO rm -f "$candidato"
      return 1
    }
    if command -v caddy >/dev/null 2>&1 &&
      ! $SUDO caddy validate --config "$candidato" --adapter caddyfile; then
      $SUDO rm -f "$candidato"
      return 1
    fi
    $SUDO chmod --reference="$config" "$candidato" 2>/dev/null || $SUDO chmod 644 "$candidato"
    $SUDO chown --reference="$config" "$candidato" 2>/dev/null || true
    $SUDO mv -f "$candidato" "$config" || return 1
    if command -v systemctl >/dev/null 2>&1 && $SUDO systemctl is-active --quiet caddy; then
      $SUDO systemctl reload caddy || return 1
    fi
  fi
  if $SUDO test -f "$snippet" && $SUDO grep -q '^# Gerado pelo Asimov\.' "$snippet"; then
    $SUDO rm -f "$snippet" || return 1
  fi
}

desinstala_registro() {
  command -v docker >/dev/null 2>&1 || return 0
  $SUDO docker logout "$(registro_host)" || true
}

# Sessão do tmux que o instalador abriu. Se a desinstalação roda dentro dela, ela fica: fechá-la
# agora mataria este comando no meio.
desinstala_sessao() {
  command -v tmux >/dev/null 2>&1 || return 0
  tmux has-session -t "$SESSAO_DO_INSTALADOR" 2>/dev/null || return 0
  if [ -n "${TMUX:-}" ] && [ "$(tmux display-message -p '#S' 2>/dev/null || true)" = "$SESSAO_DO_INSTALADOR" ]; then
    return 0
  fi
  tmux kill-session -t "$SESSAO_DO_INSTALADOR" || true
}

# Só o link que aponta para esta instalação: outro `asimov` em /usr/local/bin não é nosso.
desinstala_comando() {
  local alvo nosso
  [ -L "$LINK_COMANDO" ] || return 0
  alvo=$(readlink -f "$LINK_COMANDO" 2>/dev/null || true)
  nosso=$(readlink -f "$RAIZ_PROJETO/setup/asimov.sh" 2>/dev/null || true)
  if [ "$alvo" = "$nosso" ] || [ ! -e "$alvo" ]; then
    $SUDO rm -f "$LINK_COMANDO" || return 1
  fi
}

# desinstala_pastas 0|1: 1 apaga também os backups. Confere que as pastas são mesmo do Asimov antes
# do `rm -rf`: um RAIZ_PROJETO errado apagaria a casa do usuário.
desinstala_pastas() {
  local apagar_backups=$1
  [ -f "$RAIZ_PROJETO/setup/asimov.sh" ] && [ -f "$RAIZ_PROJETO/deploy/docker-compose.yml" ] || return 1
  case "$RAIZ_PROJETO" in / | "$HOME" | "$HOME/") return 1 ;; esac
  case "$DIR_ESTADO" in / | "$HOME" | "$HOME/" | "") return 1 ;; esac
  $SUDO rm -rf "$RAIZ_PROJETO" || return 1
  $SUDO rm -rf "$DIR_ESTADO" || return 1
  [ -d "$PASTA_DO_SISTEMA" ] || return 0
  if [ "$apagar_backups" = 1 ]; then
    $SUDO rm -rf "$PASTA_DO_SISTEMA" || return 1
  else
    $SUDO find "$PASTA_DO_SISTEMA" -mindepth 1 -maxdepth 1 ! -name backups -exec rm -rf {} + || return 1
  fi
}
