#!/usr/bin/env bash
# Tela 8: menu do operador. Editar, remover e ver consumo, sempre pela API.

# mostra_agente: resumo do AGENTE escolhido.
mostra_agente() {
  local fallback
  fallback=$(jq -r '.modelo_fallback // ""' <<<"$AGENTE")
  campo "Empresa" "$AGENTE_EMPRESA"
  campo "Canal" "$(jq -r '.canal' <<<"$AGENTE")"
  campo "Ritmo" "$(jq -r '{instantaneo: "instantâneo", natural: "natural", reflexivo: "reflexivo", manual: "à mão"}[.ritmo // "natural"] // "natural"' <<<"$AGENTE") ${CINZA}· espera $(jq -r '.buffer_segundos' <<<"$AGENTE") s${NORMAL}"
  campo "Mensagens" "até $(jq -r '.max_mensagens_por_resposta' <<<"$AGENTE") por resposta"
  campo "Resposta" "$(jq -r '.modelo_conversa' <<<"$AGENTE")${fallback:+ ${CINZA}→ $fallback${NORMAL}}"
  campo "Resumo" "$(jq -r '.modelo_auxiliar' <<<"$AGENTE")"
  campo "Visão" "$(jq -r '.modelo_visao' <<<"$AGENTE")"
  campo "Áudio" "$(jq -r '.modelo_transcricao' <<<"$AGENTE")"
  case "$(jq -r '.canal' <<<"$AGENTE")" in
    nativo) campo "Handoff" "aparece na conversa do terminal" ;;
    waha | whatsapp)
      campo "Handoff" "$(nome_do_destino "$(jq -c '.handoff_destino' <<<"$AGENTE")")$(jq -r '
        if .retomada_automatica_horas then "; volta com 👍 ou em \(.retomada_automatica_horas) h"
        else "; volta com 👍 ou /retomar" end' <<<"$AGENTE")"
      campo "Atende" "$(atende_do_agente "$AGENTE")"
      ;;
    *)
      campo "Handoff" "$(nome_do_destino "$(jq -c '.handoff_destino' <<<"$AGENTE")")$(jq -r '
        if .retomada_automatica_horas then "; volta em \(.retomada_automatica_horas) h se ninguém devolver"
        else "; volta quando a conversa voltar para Pendente" end' <<<"$AGENTE")"
      ;;
  esac
  campo "Digitação" "$(jq -r '"\(.digitacao_caracteres_por_segundo) caracteres/s, até \(.digitacao_maximo_segundos) s por mensagem"' <<<"$AGENTE")"
  campo "Ferramentas" "$(jq -r '(.ferramentas // []) | if length == 0 then "nenhuma" else map({calculadora: "calculadora", busca_web: "busca na web"}[.] // .) | join(", ") end' <<<"$AGENTE")"
  campo "Jeito" "$(jq -r '{formal: "formal", normal: "normal", descontraido: "descontraído"}[.tom // "normal"] // "normal"' <<<"$AGENTE"), $(emoji_do_agente "$AGENTE")$(jq -r 'if .restringe_temas then ", só assuntos da empresa" else "" end' <<<"$AGENTE")"
  campo "Humano" "$(jq -r 'if (.transfere_para_humano // true) then "pode passar a conversa para uma pessoa" else "atende até o fim sozinho" end' <<<"$AGENTE")"
}

# salva_agente JSON: PATCH só com os campos do JSON; atualiza AGENTE e deixa o RESULTADO para a
# tela redesenhada mostrar.
salva_agente() {
  api_com_token PATCH "$(caminho_do_agente "$AGENTE")" "$1" "Salvando…"
  if [ "$API_STATUS" = 200 ]; then
    AGENTE=$API_RESPOSTA
    RESULTADO=$(ok "Salvo. Vale a partir da próxima mensagem.")
  else
    RESULTADO=$(falha "$(detalhe_erro "$API_RESPOSTA")")
  fi
  devolve AGENTE RESULTADO
}

# escolhe_modelo_do_agente: pergunta a função e o modelo; define CORPO_MODELO para o PATCH.
# Provedor sem chave pede a chave na hora; a API guarda e ela vale no próximo turno.
escolhe_modelo_do_agente() {
  local op campo funcao rotulo opcional=""
  local -a provedores=(openai anthropic gemini groq)
  echo
  escolha op "Qual modelo" \
    "Resposta ao contato  ${CINZA}$(jq -r '.modelo_conversa' <<<"$AGENTE")${NORMAL}" \
    "Fallback  ${CINZA}$(jq -r '.modelo_fallback // "nenhum"' <<<"$AGENTE")${NORMAL}" \
    "Resumo do handoff  ${CINZA}$(jq -r '.modelo_auxiliar' <<<"$AGENTE")${NORMAL}" \
    "Visão  ${CINZA}$(jq -r '.modelo_visao' <<<"$AGENTE")${NORMAL}" \
    "Áudio  ${CINZA}$(jq -r '.modelo_transcricao' <<<"$AGENTE")${NORMAL}"
  case "$op" in
    1) campo=modelo_conversa funcao=conversa rotulo="Resposta ao contato" ;;
    2) campo=modelo_fallback funcao=conversa rotulo="Fallback, se a resposta falhar" opcional=1 ;;
    3)
      campo=modelo_auxiliar funcao=auxiliar rotulo="Resumo do handoff"
      dica "Só resume a conversa para o atendente: um modelo mais barato costuma bastar."
      ;;
    4) campo=modelo_visao funcao=visao rotulo="Visão (imagens e PDF)" ;;
    *) campo=modelo_transcricao funcao=transcricao rotulo="Transcrição de áudio" ;;
  esac
  escolhe_modelo_em MODELO_ESCOLHIDO "$rotulo" "$funcao" "$opcional" "${provedores[@]}"
  CORPO_MODELO=$(jq -n --arg campo "$campo" --arg modelo "$MODELO_ESCOLHIDO" \
    '{($campo): (if $modelo == "" then null else $modelo end)}')
}

