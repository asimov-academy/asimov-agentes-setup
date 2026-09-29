#!/usr/bin/env bash
# Conta de IA do operador (Claude Code ou Codex) vinculada na VPS.
#
# O setup já instalava o CLI escolhido e parava aí. Vincular a conta é o que liga o copiloto do
# painel: ele conversa com o operador e opera a plataforma pela API, usando a assinatura que o
# operador já paga (Claude Pro ou Max, ChatGPT Plus ou Pro), sem chave de API e sem custo por token.
#
# A credencial nasce e vive onde o CLI oficial a guarda (~/.claude ou ~/.codex, modo 600 dele).
# Nada de segredo entra no .env nem no banco: o .env guarda só que existe vínculo, com qual CLI e
# em que conta, que é o que o painel precisa saber para mostrar ou esconder o copiloto.

ia_e_codex() { [ "$(env_get AGENTE_CODIGO)" = codex ]; }
ia_comando() { ia_e_codex && echo codex || echo claude; }
ia_nome() { ia_e_codex && echo "Codex" || echo "Claude Code"; }
ia_assinatura() { ia_e_codex && echo "ChatGPT Plus ou Pro" || echo "Claude Pro ou Max"; }
ia_dir_credencial() { ia_e_codex && echo "$HOME/.codex" || echo "$HOME/.claude"; }

# O instalador do Claude Code deixa o binário em ~/.local/bin, que pode não estar no PATH desta
# sessão. Sem caminho resolvido, o resto da tela acha que o CLI não foi instalado.
ia_binario() {
  local cli
  cli=$(ia_comando)
  if command -v "$cli" >/dev/null 2>&1; then
    printf '%s' "$cli"
  elif [ -x "$HOME/.local/bin/$cli" ]; then
    printf '%s' "$HOME/.local/bin/$cli"
  fi
}

vinculo_ligado() { [ "$(env_get IA_VINCULADA)" = 1 ]; }

# Agente respondendo contato pela assinatura ChatGPT (experimental). Só cabe na instalação para a
# própria empresa e com o Codex: na revenda seria a conta de uma pessoa atendendo empresas de outros.
assinatura_ligada() { [ "$(env_get ASSINATURA_NO_ATENDIMENTO)" = 1 ]; }
assinatura_cabe() { [ "$(env_get MODO_INSTALACAO)" = empresa ] && ia_e_codex; }

# vinculo_situacao: vinculada, sem_conta ou sem_cli. É o único lugar que sabe como cada CLI
# responde, porque é a primeira coisa a quebrar quando o CLI muda o jeito de guardar o login.
vinculo_situacao() {
  local bin
  bin=$(ia_binario)
  if [ -z "$bin" ]; then
    echo sem_cli
    return 0
  fi
  if ia_e_codex; then
    if "$bin" login status >/dev/null 2>&1; then echo vinculada; else echo sem_conta; fi
  else
    if [ -s "$HOME/.claude/.credentials.json" ]; then echo vinculada; else echo sem_conta; fi
  fi
}

# A conta aparece no resumo e no painel. Não achar o e-mail não é erro: o vínculo vale do mesmo
# jeito, só fica sem o rótulo.
vinculo_conta() {
  local bin saida
  bin=$(ia_binario)
  [ -n "$bin" ] || return 0
  if ia_e_codex; then
    saida=$("$bin" login status 2>/dev/null || true)
  else
    saida=$(grep -o '[[:alnum:]._%+-]\+@[[:alnum:].-]\+\.[[:alpha:]]\{2,\}' "$HOME/.claude/.credentials.json" 2>/dev/null | head -n1 || true)
  fi
  grep -o '[[:alnum:]._%+-]\+@[[:alnum:].-]\+\.[[:alpha:]]\{2,\}' <<<"$saida" | head -n1 || true
}

# O Claude Code guarda o login em ~/.claude/ e o estado do primeiro uso em ~/.claude.json, que fica
# fora da pasta. Sem o segundo, o CLI no contêiner se acha em primeira execução e sai sem responder.
# O Codex guarda tudo em ~/.codex.
ia_arquivo_de_config() { ia_e_codex || printf '%s/.claude.json' "$HOME"; }

