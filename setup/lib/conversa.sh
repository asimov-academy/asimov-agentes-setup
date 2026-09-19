#!/usr/bin/env bash
# Tela 8, Conversar com agente: o operador é o contato, aqui no terminal. Vale para agente de qualquer
# canal: a conversa de teste responde aqui e não passa pelo canal do agente.
# A mensagem vai pela API, que grava e agenda o buffer; a resposta chega pelo worker e o terminal
# consulta a API a cada segundo enquanto espera, mostrando em que etapa o agente está.

# Máximo de espera por uma resposta: buffer, mídia, modelo e digitando cabem com folga.
CONVERSA_ESPERA_MAXIMA=300
QUADROS_ESPERA=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

fluxo_conversar() {
  secao "Conversar com agente"
  if ! escolhe_agente; then
    pausa
    return 0
  fi
  conversa_no_terminal
}

# conversa_no_terminal: conversa com o AGENTE escolhido até Esc ou /sair.
conversa_no_terminal() {
  local nome caminho cliente_id buffer canal tecla tique=1
  nome=$(jq -r .nome <<<"$AGENTE")
  cliente_id=$(jq -r .cliente_id <<<"$AGENTE")
  buffer=$(jq -r .buffer_segundos <<<"$AGENTE")
  canal=$(jq -r .canal <<<"$AGENTE")
  caminho="$(caminho_do_agente "$AGENTE")/terminal"
  CONVERSA="" CONVERSA_ID="" PROXIMA=0 ESPERANDO=0 ENVIADA_EM=0 RECEBEU=0 HANDOFF_VISTO="" TURNO_VISTO=""
  DIGITANDO=0 RESPONDENDO=0 COMECOU_EM=0 INDICADOR=0 STATUS="" QUADRO=0 DIGITADO="" CONSULTOU_EM=-1
  # Com bash 4+ a linha de status anda 4 vezes por segundo; a API continua sendo consultada 1 vez.
  [ "${BASH_VERSINFO[0]}" -ge 4 ] && tique=0.25

  secao "Conversa com $nome"
  if [ "$canal" != nativo ]; then
    aviso "Conversa de teste: as respostas aparecem só aqui, nada vai para o $canal."
  fi
  dica "Cada linha é uma mensagem, e o agente espera ${buffer} s depois da última para responder."
  dica "/nova outra conversa · /retomar faz o agente voltar a responder · /sair volta"
  echo

  if ! tem_terminal; then
    _conversa_por_linha
    return 0
  fi

  descarta_pendentes
  _conversa_prompt
  while true; do
    le_tecla tecla "$tique"
    case "$tecla" in
      nada) ;;
      enter)
        _conversa_limpa_status
        _prompt "Você"
        printf ': %s\n' "$DIGITADO"
        _conversa_linha "$DIGITADO" || return 0
        DIGITADO=""
        _conversa_mostra ""
        ;;
      esc)
        _conversa_limpa_status
        volta_se_puder
        return 0
        ;;
      apagar)
        if [ -n "$DIGITADO" ]; then
          DIGITADO=${DIGITADO%?}
          printf '\b \b'
        fi
        ;;
      ?)
        DIGITADO+=$tecla
        printf '%s' "$tecla"
        ;;
    esac
    [ "$ESPERANDO" = 1 ] || continue
    # Uma consulta por segundo: digitando rápido não pode esperar a API a cada tecla.
    if [ "$SECONDS" != "$CONSULTOU_EM" ]; then
      CONSULTOU_EM=$SECONDS
      _conversa_consulta
    fi
    _conversa_status
  done
}

_conversa_prompt() {
  printf '\r\033[K'
  _prompt "Você"
  printf ': %s' "$DIGITADO"
}

# Sem terminal (simulação com arquivo de respostas): lê uma linha e espera a resposta inteira.
_conversa_por_linha() {
  local linha
  while true; do
    _prompt "Você"
    printf ': '
    linha=""
    ler linha
    echo
    _conversa_linha "$linha" || return 0
    while [ "$ESPERANDO" = 1 ]; do
      _conversa_consulta
      [ "$ESPERANDO" = 1 ] && sleep 1
    done
  done
}

