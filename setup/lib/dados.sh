#!/usr/bin/env bash
# Telas de dados: modo da instalação, configuração e a escolha de IA de cada agente.
# Respostas comuns vão para o estado. Chave de provedor de IA vai para a API, que a guarda cifrada.

nome_bonito() {
  case "$1" in
    openai) echo OpenAI ;;
    anthropic) echo Anthropic ;;
    gemini) echo Gemini ;;
    groq) echo Groq ;;
    assinatura) echo "Assinatura ChatGPT" ;;
  esac
}

# assinatura_vale: a API diz se esta instalação responde contato pela assinatura ChatGPT
# (experimental): modo empresa, Codex vinculado e ASSINATURA_NO_ATENDIMENTO=1, ligado em `asimov ia`.
assinatura_vale() {
  api GET /admin/ia/chaves
  [ "$API_STATUS" = 200 ] && jq -e '.assinatura.disponivel == true' <<<"$API_RESPOSTA" >/dev/null 2>&1
}

# assinatura_oferece: a opção entra na lista quando já vale ou quando pode ser ligada ali mesmo
# (instalação para a própria empresa, Codex vinculado). Instalação retomada pulava a pergunta da
# conta de IA, e a assinatura nunca aparecia na criação do primeiro agente.
assinatura_oferece() {
  assinatura_vale && return 0
  assinatura_cabe && vinculo_ligado
}

# assinatura_explica: o risco aparece toda vez que ela é escolhida, não só quando é ligada.
assinatura_explica() {
  aviso "Experimental: responde pela sua conta do ChatGPT, sem custo por mensagem, dentro do limite do plano."
  dica "A OpenAI indica chave de API para automação e pode limitar a conta: use uma conta só para isto."
}

# provedor_tem_chave provedor: a API diz quais provedores já têm chave guardada (nunca a chave).
provedor_tem_chave() {
  api GET /admin/ia/chaves
  [ "$API_STATUS" = 200 ] && jq -e --arg p "$1" '.com_chave | index($p)' <<<"$API_RESPOSTA" >/dev/null 2>&1
}

# pede_chave provedor: só pergunta se a instalação ainda não tem a chave. Quem testa no provedor e
# guarda cifrada é a API; a chave vale para todo agente e não passa pelo .env.
pede_chave() {
  local provedor=$1 chave
  provedor_tem_chave "$provedor" && return 0
  dica "A chave é pedida uma vez e vale para todo agente que usar a $(nome_bonito "$provedor")."
  while true; do
    pergunta_secreta chave "Chave de API da $(nome_bonito "$provedor")"
    printf '  %sTestando…%s' "$CINZA" "$NORMAL"
    api PUT "/admin/ia/chaves/$provedor" "$(jq -n --arg c "$chave" '{chave: $c}')"
    printf '\r\033[K'
    if [ "$API_STATUS" = 204 ]; then
      ok "Chave da $(nome_bonito "$provedor") válida"
      return 0
    fi
    falha "$(detalhe_erro "$API_RESPOSTA")"
  done
}