# Cada mudança roda em `com_voltar`: Esc no meio volta para a ficha sem salvar.
fluxo_editar_agente() {
  local op
  local -a rotulos acoes
  secao "Editar agente"
  if ! escolhe_agente; then
    pausa
    return 0
  fi
  RESULTADO=""
  while true; do
    secao "Editar $(jq -r '.nome' <<<"$AGENTE")"
    mostra_agente
    if [ -n "$RESULTADO" ]; then
      echo
      printf '%s\n' "$RESULTADO"
      RESULTADO=""
    fi
    echo
    rotulos=("Nome" "Ritmo" "Mensagens por resposta" "Ferramentas" "Jeito de falar" "Base de conhecimento" "Ver como ele responde" "Modelos")
    acoes=(edita_nome edita_ritmo edita_mensagens edita_ferramentas edita_jeito edita_conhecimento roda_prova edita_modelo)
    # No nativo o handoff aparece no próprio terminal: não há destino para escolher, mas dá para
    # ligar o agente num canal.
    case "$(jq -r '.canal' <<<"$AGENTE")" in
      nativo)
        rotulos+=("Conectar a um canal")
        acoes+=(conecta_canal)
        ;;
      waha)
        rotulos+=("WhatsApp")
        acoes+=(edita_waha)
        ;;
      whatsapp)
        rotulos+=("WhatsApp")
        acoes+=(edita_whatsapp)
        ;;
      *)
        rotulos+=("Handoff")
        acoes+=(edita_handoff)
        ;;
    esac
    rotulos+=("Voltar")
    ESC_ESCOLHE=${#rotulos[@]} escolha op "O que mudar?" "${rotulos[@]}"
    [ "$op" -lt "${#rotulos[@]}" ] || return 0
    com_voltar "${acoes[$((op - 1))]}"
    [ "$FALHOU" = 0 ] || pausa
  done
}

edita_nome() {
  local valor
  if [ "$(jq -r '.canal' <<<"$AGENTE")" = chatwoot ]; then
    dica "Muda também o nome do bot, que aparece nas mensagens no Chatwoot. A pasta do prompt continua a mesma."
  else
    dica "A pasta do prompt continua a mesma."
  fi
  pergunta valor "Nome" "$(jq -r '.nome' <<<"$AGENTE")"
  salva_agente "$(jq -n --arg v "$valor" '{nome: $v}')"
  if [ "$API_STATUS" = 422 ]; then
    printf '%s\n' "$RESULTADO"
    if confirma "Salvar o nome só aqui, sem mudar no Chatwoot?"; then
      salva_agente "$(jq -n --arg v "$valor" '{nome: $v, renomear_no_canal: false}')"
    fi
  fi
}

# Ritmo: espera, leitura e digitação num nome só. Eram dois itens de número no menu, e quem não
# construiu a plataforma não tem como escolher "8 segundos" com informação nenhuma. O painel mostra
# os mesmos três presets, pelo mesmo campo.
edita_ritmo() {
  local op atual ritmo buffer velocidade maximo
  case "$(jq -r '.ritmo // "natural"' <<<"$AGENTE")" in
    instantaneo) atual=1 ;;
    reflexivo) atual=3 ;;
    manual) atual=4 ;;
    *) atual=2 ;;
  esac
  ESCOLHA_ATUAL=$atual escolha op "Em que ritmo ele responde?" \
    "Instantâneo  ${CINZA}responde na hora, sem esperar${NORMAL}" \
    "Natural  ${CINZA}lê, digita e responde como uma pessoa${NORMAL}" \
    "Reflexivo  ${CINZA}espera mais e escreve devagar${NORMAL}" \
    "Ajustar à mão  ${CINZA}os três números${NORMAL}"
  case "$op" in
    1) ritmo=instantaneo ;;
    3) ritmo=reflexivo ;;
    4) ritmo="" ;;
    *) ritmo=natural ;;
  esac
  if [ -n "$ritmo" ]; then
    salva_agente "$(jq -n --arg r "$ritmo" '{ritmo: $r}')"
    return 0
  fi
  dica "Quanto o agente espera o contato parar de mandar mensagens antes de responder."
  pergunta_numero buffer "Segundos de espera (1 a 60)" 1 60 "$(jq -r '.buffer_segundos' <<<"$AGENTE")"
  dica "No celular, uma pessoa digita de 4 a 8 caracteres por segundo."
  pergunta_numero velocidade "Caracteres por segundo (1 a 30)" 1 30 "$(jq -r '.digitacao_caracteres_por_segundo' <<<"$AGENTE")"
  dica "Teto por mensagem, para resposta longa não demorar demais."
  pergunta_numero maximo "Máximo de segundos digitando por mensagem (1 a 30)" 1 30 "$(jq -r '.digitacao_maximo_segundos' <<<"$AGENTE")"
  salva_agente "$(jq -n --argjson b "$buffer" --argjson v "$velocidade" --argjson m "$maximo" \
    '{buffer_segundos: $b, digitacao_caracteres_por_segundo: $v, digitacao_maximo_segundos: $m}')"
}