# _conversa_linha TEXTO: comando ou mensagem. Devolve 1 para sair da conversa.
_conversa_linha() {
  local texto corpo
  texto=$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  case "$texto" in
    "") return 0 ;;
    /sair) return 1 ;;
    /nova)
      CONVERSA="" CONVERSA_ID="" PROXIMA=0 ESPERANDO=0 HANDOFF_VISTO="" TURNO_VISTO="" STATUS=""
      _conversa_mostra "$(dica "Conversa nova: o agente não lembra da anterior.")"
      return 0
      ;;
    /retomar)
      if [ -z "$CONVERSA_ID" ]; then
        _conversa_mostra "$(dica "Nenhuma conversa ainda.")"
        return 0
      fi
      api POST "/admin/clientes/$cliente_id/conversas/$CONVERSA_ID/retomar"
      if [ "$API_STATUS" != 200 ]; then
        _conversa_mostra "$(falha "$(detalhe_erro "$API_RESPOSTA")")"
      elif [ "$(jq -r .retomado <<<"$API_RESPOSTA")" = true ]; then
        HANDOFF_VISTO=""
        _conversa_mostra "$(ok "O agente voltou a responder nesta conversa.")"
      else
        _conversa_mostra "$(dica "A conversa não estava com humano.")"
      fi
      return 0
      ;;
  esac

  corpo=$(jq -n --arg texto "$texto" --arg conversa "$CONVERSA" '{texto: $texto} + (if $conversa == "" then {} else {conversa: $conversa} end)')
  api POST "$caminho" "$corpo"
  if [ "$API_STATUS" != 200 ]; then
    _conversa_mostra "$(falha "$(detalhe_erro "$API_RESPOSTA")")"
    return 0
  fi
  CONVERSA=$(jq -r .conversa <<<"$API_RESPOSTA")
  CONVERSA_ID=$(jq -r .conversa_id <<<"$API_RESPOSTA")
  if [ "$(jq -r .agendada <<<"$API_RESPOSTA")" != true ]; then
    _conversa_mostra "$(aviso "A conversa está com humano e o agente não responde. /retomar devolve a conversa ao agente.")"
    return 0
  fi
  # Mensagem nova recomeça o buffer; se o turno anterior ainda está no ar, a etapa segue a dele.
  [ "$ESPERANDO" = 1 ] || RECEBEU=0 RESPONDENDO=0 DIGITANDO=0
  ESPERANDO=1 ENVIADA_EM=$SECONDS
}

# _conversa_limpa_status: apaga a linha em edição e a de status acima dela; o cursor fica no começo.
_conversa_limpa_status() {
  printf '\r\033[K'
  if [ "$INDICADOR" = 1 ]; then
    printf '\033[1A\r\033[K'
    INDICADOR=0
  fi
}

# _conversa_mostra TEXTO: escreve acima da linha em edição, sem perder o que já foi digitado.
_conversa_mostra() {
  if ! tem_terminal; then
    [ -z "$1" ] || printf '%s\n' "$1"
    return 0
  fi
  _conversa_limpa_status
  [ -z "$1" ] || printf '%s\n' "$1"
  if [ -n "$STATUS" ]; then
    printf '%s\n' "$STATUS"
    INDICADOR=1
  fi
  _conversa_prompt
}