# escolhe_modelo_em VAR "rótulo" função opcional provedor...: define VAR como provedor:modelo.
# Com opcional não vazio, a primeira opção é ficar sem modelo (VAR vazia).
escolhe_modelo_em() {
  local __destino=$1 __rotulo=$2 __funcao=$3 __opcional=$4 __op __indice __provedor __modelo __linha __outro
  shift 4
  local -a __provedores=() __nomes=() __modelos=() __sem_assinatura=()
  for __provedor in "$@"; do
    [ "$__funcao" = transcricao ] && [ "$__provedor" = anthropic ] && continue
    __provedores+=("$__provedor")
  done
  [ -n "$__opcional" ] && __nomes+=("Sem fallback")
  for __provedor in "${__provedores[@]}"; do
    if [ "$__provedor" = assinatura ]; then
      __nomes+=("Assinatura ChatGPT  ${CINZA}experimental, sem chave de API${NORMAL}")
    else
      __nomes+=("$(nome_bonito "$__provedor")")
    fi
  done

  echo
  escolha __op "$__rotulo" "${__nomes[@]}"
  if [ -n "$__opcional" ]; then
    if [ "$__op" = 1 ]; then
      printf -v "$__destino" '%s' ""
      return 0
    fi
    __op=$((__op - 1))
  fi
  __provedor=${__provedores[$((__op - 1))]}
  if [ "$__provedor" = assinatura ] && ! assinatura_vale; then
    # Ainda desligada: liga aqui mesmo. Recusou ou não subiu, a escolha volta sem a assinatura.
    assinatura_liga || true
    if ! assinatura_vale; then
      dica "Seguindo com um provedor com chave de API."
      for __outro in "${__provedores[@]}"; do
        [ "$__outro" = assinatura ] || __sem_assinatura+=("$__outro")
      done
      escolhe_modelo_em "$__destino" "$__rotulo" "$__funcao" "$__opcional" "${__sem_assinatura[@]}"
      return 0
    fi
  elif [ "$__provedor" = assinatura ]; then
    assinatura_explica
  else
    pede_chave "$__provedor"
  fi

  api GET "/admin/ia/modelos/$__provedor?funcao=$__funcao"
  if [ "$API_STATUS" = 200 ]; then
    while IFS= read -r __linha; do
      [ -n "$__linha" ] && __modelos+=("${__linha#*:}")
    done < <(jq -r '.[]' <<<"$API_RESPOSTA" 2>/dev/null || true)
  fi
  if [ "${#__modelos[@]}" -eq 0 ]; then
    dica "Não consegui listar os modelos da $(nome_bonito "$__provedor"); digite o nome."
    pergunta __modelo "Modelo"
  else
    escolha __indice "Modelo" "${__modelos[@]}" "${CINZA}outro (digitar)${NORMAL}"
    if [ "$__indice" -gt "${#__modelos[@]}" ]; then
      pergunta __modelo "Nome do modelo"
    else
      __modelo=${__modelos[$((__indice - 1))]}
    fi
  fi
  printf -v "$__destino" '%s' "$__provedor:$__modelo"
}

# escolhe_modelo_do_novo_agente: a IA é escolha de cada agente, feita ao criá-lo. Define
# MODELOS_NOVO_AGENTE (JSON do campo `modelos`). Só a resposta é perguntada: resumo, visão e áudio
# nascem no mesmo provedor e mudam em Editar agente > Modelos.
escolhe_modelo_do_novo_agente() {
  local resposta audio reserva base
  local -a provedores=(openai anthropic gemini groq)
  assinatura_oferece && provedores+=(assinatura)
  dica "Cada agente tem a própria IA. Resumo, imagem e áudio seguem o mesmo provedor"
  dica "e mudam depois em Editar agente > Modelos."
  escolhe_modelo_em resposta "IA que responde o contato" conversa "" "${provedores[@]}"
  MODELOS_NOVO_AGENTE=$(jq -n --arg r "$resposta" '{modelo_conversa: $r}')
  base=${resposta%%:*}
  # Pela assinatura, a reserva com chave é obrigatória: quando a janela de uso acaba, é ela quem
  # responde. Imagem e áudio também saem dela, porque o Codex não lê arquivo nem transcreve.
  if [ "$base" = assinatura ]; then
    echo
    dica "A reserva responde quando a janela de uso da assinatura acaba, e cuida de imagem e áudio."
    escolhe_modelo_em reserva "Reserva, com chave de API" conversa "" openai anthropic gemini groq
    MODELOS_NOVO_AGENTE=$(jq --arg f "$reserva" '. + {modelo_fallback: $f}' <<<"$MODELOS_NOVO_AGENTE")
    base=${reserva%%:*}
  fi
  # A Anthropic não transcreve áudio: sem outro provedor com chave, o áudio precisa de um.
  if [ "$base" = anthropic ] && ! provedor_tem_chave openai && ! provedor_tem_chave groq &&
    ! provedor_tem_chave gemini; then
    dica "A Anthropic não transcreve áudio. Escolha quem transcreve."
    escolhe_modelo_em audio "Transcrição de áudio" transcricao "" openai groq gemini
    MODELOS_NOVO_AGENTE=$(jq --arg a "$audio" '. + {modelo_transcricao: $a}' <<<"$MODELOS_NOVO_AGENTE")
  fi
  echo
}