edita_mensagens() {
  local valor
  pergunta_numero valor "Máximo de mensagens por resposta (1 a 10)" 1 10 "$(jq -r '.max_mensagens_por_resposta' <<<"$AGENTE")"
  salva_agente "$(jq -n --argjson v "$valor" '{max_mensagens_por_resposta: $v}')"
}

edita_ferramentas() {
  local escolhidas
  escolhe_ferramentas escolhidas "$AGENTE"
  salva_agente "$(jq -n --argjson f "$escolhidas" '{ferramentas: $f}')"
}

edita_modelo() {
  escolhe_modelo_do_agente
  salva_agente "$CORPO_MODELO"
}

# fluxo_diagnostico: o que está no ar e em que versão. Sai no `asimov diagnostico`.
# Nasceu de a página pública responder 404 com o arquivo certo no disco: o Caddy estava com a
# configuração antiga em memória, e não havia como ver isso sem entrar nos contêineres.
fluxo_diagnostico() {
  local sub codigo
  sub=$(env_get SUBDOMINIO_BOT)
  secao "Diagnóstico"
  campo "Versão do código" "$VERSAO"
  campo "Versão instalada" "$(estado_get versao)"
  campo "Pasta" "$RAIZ_PROJETO"
  echo
  confere_endereco "API, por dentro" "http://127.0.0.1:8000/health"
  confere_endereco "API, pelo domínio" "https://$sub/health"
  confere_endereco "Política de privacidade" "https://$sub/privacidade"
  confere_endereco "Ícone do app" "https://$sub/icone-app.png"
  confere_endereco "WAHA, por dentro" "http://127.0.0.1:8000/admin/canais/waha" --com-chave
  if painel_ligado; then
    confere_endereco "Painel" "https://$(env_get SUBDOMINIO_APP)/painel/entrar"
  fi
  echo
  mostra_backup
  echo
  if [ "$(estado_get versao)" != "$VERSAO" ]; then
    aviso "A versão instalada não é a do código. Rode: asimov atualizar"
  fi
  dica "404 com o arquivo no lugar é o servidor web com a configuração antiga em memória."
  dica "  cd $RAIZ_PROJETO && source deploy/compose.sh && dc restart caddy"
  dica "  cd $RAIZ_PROJETO && source deploy/compose.sh && dc logs -n 50 api"
}

# mostra_backup: quando foi o último e quantos existem. Backup que ninguém confere não é backup.
mostra_backup() {
  local pasta=${PASTA_BACKUP:-/var/lib/asimov/backups} quando erro_em quantos
  # `estado_get` sai diferente de zero quando a chave não existe, e com `set -e` isso derruba a
  # tela inteira.
  quando=$(estado_get backup_em || true)
  erro_em=$(estado_get backup_falhou || true)
  quantos=$(find "$pasta" -maxdepth 1 -name 'asimov-*.sql.gz' 2>/dev/null | wc -l | tr -d ' ' || true)
  if [ -n "$erro_em" ]; then
    falha "Último backup falhou em $erro_em. Veja o log: $LOG"
    # O dump pode estar íntegro e a falha ser só do .env, dos prompts ou do conhecimento: quem lê a
    # tela precisa saber que existe banco para restaurar.
    if [ -n "$quando" ]; then
      dica "O dump do banco de $quando está em $pasta."
    fi
  elif [ -n "$quando" ]; then
    campo "Backup" "$quando ${CINZA}· $quantos guardados em $pasta${NORMAL}"
  else
    campo "Backup" "nenhum ainda ${CINZA}· roda de madrugada, pelo asimov-backup.timer${NORMAL}"
  fi
}

# confere_endereco "rótulo" URL [--com-chave]: mostra o código HTTP de um endereço.
confere_endereco() {
  local rotulo=$1 url=$2 chave=${3:-} codigo
  if [ -n "$chave" ]; then
    codigo=$(printf 'X-Admin-Key: %s\n' "$(env_get CHAVE_API_ADMIN)" |
      curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H @- "$url" || true)
  else
    codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)
  fi
  if [ "$codigo" = 200 ]; then
    campo "$rotulo" "$(printf '%s✓ %s%s' "$VERDE" "$codigo" "$NORMAL")"
  else
    campo "$rotulo" "$(printf '%s✗ %s%s  %s%s%s' "$VERMELHO" "$codigo" "$NORMAL" "$CINZA" "$url" "$NORMAL")"
  fi
}