vinculo_grava() {
  local dir config
  dir=$(ia_dir_credencial)
  config=$(ia_arquivo_de_config)
  env_set IA_VINCULADA 1
  env_set IA_CLI "$(env_get AGENTE_CODIGO)"
  env_set IA_CONTA "$(vinculo_conta)"
  # O contêiner do copiloto monta esta pasta para usar o mesmo login, sem cópia de credencial.
  env_set CREDENCIAL_IA_HOST "$dir"
  env_set CREDENCIAL_IA_CONTAINER "/home/app/$(basename "$dir")"
  if [ -n "$config" ] && [ -f "$config" ]; then
    env_set CONFIG_IA_HOST "$config"
    env_set CONFIG_IA_CONTAINER "/home/app/$(basename "$config")"
  else
    env_set CONFIG_IA_HOST ""
    env_set CONFIG_IA_CONTAINER ""
  fi
  # O contêiner roda com o dono da credencial, não com o usuário da imagem: o login do operador é
  # 600 do dono dele (root, em quase toda VPS) e um uid diferente não conseguiria nem abrir.
  env_set CREDENCIAL_IA_UID "$(stat -c '%u' "$dir" 2>/dev/null || echo 1000)"
  env_set CREDENCIAL_IA_GID "$(stat -c '%g' "$dir" 2>/dev/null || echo 1000)"
}

vinculo_limpa() {
  env_set IA_VINCULADA ""
  env_set IA_CONTA ""
}

# O login do CLI é interativo e lê do terminal, não do descritor 3 das perguntas do setup. O grupo
# em volta do teste evita que o 2>/dev/null valha para o script inteiro.
ia_tem_tty() { [ -e /dev/tty ] && { : </dev/tty; } 2>/dev/null; }

# ia_roda comando...: roda o CLI com o terminal na entrada, quando existe um.
ia_roda() {
  if ia_tem_tty; then
    "$@" </dev/tty
  else
    "$@"
  fi
}

vinculo_roda_login() {
  local bin dir
  bin=$(ia_binario)
  [ -n "$bin" ] || return 1
  dir=$(ia_dir_credencial)
  mkdir -p "$dir"
  chmod 700 "$dir" 2>/dev/null || true
  if ia_e_codex; then
    # Servidor não abre navegador: o device auth mostra um código para aprovar em outro aparelho.
    ia_roda "$bin" login --device-auth || ia_roda "$bin" login || return 1
  else
    # O Claude Code faz o login na primeira execução: mostra o endereço, recebe de volta o código
    # colado do navegador e cai na conversa. Voltar para o setup é sair dela.
    dica "Faça o login e, quando o Claude Code abrir, digite /exit para voltar ao setup."
    pausa "Enter para abrir o Claude Code"
    ia_roda "$bin" || true
  fi
}

# O contêiner do copiloto só existe para o painel: quem administra pelo terminal não baixa a imagem
# dele. Por isso subir depende das duas coisas, conta vinculada e painel ligado, e quem liga cada
# uma chama esta função. A assinatura no atendimento tem contêiner próprio (`assinatura_acerta`).
copiloto_acerta() {
  if vinculo_ligado && painel_ligado; then
    copiloto_sobe
  else
    copiloto_desce
  fi
}

copiloto_sobe() {
  printf '  %sPreparando o copiloto (leva alguns minutos na primeira vez)…%s' "$CINZA" "$NORMAL"
  env_set COPILOTO_ATIVO 1
  # Sempre recriando: o que muda entre uma vinculação e outra são os volumes da credencial e o
  # usuário do contêiner, e contêiner que já existe não pega nada disso sozinho.
  if ! dc pull copiloto >>"$LOG" 2>&1 || ! dc up -d --force-recreate copiloto >>"$LOG" 2>&1; then
    printf '\r\033[K'
    env_set COPILOTO_ATIVO ""
    aviso "O copiloto não subiu. O painel funciona sem ele; veja o log: $LOG"
    return 1
  fi
  # A API lê o vínculo no boot: sem recriar, o painel seguiria sem o copiloto até alguém reiniciar.
  dc up -d --force-recreate api >>"$LOG" 2>&1 || true
  printf '\r\033[K'
  ok "Copiloto no ar no painel."
}

copiloto_desce() {
  [ "$(env_get COPILOTO_ATIVO)" = 1 ] || return 0
  dc stop copiloto >>"$LOG" 2>&1 || true
  dc rm -f copiloto >>"$LOG" 2>&1 || true
  env_set COPILOTO_ATIVO ""
  dc up -d --force-recreate api >>"$LOG" 2>&1 || true
}