# limpa_dominio "o que a pessoa digitou": devolve só o domínio base, em minúsculas. Aceita colado
# com https://, www., bot., app., porta, caminho, barra no fim, espaço em volta e ponto final.
limpa_dominio() {
  local d=$1
  d=$(tr '[:upper:]' '[:lower:]' <<<"$d" | tr -d '[:space:]')
  d=${d#*://}
  d=${d#*@}
  d=${d%%/*}
  d=${d%%\?*}
  d=${d%%#*}
  d=${d%%:*}
  while [[ "$d" == .* ]]; do d=${d#.}; done
  while [[ "$d" == *. ]]; do d=${d%.}; done
  # Só tira o prefixo se sobrar um domínio: "app.com" é domínio, "app.exemplo.com" é subdomínio.
  local prefixo
  for prefixo in www. bot. app.; do
    [[ "$d" == "$prefixo"*.* ]] && d=${d#"$prefixo"}
  done
  printf '%s' "$d"
}

valida_dominio() {
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

tela_modo() {
  [ -n "$(env_get MODO_INSTALACAO)" ] && return 0
  secao "Uso"
  local op
  escolha op "Para quem são os agentes?" \
    "Só para a minha empresa" \
    "Para empresas clientes  ${CINZA}revenda: cada empresa com seus agentes${NORMAL}"
  env_set MODO_INSTALACAO "$([ "$op" = 1 ] && echo empresa || echo revenda)"
}

tela_dados() {
  estado_tem dados_confirmados && return 0
  secao "Configuração"

  local dominio email opcao provedor digitado ip
  dica "Domínio dos agentes. Eles ficam em bot.<domínio>."
  while true; do
    pergunta digitado "Domínio" "$(estado_get dominio)"
    dominio=$(limpa_dominio "$digitado")
    if valida_dominio "$dominio"; then
      [ "$dominio" = "$digitado" ] || ok "Entendi $(destaque "$dominio"): os agentes ficam em $(destaque "bot.$dominio")"
      break
    fi
    falha "Domínio inválido. Ex: exemplo.com.br"
  done
  # O registro é pedido aqui, e não só no `tela_dns`, porque o DNS leva minutos para propagar: quem
  # cria agora espera menos na tela seguinte, que não passa enquanto o nome não resolver.
  ip=$(ip_publico)
  echo
  aviso "Precisa de um registro DNS: $(destaque "bot.$dominio") apontando para o IP $(destaque "${ip:-desta VPS}")."
  dica "Crie agora no painel do domínio; a conferência vem na tela seguinte."
  echo
  while true; do
    pergunta email "E-mail para o SSL" "$(estado_get email)"
    [[ "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] && break
    falha "E-mail inválido."
  done
  echo
  # A imagem Ubuntu da Oracle traz um REJECT no iptables que o ufw não vence: o passo de firewall
  # precisa saber disso. A liberação no painel da Oracle é com o operador, antes de instalar.
  escolha provedor "Onde está sua VPS?" \
    "Outro provedor  ${CINZA}Hostinger, HostGator, Contabo, DigitalOcean...${NORMAL}" \
    "Oracle Cloud"
  echo
  dica "É o assistente que move o copiloto do painel, pela assinatura que você já paga."
  escolha opcao "Assistente do copiloto" "Claude Code" "Codex"

  estado_set dominio "$dominio"
  estado_set email "$email"
  env_set DOMINIO_BASE "$dominio"
  env_set SUBDOMINIO_BOT "bot.$dominio"
  env_set EMAIL_SSL "$email"
  env_set AGENTE_CODIGO "$([ "$opcao" = 1 ] && echo claude_code || echo codex)"
  env_set PROVEDOR_VPS "$([ "$provedor" = 2 ] && echo oracle || echo outro)"
  estado_set dados_confirmados "$(date -Is)"
}