# conecta_canal: liga o AGENTE nativo num canal externo. Prompt, modelos, ferramentas e conversas ficam.
conecta_canal() {
  local nome op
  nome=$(jq -r '.nome' <<<"$AGENTE")
  echo
  dica "$nome passa a atender pelo canal com o mesmo prompt, modelos e ferramentas."
  dica "A conversa de teste aqui no terminal continua funcionando."
  echo
  escolha op "Canal" \
    "Chatwoot  ${CINZA}caixa de entrada de um Chatwoot que já existe${NORMAL}" \
    "WhatsApp oficial  ${CINZA}Cloud API da Meta: número homologado, cobrado por mensagem${NORMAL}" \
    "WhatsApp pela WAHA  ${CINZA}seu número, pareado por QR code; API não oficial${NORMAL}"
  case "$op" in
    1) conecta_chatwoot "$nome" ;;
    2) conecta_whatsapp "$nome" ;;
    *) conecta_waha "$nome" ;;
  esac
  devolve AGENTE RESULTADO
}

conecta_chatwoot() {
  local nome=$1 corpo rapido=""
  escolhe_caixa_chatwoot
  pergunta_retomada 4 chatwoot
  ritmo_do_whatsapp && rapido=1

  corpo=$(jq -n --argjson conexao "$CHATWOOT_CONEXAO" --argjson destino "$HANDOFF_DESTINO" \
    --argjson horas "$RETOMADA_HORAS" \
    '{canal: "chatwoot", conexao: $conexao, handoff_destino: $destino, retomada_automatica_horas: $horas}')
  api_com_token POST "$(caminho_do_agente "$AGENTE")/canal" "$corpo" "Criando o bot no Chatwoot…"
  if [ "$API_STATUS" != 200 ]; then
    RESULTADO=$(falha "$(detalhe_erro "$API_RESPOSTA")")
    return 0
  fi
  AGENTE=$API_RESPOSTA
  RESULTADO=$(ok "$(destaque "$nome") no ar na caixa $(destaque "$AGENTE_CAIXA") ${CINZA}· handoff para $(nome_do_destino "$HANDOFF_DESTINO")${NORMAL}")
  [ -n "$rapido" ] && aplica_ritmo_do_whatsapp
  return 0
}

conecta_waha() {
  local nome=$1 rapido=""
  aviso_nao_oficial || return 0
  garante_waha
  prepara_aparelho "$nome" "$AGENTE_EMPRESA"
  pergunta_retomada
  ritmo_do_whatsapp && rapido=1

  api POST "$(caminho_do_agente "$AGENTE")/canal" '{"canal": "waha", "conexao": {}}'
  if [ "$API_STATUS" != 200 ]; then
    RESULTADO=$(falha "$(detalhe_erro "$API_RESPOSTA")")
    return 0
  fi
  AGENTE=$API_RESPOSTA
  api PATCH "$(caminho_do_agente "$AGENTE")" "$(jq -n --argjson h "$RETOMADA_HORAS" '{retomada_automatica_horas: $h}')"
  [ "$API_STATUS" = 200 ] && AGENTE=$API_RESPOSTA
  [ -n "$rapido" ] && aplica_ritmo_do_whatsapp

  if espera_waha "$AGENTE"; then
    escolhe_destino_waha "$AGENTE"
    api PATCH "$(caminho_do_agente "$AGENTE")" "$(jq -n --argjson d "$HANDOFF_DESTINO" '{handoff_destino: $d}')"
    if [ "$API_STATUS" = 200 ]; then
      AGENTE=$API_RESPOSTA
      RESULTADO=$(ok "$(destaque "$nome") atende no WhatsApp $(destaque "+$WAHA_NUMERO") ${CINZA}· handoff para $(nome_do_destino "$HANDOFF_DESTINO")${NORMAL}")
      return 0
    fi
    RESULTADO=$(falha "$(detalhe_erro "$API_RESPOSTA")")
    return 0
  fi
  RESULTADO=$(aviso "$(destaque "$nome") está no WhatsApp, mas o número ainda não foi pareado. Volte em WhatsApp para ler o QR code.")
  return 0
}

# O ritmo de teste (buffer e digitando curtos) parece robô para quem escreve no WhatsApp.
ritmo_do_whatsapp() {
  [ "$(jq -r '.buffer_segundos < 8 or .digitacao_maximo_segundos < 20' <<<"$AGENTE")" = true ] || return 1
  echo
  dica "O ritmo de teste (buffer e digitando curtos) parece robô para quem escreve no WhatsApp."
  confirma "Usar o ritmo do WhatsApp (espera 8 s e digita como uma pessoa)?"
}