vinculo_entra() {
  local situacao
  if [ -z "$(ia_binario)" ]; then
    falha "$(ia_nome) não está instalado nesta VPS."
    dica "Rode o setup de novo: bash $RAIZ_PROJETO/setup/instalar.sh"
    return 1
  fi
  vinculo_roda_login || true
  situacao=$(vinculo_situacao)
  if [ "$situacao" = vinculada ]; then
    vinculo_grava
    local conta
    conta=$(env_get IA_CONTA)
    ok "Conta de $(ia_nome) vinculada${conta:+ ${CINZA}$conta${NORMAL}}"
    copiloto_acerta || true
    assinatura_ligada && { assinatura_acerta || true; }
    return 0
  fi
  vinculo_limpa
  falha "O login não terminou: $(ia_nome) segue sem conta."
  dica "Você pode tentar de novo a qualquer momento com: asimov ia"
  return 1
}

vinculo_sai() {
  local bin
  confirma "Desvincular a conta? O copiloto do painel para de responder." || return 0
  bin=$(ia_binario)
  if [ -n "$bin" ]; then
    if ia_e_codex; then
      "$bin" logout >>"$LOG" 2>&1 || true
    else
      rm -f "$HOME/.claude/.credentials.json"
    fi
  fi
  vinculo_limpa
  copiloto_desce
  if assinatura_ligada; then
    env_set ASSINATURA_NO_ATENDIMENTO ""
    assinatura_acerta || true
    assinatura_reinicia
  fi
  ok "Conta desvinculada. O painel segue funcionando sem o copiloto."
}

# A API, o worker e o painel leem a opção no boot: sem recriar, a escolha não aparece nem vale.
assinatura_reinicia() {
  local -a servicos=(api worker)
  painel_ligado && servicos+=(painel)
  dc up -d --force-recreate "${servicos[@]}" >>"$LOG" 2>&1 || true
  # A escolha do modelo pergunta à API logo em seguida: ela precisa estar de pé de novo.
  espera_url "${API_LOCAL:-http://127.0.0.1:8000}/health" 24 >>"$LOG" 2>&1 || true
}

# O contêiner `assinatura` roda a imagem pública da plataforma com o Codex dentro: não pede token
# nem painel. Sobe com a opção ligada, a conta vinculada e a instalação cabendo nela; recriado
# sempre, porque o que muda entre um vínculo e outro são a pasta do login e o dono dela.
assinatura_acerta() {
  if assinatura_ligada && vinculo_ligado && assinatura_cabe; then
    printf '  %sPreparando o contêiner da assinatura (leva alguns minutos na primeira vez)…%s' "$CINZA" "$NORMAL"
    if ! dc pull assinatura >>"$LOG" 2>&1 || ! dc up -d --force-recreate assinatura >>"$LOG" 2>&1; then
      printf '\r\033[K'
      return 1
    fi
    printf '\r\033[K'
    ok "Contêiner da assinatura no ar."
  else
    # Com a opção desligada o `dc` já não passa o perfil: ele vai à mão, só para remover.
    dc --profile assinatura rm -sf assinatura >>"$LOG" 2>&1 || true
  fi
}

assinatura_liga() {
  assinatura_explica
  dica "Cada agente escolhe em Editar agente > Modelos, e precisa de uma reserva com chave de API."
  # Padrão Não: é experimento, e Enter segue só com a chave de API, como sempre foi.
  confirma "Deixar os agentes responderem pela assinatura?" false || return 0
  env_set ASSINATURA_NO_ATENDIMENTO 1
  if ! assinatura_acerta; then
    env_set ASSINATURA_NO_ATENDIMENTO ""
    falha "Não liguei: o contêiner da assinatura não subiu. Veja o log: $LOG"
    return 1
  fi
  assinatura_reinicia
  ok "Ligado. Escolha a assinatura em Editar agente > Modelos ou na ficha do painel."
}

assinatura_desliga() {
  confirma "Desligar? Agente que responde pela assinatura passa a responder pela reserva." || return 0
  env_set ASSINATURA_NO_ATENDIMENTO ""
  assinatura_acerta || true
  assinatura_reinicia
  ok "Desligado. Os agentes respondem pela chave de API."
}