# _conversa_status: etapa atual com animação e tempo, redesenhada acima da linha em edição.
_conversa_status() {
  local quadro etapa="" novo="" passou
  QUADRO=$(((QUADRO + 1) % ${#QUADROS_ESPERA[@]}))
  quadro=${QUADROS_ESPERA[$QUADRO]}
  passou=$((SECONDS - ENVIADA_EM))
  if [ "$ESPERANDO" != 1 ]; then
    etapa=""
  elif [ "$RESPONDENDO" = 0 ] && [ "$RECEBEU" = 0 ] && [ "$passou" -lt "$buffer" ]; then
    etapa="esperando você terminar de escrever · responde em $((buffer - passou)) s"
  elif [ "$RESPONDENDO" = 0 ] && [ "$RECEBEU" = 0 ]; then
    etapa="$nome vai responder · na fila há $((passou - buffer)) s"
  elif [ "$RECEBEU" = 0 ]; then
    etapa="$nome está pensando · $((SECONDS - COMECOU_EM)) s"
  elif [ "$DIGITANDO" = 1 ]; then
    etapa="$nome está digitando"
  else
    etapa="$nome está terminando o turno"
  fi
  [ -z "$etapa" ] || novo="  ${CIANO}${quadro}${NORMAL} ${CINZA}${etapa}${NORMAL}"
  [ "$novo" != "$STATUS" ] || return 0
  STATUS=$novo
  _conversa_mostra ""
}

# _conversa_consulta: mensagens novas do agente, etapa, handoff e, no fim, o resumo do turno. Para de
# esperar quando o agente respondeu e o turno terminou (o handoff chega depois da última mensagem), ou
# passou do tempo máximo.
_conversa_consulta() {
  local saida="" handoff codigo
  api GET "$caminho/$CONVERSA?depois=$PROXIMA"
  if [ "$API_STATUS" != 200 ]; then
    ESPERANDO=0 STATUS=""
    _conversa_mostra "$(falha "$(detalhe_erro "$API_RESPOSTA")")"
    return 0
  fi
  if [ "$(jq '.mensagens | length' <<<"$API_RESPOSTA")" -gt 0 ]; then
    RECEBEU=1
    saida=$(jq -r --arg nome "$nome" --arg ciano "$CIANO$NEGRITO" --arg normal "$NORMAL" \
      '.mensagens[] | "  \($ciano)\($nome):\($normal) \(.texto | gsub("\n"; "\n    "))"' <<<"$API_RESPOSTA")
    PROXIMA=$(jq -r .proxima <<<"$API_RESPOSTA")
  fi
  DIGITANDO=$([ "$(jq -r .digitando <<<"$API_RESPOSTA")" = true ] && echo 1 || echo 0)
  if [ "$(jq -r .respondendo <<<"$API_RESPOSTA")" = true ]; then
    [ "$RESPONDENDO" = 1 ] || COMECOU_EM=$SECONDS
    RESPONDENDO=1
  else
    RESPONDENDO=0
  fi

  handoff=$(jq -c .handoff <<<"$API_RESPOSTA")
  codigo=$(jq -r '.handoff.codigo // ""' <<<"$API_RESPOSTA")
  if [ -n "$codigo" ] && [ "$codigo" != "$HANDOFF_VISTO" ]; then
    HANDOFF_VISTO=$codigo
    saida+="${saida:+$'\n'}$(aviso "Conversa passada para humano · código $(destaque "$codigo")")"
    saida+=$'\n'$(dica "Motivo: $(jq -r .motivo <<<"$handoff")")
    saida+=$'\n'$(jq -r '.resumo' <<<"$handoff" | sed "s/^/  $CINZA/; s/\$/$NORMAL/")
    saida+=$'\n'$(dica "O agente fica calado nesta conversa. /retomar devolve a conversa ao agente.")
  fi

  if [ "$RECEBEU" = 1 ] && [ "$DIGITANDO" = 0 ] && [ "$RESPONDENDO" = 0 ]; then
    ESPERANDO=0 STATUS=""
    saida+="${saida:+$'\n'}$(_conversa_resumo_do_turno)"
    TURNO_VISTO=$(jq -r '.turno.id // ""' <<<"$API_RESPOSTA")
  elif [ $((SECONDS - ENVIADA_EM)) -ge "$CONVERSA_ESPERA_MAXIMA" ]; then
    ESPERANDO=0 STATUS=""
    saida+="${saida:+$'\n'}$(aviso "Sem resposta em $((CONVERSA_ESPERA_MAXIMA / 60)) minutos. Veja em Ver consumo e falhas.")"
  fi
  [ -z "$saida" ] || _conversa_mostra "$saida"
}

# _conversa_resumo_do_turno: tempo, modelo, tokens, custo e ferramentas do turno que acabou.
_conversa_resumo_do_turno() {
  local turno
  turno=$(jq -c '.turno // empty' <<<"$API_RESPOSTA")
  [ -n "$turno" ] || return 0
  [ "$(jq -r .id <<<"$turno")" != "$TURNO_VISTO" ] || return 0
  if [ -n "$(jq -r '.erro // ""' <<<"$turno")" ]; then
    falha "Modelo falhou: $(jq -r '.erro | gsub("\\s+"; " ") | .[0:120]' <<<"$turno")"
    return 0
  fi
  jq -r --arg total "$((SECONDS - ENVIADA_EM))" --arg cinza "$CINZA" --arg verde "$VERDE" --arg normal "$NORMAL" '
    def curto: if . >= 1000 then "\(. / 100 | floor / 10)k" else tostring end;
    def rotulo: {calcular: "calculadora", web_search: "busca na web", duckduckgo_search: "busca na web",
      transferir_para_humano: "passar para humano"}[.] // .;
    ([.ferramentas[] | rotulo] | unique) as $usadas
    | "  \($verde)✓\($normal) \($cinza)resposta em \($total) s · \(.modelo) pensou \(.latencia_ms / 100 | round / 10) s"
      + " · \(.tokens_entrada + .tokens_saida | curto) tokens"
      + (if .custo_estimado == null then "" else " · US$ \(.custo_estimado | tonumber * 10000 | round / 10000)" end)
      + (if ($usadas | length) > 0 then " · usou \($usadas | join(", "))" else "" end)
      + $normal' <<<"$turno"
}