aplica_ritmo_do_whatsapp() {
  api PATCH "$(caminho_do_agente "$AGENTE")" '{"buffer_segundos": 8, "digitacao_caracteres_por_segundo": 6, "digitacao_maximo_segundos": 20}'
  if [ "$API_STATUS" = 200 ]; then
    AGENTE=$API_RESPOSTA
  else
    RESULTADO+=$'\n'$(falha "Ritmo não mudou: $(detalhe_erro "$API_RESPOSTA")")
  fi
}

# Tom, emoji, o que ele pode falar e se existe alguém para assumir: é o jeito do agente, e o painel
# tem as mesmas quatro escolhas na mesma rota.
edita_jeito() {
  local op tom humano temas memoria aviso atual
  case "$(jq -r '.tom // "normal"' <<<"$AGENTE")" in
    formal) atual=1 ;;
    descontraido) atual=3 ;;
    *) atual=2 ;;
  esac
  ESCOLHA_ATUAL=$atual escolha op "Como ele fala?" \
    "Formal  ${CINZA}português correto, sem gíria${NORMAL}" \
    "Normal  ${CINZA}como alguém da empresa no WhatsApp${NORMAL}" \
    "Descontraído  ${CINZA}leve e próximo, sem perder o profissional${NORMAL}"
  case "$op" in
    1) tom=formal ;;
    3) tom=descontraido ;;
    *) tom=normal ;;
  esac

  pergunta_emoji "$(jq -r '.emojis' <<<"$AGENTE")"

  dica "Desligado, ele nunca promete que alguém vai assumir: atende até o fim sozinho."
  confirma "Ele pode passar a conversa para uma pessoa?" "$(jq -r '.transfere_para_humano' <<<"$AGENTE")" && humano=true || humano=false
  confirma "Ele só fala de assuntos da empresa?" "$(jq -r '.restringe_temas' <<<"$AGENTE")" && temas=true || temas=false

  dica "Ligado, ele guarda o que ficou combinado com cada contato e não pergunta duas vezes."
  confirma "Ele lembra de cada contato?" "$(jq -r '.memoria_ativa' <<<"$AGENTE")" && memoria=true || memoria=false

  dica "Uma linha na primeira mensagem de cada conversa. Quem atende na União Europeia precisa ligar."
  confirma "Ele avisa que é um assistente virtual?" "$(jq -r '.avisa_que_e_ia' <<<"$AGENTE")" && aviso=true || aviso=false

  salva_agente "$(jq -n --arg t "$tom" --arg e "$EMOJIS" --argjson h "$humano" --argjson r "$temas" \
    --argjson m "$memoria" --argjson a "$aviso" \
    '{tom: $t, emojis: $e, transfere_para_humano: $h, restringe_temas: $r, memoria_ativa: $m, avisa_que_e_ia: $a}')"
}

# O material que o agente sabe além do prompt. O painel tem a mesma coisa na aba Treinamento, pelas
# mesmas rotas: aqui o arquivo já está na VPS, e lá ele sobe pelo navegador.
edita_conhecimento() {
  local op caminho arquivo texto url documento_id documentos linhas
  while true; do
    caminho="$(caminho_do_agente "$AGENTE")/documentos"
    api GET "$caminho"
    exige_api
    documentos=$API_RESPOSTA
    linhas=$(jq -r '.[] | "  \(.nome)  [\(.status)\(if .status == "pronto" then ", \(.total_trechos) trechos" else "" end)]\(if .erro != "" then "  " + .erro else "" end)"' <<<"$documentos")
    if [ -n "$linhas" ]; then
      printf '%s\n\n' "$linhas"
    else
      dica "Ele ainda não sabe nada além do prompt."
    fi

    ESC_ESCOLHE=5 escolha op "Base de conhecimento" \
      "Enviar um arquivo  ${CINZA}PDF, DOCX, TXT ou MD que já está na VPS${NORMAL}" \
      "Ensinar uma frase  ${CINZA}uma afirmação por vez${NORMAL}" \
      "Ensinar por site  ${CINZA}o texto de uma página${NORMAL}" \
      "Remover um material" \
      "Voltar"
    case "$op" in
      1)
        pergunta arquivo "Caminho do arquivo na VPS"
        if [ ! -f "$arquivo" ]; then
          printf '%s\n' "$(falha "Não achei esse arquivo.")"
          continue
        fi
        api_arquivo "$caminho" "$arquivo"
        ;;
      2)
        pergunta texto "O que ele precisa saber"
        api POST "$caminho/texto" "$(jq -n --arg t "$texto" '{texto: $t}')"
        ;;
      3)
        pergunta url "Endereço da página"
        api POST "$caminho/site" "$(jq -n --arg u "$url" '{url: $u}')"
        ;;
      4)
        documento_id=$(escolhe_documento "$documentos") || continue
        api DELETE "$caminho/$documento_id"
        ;;
      *) return 0 ;;
    esac
    if [ "$API_STATUS" = 200 ] || [ "$API_STATUS" = 201 ]; then
      printf '%s\n' "$(ok "Pronto.")"
    else
      printf '%s\n' "$(falha "$(detalhe_erro "$API_RESPOSTA")")"
    fi
    pausa
  done
}