# Trocar de CLI troca o motor do copiloto, que lê AGENTE_CODIGO. O login do CLI novo é pedido na hora, senão o operador fica sem copiloto sem saber.
vinculo_troca_cli() {
  local op atual
  atual=$(env_get AGENTE_CODIGO)
  ESCOLHA_ATUAL=$([ "$atual" = codex ] && echo 2 || echo 1) \
    escolha op "Qual assistente usar" "Claude Code" "Codex"
  local novo
  novo=$([ "$op" = 1 ] && echo claude_code || echo codex)
  [ "$novo" = "$atual" ] && { dica "Nada mudou."; return 0; }
  env_set AGENTE_CODIGO "$novo"
  vinculo_limpa
  # A imagem do copiloto leva o CLI dentro: trocar de assistente pede contêiner novo.
  copiloto_desce
  # A assinatura no atendimento é só do Codex: trocar de assistente a desliga.
  if assinatura_ligada; then
    env_set ASSINATURA_NO_ATENDIMENTO ""
    assinatura_acerta || true
    assinatura_reinicia
  fi
  ok "Assistente agora é $(ia_nome)."
  if [ -z "$(ia_binario)" ]; then
    aviso "$(ia_nome) ainda não está instalado. Rode: bash $RAIZ_PROJETO/setup/instalar.sh"
    return 0
  fi
  confirma "Vincular a conta de $(ia_nome) agora?" || return 0
  vinculo_entra || true
}

# Tela do menu e do comando `asimov ia`.
fluxo_vinculo() {
  local op situacao
  local -a rotulos acoes
  situacao=$(vinculo_situacao)

  secao "Conta de IA"
  campo "Assistente" "$(ia_nome)"
  case "$situacao" in
    vinculada) campo "Conta" "$(env_get IA_CONTA)" ;;
    sem_conta) campo "Conta" "ainda sem login" ;;
    sem_cli) campo "Conta" "$(ia_nome) não instalado" ;;
  esac
  campo "Copiloto" "$(vinculo_ligado && echo "ligado no painel" || echo "desligado")"
  if assinatura_cabe; then
    campo "Atendimento" "$(assinatura_ligada && echo "pode responder pela assinatura" || echo "só pela chave de API")"
  fi
  echo

  # O .env pode estar desencontrado do CLI: alguém deslogou por fora, ou o login expirou.
  if [ "$situacao" = vinculada ] && ! vinculo_ligado; then
    vinculo_grava
    ok "Login encontrado: copiloto ligado."
    echo
  elif [ "$situacao" != vinculada ] && vinculo_ligado; then
    vinculo_limpa
    aviso "O login do $(ia_nome) não vale mais. Vincule de novo para ter o copiloto."
    echo
  fi

  if [ "$situacao" = vinculada ]; then
    rotulos=("Trocar de assistente" "Desvincular a conta")
    acoes=(vinculo_troca_cli vinculo_sai)
    if assinatura_cabe && assinatura_ligada; then
      rotulos+=("Parar de responder contatos pela assinatura")
      acoes+=(assinatura_desliga)
    elif assinatura_cabe; then
      rotulos+=("Responder contatos pela assinatura  ${CINZA}experimental${NORMAL}")
      acoes+=(assinatura_liga)
    fi
    rotulos+=("Voltar")
  else
    rotulos=("Vincular a conta agora" "Trocar de assistente" "Voltar")
    acoes=(vinculo_entra vinculo_troca_cli)
  fi
  ESC_ESCOLHE=${#rotulos[@]} escolha op "O que fazer?" "${rotulos[@]}"
  [ "$op" -lt "${#rotulos[@]}" ] || return 0
  "${acoes[$((op - 1))]}" || true
}

# Oferece o vínculo uma vez, na instalação e na primeira atualização de quem já tinha instalado.
# Quem pula segue com tudo funcionando: só o copiloto do painel fica de fora.
tela_vinculo_ia() {
  estado_tem ia_perguntada && return 0
  if [ "$(vinculo_situacao)" = vinculada ]; then
    vinculo_grava
    estado_set ia_perguntada "$(date -Is)"
    return 0
  fi

  secao "Conta de IA"
  info "Você escolheu o $(destaque "$(ia_nome)"). Entrando na sua conta agora,"
  info "o painel no navegador ganha um copiloto que cria e ajusta agente conversando com você."
  echo
  dica "Roda pela sua assinatura ($(ia_assinatura)), sem chave de API e sem custo por token."
  echo

  if confirma "Entrar na sua conta de $(ia_nome) agora?"; then
    vinculo_entra || true
    # Na instalação para a própria empresa com o Codex, a mesma conta pode responder os contatos.
    # Perguntado aqui, antes do primeiro agente, para ele já poder nascer pela assinatura.
    if vinculo_ligado && assinatura_cabe && ! assinatura_ligada; then
      echo
      assinatura_liga || true
    fi
    pausa
  else
    dica "Quando quiser: asimov ia"
  fi
  estado_set ia_perguntada "$(date -Is)"
}