# escolhe_documento JSON: imprime o id escolhido, ou sai diferente de 0 quando não há o que remover.
escolhe_documento() {
  local op quantos
  local -a nomes=()
  quantos=$(jq -r 'length' <<<"$1")
  [ "$quantos" -gt 0 ] || return 1
  while IFS= read -r linha; do nomes+=("$linha"); done < <(jq -r '.[] | .nome' <<<"$1")
  ESC_ESCOLHE=$((quantos + 1)) escolha op "Remover qual?" "${nomes[@]}" "Voltar"
  [ "$op" -le "$quantos" ] || return 1
  jq -r --argjson i "$((op - 1))" '.[$i].id' <<<"$1"
}

# As mesmas cinco perguntas de sempre, com o prompt que está valendo. O painel tem o mesmo botão na
# aba Trabalho, pela mesma rota: aqui o operador lê no terminal, lá ele compara com a rodada anterior.
roda_prova() {
  dica "Cinco perguntas de sempre, com o prompt de agora. Gasta modelo, como uma conversa de verdade."
  api POST "$(caminho_do_agente "$AGENTE")/prova"
  if [ "$API_STATUS" != 200 ]; then
    printf '%s\n' "$(falha "$(detalhe_erro "$API_RESPOSTA")")"
    return 0
  fi
  jq -r --arg cinza "$CINZA" --arg normal "$NORMAL" '.casos[] |
    "\n  \($cinza)\(.pergunta)\($normal)\n  " +
    (if .erro != "" then .erro else (.mensagens | join("\n  ")) end) +
    (if .transferiu then "\n  \($cinza)(passou para uma pessoa)\($normal)" else "" end)' <<<"$API_RESPOSTA"
  echo
}

edita_handoff() {
  configura_handoff "$AGENTE"
  devolve AGENTE RESULTADO
}

fluxo_remover_agente() {
  local nome confirmacao corpo cliente_id canal aguarde="Removendo…"
  secao "Remover agente"
  escolhe_agente || return 0
  nome=$(jq -r '.nome' <<<"$AGENTE")
  cliente_id=$(jq -r '.cliente_id' <<<"$AGENTE")
  canal=$(jq -r '.canal' <<<"$AGENTE")
  echo
  case "$canal" in
    chatwoot)
      aviso "$(destaque "$nome") para de responder na hora e o webhook deixa de valer."
      dica "O bot sai do Chatwoot. Conversas e consumo ficam guardados; o prompt fica em prompts/ e"
      aguarde="Removendo e apagando o bot no Chatwoot…"
      ;;
    whatsapp)
      aviso "$(destaque "$nome") para de responder na hora e o webhook deixa de valer."
      dica "O número continua na Meta, com os webhooks de volta para a URL do app. Conversas e"
      dica "consumo ficam guardados; o prompt fica em prompts/ e"
      aguarde="Removendo e devolvendo o webhook na Meta…"
      ;;
    waha)
      aviso "$(destaque "$nome") para de responder na hora e o número é desconectado."
      dica "O aparelho sai da lista de aparelhos conectados do WhatsApp. Conversas e consumo ficam"
      dica "guardados; o prompt fica em prompts/ e"
      aguarde="Removendo e desconectando o número…"
      ;;
    *)
      aviso "$(destaque "$nome") deixa de conversar no terminal."
      dica "Conversas e consumo ficam guardados; o prompt fica em prompts/ e"
      ;;
  esac
  dica "volta se você criar um agente com o mesmo nome nessa empresa."
  echo
  pergunta confirmacao "Para confirmar, digite $(destaque "$nome")"
  if [ "$(normaliza "$confirmacao")" != "$(normaliza "$nome")" ]; then
    falha "Você digitou $(destaque "$confirmacao"), e o agente se chama $(destaque "$nome"). Nada foi removido."
    return 0
  fi

  corpo=$(jq -n --arg c "$confirmacao" '{confirmacao: $c}')
  api_com_token DELETE "$(caminho_do_agente "$AGENTE")" "$corpo" "$aguarde"
  if [ "$API_STATUS" = 422 ]; then
    falha "$(detalhe_erro "$API_RESPOSTA")"
    confirma "Remover mesmo assim, deixando a conexão no canal?" || return 0
    api DELETE "$(caminho_do_agente "$AGENTE")" "$(jq -c '. + {desconectar_canal: false}' <<<"$corpo")"
  fi
  if [ "$API_STATUS" != 200 ]; then
    falha "$(detalhe_erro "$API_RESPOSTA")"
    return 0
  fi
  ok "$(destaque "$nome") removido"
  if [ "$(jq -r '.canal_desconectado' <<<"$API_RESPOSTA")" != true ]; then
    if [ "$canal" = waha ]; then
      aviso "O número continua conectado: tire o aparelho no WhatsApp, em Aparelhos conectados."
    elif [ "$canal" = whatsapp ]; then
      aviso "O webhook do número continua apontado para cá: tire o override no painel da Meta."
    else
      aviso "O bot continua no Chatwoot: tire ele da caixa de entrada nas configurações de bot da caixa."
    fi
  fi

  [ "$(env_get MODO_INSTALACAO)" = revenda ] || return 0
  api GET "/admin/agentes?cliente_id=$cliente_id"
  [ "$API_STATUS" = 200 ] && [ "$(jq 'length' <<<"$API_RESPOSTA")" -eq 0 ] || return 0
  echo
  if confirma "A empresa $AGENTE_EMPRESA ficou sem agentes. Remover a empresa também?"; then
    api DELETE "/admin/clientes/$cliente_id" "$(jq -n --arg c "$AGENTE_EMPRESA" '{confirmacao: $c}')"
    if [ "$API_STATUS" = 204 ]; then
      ok "Empresa $(destaque "$AGENTE_EMPRESA") removida"
    else
      falha "$(detalhe_erro "$API_RESPOSTA")"
    fi
  fi
}

# Uma linha por empresa (total) e por agente, com 7 e 30 dias lado a lado.
mostra_consumo() {
  local semana mes nivel nome t7 k7 c7 t30 k30 c30 asterisco parcial="" data tipo onde erro op linha
  local filtro="" titulo="Consumo"
  local -a ids=() nomes=()
  api GET /admin/clientes
  exige_api
  while IFS=$'\t' read -r nome linha; do nomes+=("$nome"); ids+=("$linha"); done \
    < <(jq -r '.[] | [.nome, .id] | @tsv' <<<"$API_RESPOSTA")
  if [ "${#ids[@]}" -gt 1 ]; then
    secao "Consumo"
    escolha op "De qual empresa?" "Todas as empresas" "${nomes[@]}"
    if [ "$op" -gt 1 ]; then
      filtro="&cliente_id=${ids[$((op - 2))]}"
      titulo="Consumo · ${nomes[$((op - 2))]}"
    fi
  fi
  api GET "/admin/consumo?dias=7$filtro"
  exige_api
  semana=$API_RESPOSTA
  api GET "/admin/consumo?dias=30$filtro"
  exige_api
  mes=$API_RESPOSTA

  secao "$titulo"
  if [ "$(jq '.agentes | length' <<<"$mes")" -eq 0 ]; then
    dica "Nenhum turno nos últimos 30 dias."
  else
    printf '  %s%s%s%s\n' "$CINZA" "$(coluna "" 22)" "$(coluna "últimos 7 dias" 28)" "últimos 30 dias$NORMAL"
    printf '  %s%s%7s %7s %9s   %7s %7s %9s%s\n' "$CINZA" "$(coluna "" 22)" turnos tokens "US\$" turnos tokens "US\$" "$NORMAL"
    while IFS=$'\x1f' read -r nivel nome t7 k7 c7 t30 k30 c30 asterisco; do
      [ -n "$asterisco" ] && parcial=1
      if [ "$nivel" = empresa ]; then
        printf '  %s%s%7s %7s %9s   %7s %7s %9s%s%s\n' "$NEGRITO" "$(coluna "$nome" 22)" "$t7" "$k7" "$c7" "$t30" "$k30" "$c30" "$asterisco" "$NORMAL"
      else
        printf '    %s%7s %7s %9s   %7s %7s %9s%s\n' "$(coluna "$nome" 20)" "$t7" "$k7" "$c7" "$t30" "$k30" "$c30" "$asterisco"
      fi
    done < <(jq -r --argjson semana "$semana" '
      def soma(lista): {
        turnos: (lista | map(.turnos) | add // 0),
        tokens: (lista | map(.tokens_entrada + .tokens_saida) | add // 0),
        custo: (lista | map(.custo_estimado | tonumber) | add // 0),
        sem_custo: (lista | map(.sem_custo) | add // 0)
      };
      def curto: if . >= 1000000 then "\(. / 100000 | floor / 10)M"
        elif . >= 1000 then "\(. / 1000 | floor)k" else tostring end;
      def dinheiro: (. * 100 | round) as $c | "\($c / 100 | floor).\(($c % 100) + 100 | tostring | .[1:])";
      def linha(nivel; nome; s; m): [nivel, nome, (s.turnos | tostring), (s.tokens | curto), (s.custo | dinheiro),
        (m.turnos | tostring), (m.tokens | curto), (m.custo | dinheiro),
        (if m.sem_custo > 0 then "*" else "" end)] | join("");
      .agentes | group_by(.cliente_id) | sort_by(.[0].cliente) | .[]
      | .[0].cliente_id as $cliente
      | linha("empresa"; .[0].cliente; soma($semana.agentes | map(select(.cliente_id == $cliente))); soma(.)),
        (.[] | .agente_id as $agente
          | linha("agente"; .agente; soma($semana.agentes | map(select(.agente_id == $agente))); soma([.])))
    ' <<<"$mes")
    [ -n "$parcial" ] && dica "* algum modelo não informou o preço: o custo real é maior que o mostrado."
  fi

  echo
  if [ "$(jq '.falhas | length' <<<"$mes")" -eq 0 ]; then
    ok "Nenhuma falha nos últimos 30 dias"
  else
    printf '  %sÚltimas falhas%s\n' "$NEGRITO" "$NORMAL"
    while IFS=$'\x1f' read -r data tipo onde erro; do
      printf '    %s%s%s  %s  %s%s%s\n' "$CINZA" "$data" "$NORMAL" "$(coluna "$tipo" 26)" "$CINZA" "$onde" "$NORMAL"
      [ -n "$erro" ] && printf '                 %s%s%s\n' "$CINZA" "$erro" "$NORMAL"
    done < <(jq -r '.falhas[] | [
        (.criado_em | sub("\\.[0-9]+"; "") | sub("[+]00:00$"; "Z") | fromdateiso8601 | strflocaltime("%d/%m %H:%M")),
        .tipo,
        ([.cliente, .agente] | map(select(. != null)) | join(" · ")),
        ((.detalhe.erro // .detalhe.problemas // "") | tostring | gsub("\\s+"; " ") | .[0:90])
      ] | join("")' <<<"$mes")
    dica "Detalhes: source deploy/compose.sh && dc logs api worker"
  fi
  echo
}

# Cada opção roda em `com_voltar`: Esc em qualquer pergunta volta para este menu, e erro no meio
# mostra o motivo e volta também, em vez de fechar o menu.
menu_operador() {
  local op
  local -a rotulos acoes
  # Uma consulta só ao abrir: número fora do ar deixa o agente mudo e ninguém percebe sozinho.
  avisa_numeros_fora_do_ar
  while true; do
    secao "Menu"
    # A WAHA atualiza sozinha; o aviso aparece aqui quando ela precisou voltar para a versão anterior.
    [ -n "$(estado_get waha_aviso)" ] && aviso "WhatsApp: $(estado_get waha_aviso)"
    if [ -n "${AVISO_WAHA:-}" ]; then
      aviso "Número fora do ar no WhatsApp: $(destaque "$AVISO_WAHA")"
      dica "Leia o QR code de novo em Editar agente > WhatsApp > Parear o número."
    fi
    rotulos=("Criar agente" "Conversar com agente" "Listar agentes" "Editar agente" "Remover agente" "Ver consumo e falhas")
    acoes=(acao_novo_agente fluxo_conversar "com_pausa lista_agentes" fluxo_editar_agente "com_pausa fluxo_remover_agente" "com_pausa mostra_consumo")
    rotulos+=("WhatsApp (WAHA)")
    acoes+=("com_pausa fluxo_waha")
    rotulos+=("Painel no navegador" "Conta de IA" "Token do Chatwoot" "Diagnóstico" "Sair")
    acoes+=("com_pausa fluxo_painel" "com_pausa fluxo_vinculo" "com_pausa fluxo_token_chatwoot" "com_pausa fluxo_diagnostico")
    ESC_ESCOLHE=${#rotulos[@]} escolha op "O que fazer?" "${rotulos[@]}"
    [ "$op" -lt "${#rotulos[@]}" ] || return 0
    # shellcheck disable=SC2086  # a ação pode vir com `com_pausa` na frente
    com_voltar ${acoes[$((op - 1))]}
    [ "$FALHOU" = 0 ] || pausa
  done
}

# O token de administrador fica guardado depois da primeira vez; aqui o operador pode esquecê-lo.
fluxo_token_chatwoot() {
  local op endereco linha
  local -a enderecos=()
  secao "Token do Chatwoot"
  api GET /admin/canais/chatwoot/acessos
  exige_api
  while IFS= read -r linha; do enderecos+=("$linha"); done < <(jq -r '.[].endereco' <<<"$API_RESPOSTA")
  if [ "${#enderecos[@]}" -eq 0 ]; then
    dica "Nenhum token guardado. Ele é pedido na próxima ação que precisar."
    return 0
  fi
  dica "Guardado criptografado. Criar, renomear e remover agente e trocar o handoff usam este token."
  echo
  escolha op "Esquecer o token de" "${enderecos[@]}"
  endereco=${enderecos[$((op - 1))]}
  api DELETE "/admin/canais/chatwoot/acessos?endereco=$(jq -rn --arg e "$endereco" '$e | @uri')"
  if [ "$API_STATUS" = 204 ]; then
    ok "Token esquecido. Será pedido de novo na próxima vez."
  else
    falha "$(detalhe_erro "$API_RESPOSTA")"
  fi
}

com_pausa() {
  "$@"
  pausa
}

novo_agente() {
  secao "Novo agente"
  fluxo_novo_agente
  if [ "$AGENTE_CANAL" = chatwoot ]; then
    dica "Mande uma mensagem na caixa de entrada para testar."
    return 0
  fi
  echo
  if confirma "Conversar com $AGENTE_NOME agora?"; then
    conversa_no_terminal
    AGENTE_CONVERSOU=1
  else
    dica "Para conversar depois: asimov conversar"
  fi
}

acao_novo_agente() {
  AGENTE_CONVERSOU=""
  novo_agente
  # Quem saiu da conversa já leu tudo: volta direto ao menu.
  [ -n "$AGENTE_CONVERSOU" ] || pausa
}
