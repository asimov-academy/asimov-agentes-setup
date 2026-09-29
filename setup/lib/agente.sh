#!/usr/bin/env bash
# Tela 6: primeiro agente. Tudo passa pela API; o setup nunca toca no banco.
# O token de administrador do Chatwoot só vive nesta tela: a API cria o bot e o descarta.

API_LOCAL="http://127.0.0.1:$(env_get ASIMOV_PORTA_API)"
[ "$API_LOCAL" != "http://127.0.0.1:" ] || API_LOCAL="http://127.0.0.1:8000"

# api MÉTODO CAMINHO [JSON]: grava o status HTTP em API_STATUS e o corpo em API_RESPOSTA.
# Não chame dentro de $(...): as variáveis se perderiam na subshell.
#
# O corpo vai por arquivo, não por argumento: ele carrega token de canal, e argumento de processo
# é legível por qualquer usuário da máquina com `ps` (auditoria de 2026-09-18, A13). A chave
# administrativa já ia pela entrada padrão pelo mesmo motivo.
api() {
  local metodo=$1 caminho=$2 corpo=${3:-} saida arquivo=""
  local dados=()
  saida=$(mktemp)
  if [ -n "$corpo" ]; then
    arquivo=$(mktemp)
    chmod 600 "$arquivo"
    printf '%s' "$corpo" >"$arquivo"
    dados=(--data-binary "@$arquivo")
  fi
  API_STATUS=$(printf 'X-Admin-Key: %s\n' "$(env_get CHAVE_API_ADMIN)" |
    curl -s -o "$saida" -w '%{http_code}' -X "$metodo" -H @- \
      -H 'Content-Type: application/json' "${dados[@]}" "$API_LOCAL$caminho" || true)
  API_RESPOSTA=$(cat "$saida")
  rm -f "$saida" ${arquivo:+"$arquivo"}
}

# api_arquivo CAMINHO_DA_API ARQUIVO: envia um arquivo do disco da VPS por multipart.
# O `api` manda JSON; base de conhecimento manda arquivo, e é a única rota assim.
api_arquivo() {
  local caminho=$1 arquivo=$2 saida
  saida=$(mktemp)
  API_STATUS=$(printf 'X-Admin-Key: %s\n' "$(env_get CHAVE_API_ADMIN)" |
    curl -s -o "$saida" -w '%{http_code}' -X POST -H @- \
      -F "arquivo=@$arquivo" "$API_LOCAL$caminho" || true)
  API_RESPOSTA=$(cat "$saida")
  rm -f "$saida"
}

# exige_api: para o comando quando a última chamada não deu 200.
exige_api() {
  [ "$API_STATUS" = 200 ] || erro_fatal "A API não respondeu" "Veja: source deploy/compose.sh && dc logs api"
}

detalhe_erro() {
  if [ "$API_STATUS" = "000" ] || [ -z "$1" ]; then
    echo "a API não respondeu em $API_LOCAL. Veja: source deploy/compose.sh && dc logs api"
    return 0
  fi
  jq -r '.detail | if type == "string" then . else (map(.msg) | join("; ")) end' 2>/dev/null <<<"$1" || echo "$1"
}

# escolhe_empresa "nome sugerido": define EMPRESA_ID e EMPRESA_NOME.
# Modo empresa: uma empresa só, criada no primeiro agente. Modo revenda: existente ou nova.
escolhe_empresa() {
  local sugerido=$1 op nome corpo id
  local -a ids nomes
  EMPRESA_ID="" EMPRESA_NOME=""

  api GET /admin/clientes
  ids=() nomes=()
  if [ "$API_STATUS" = 200 ]; then
    while IFS=$'\t' read -r id nome; do ids+=("$id"); nomes+=("$nome"); done \
      < <(jq -r '.[] | [.id, .nome] | @tsv' <<<"$API_RESPOSTA")
  fi

  if [ "$(env_get MODO_INSTALACAO)" = empresa ] && [ "${#ids[@]}" -gt 0 ]; then
    EMPRESA_ID=${ids[0]} EMPRESA_NOME=${nomes[0]}
    return 0
  fi

  if [ "$(env_get MODO_INSTALACAO)" = revenda ] && [ "${#ids[@]}" -gt 0 ]; then
    echo
    escolha op "Empresa" "${nomes[@]}" "${CIANO}+ nova empresa${NORMAL}"
    if [ "$op" -le "${#ids[@]}" ]; then
      EMPRESA_ID=${ids[$((op - 1))]} EMPRESA_NOME=${nomes[$((op - 1))]}
      return 0
    fi
  fi

  while true; do
    pergunta nome "$([ "$(env_get MODO_INSTALACAO)" = empresa ] && echo 'Nome da sua empresa' || echo 'Nome da empresa cliente')" "$sugerido"
    corpo=$(jq -n --arg nome "$nome" '{nome: $nome}')
    api POST /admin/clientes "$corpo"
    if [ "$API_STATUS" = 201 ]; then
      EMPRESA_ID=$(jq -r .id <<<"$API_RESPOSTA") EMPRESA_NOME=$nome
      return 0
    fi
    falha "$(detalhe_erro "$API_RESPOSTA")"
    sugerido=""
  done
}

# api_com_token MÉTODO CAMINHO JSON "aguarde": como `api`, mas se a API pedir o token de
# administrador do Chatwoot (428: nenhum guardado, ou o guardado foi recusado), pergunta e repete com
# ele em `conexao.token_admin`. A API guarda o token que funcionar: ele é pedido uma vez só.
api_com_token() {
  local metodo=$1 caminho=$2 corpo=$3 aguarde=${4:-} token tentou=""
  while true; do
    [ -n "$aguarde" ] && printf '  %s%s%s' "$CINZA" "$aguarde" "$NORMAL"
    api "$metodo" "$caminho" "$corpo"
    [ -n "$aguarde" ] && printf '\r\033[K'
    [ "$API_STATUS" = 428 ] || return 0
    if [ -n "$tentou" ]; then
      falha "$(detalhe_erro "$API_RESPOSTA")"
    else
      dica "Token de administrador: no Chatwoot, avatar > Configurações do perfil > Token de acesso."
      dica "Fica guardado criptografado; só é pedido de novo se o Chatwoot recusar."
    fi
    pergunta_secreta token "Token de acesso do Chatwoot"
    # Pelo ambiente, não por argumento: `jq --arg token` apareceria em `ps` (A13).
    corpo=$(ASIMOV_TOKEN="$token" jq -c \
      '.conexao = ((.conexao // {}) + {token_admin: env.ASIMOV_TOKEN})' <<<"$corpo")
    unset token
    tentou=1
  done
}

# acessa_chatwoot [URL]: preenche CHATWOOT_URL e CHATWOOT_CONTAS (JSON da API).
# Com URL (agente que já existe) não pergunta o endereço e devolve 1 se o Chatwoot falhar.
acessa_chatwoot() {
  local corpo url_fixa=${1:-}
  while true; do
    if [ -n "$url_fixa" ]; then
      CHATWOOT_URL=$url_fixa
    else
      pergunta CHATWOOT_URL "URL do Chatwoot" "$(estado_get chatwoot_url)"
    fi
    CHATWOOT_URL=${CHATWOOT_URL%%/app*}
    CHATWOOT_URL=${CHATWOOT_URL%/}
    corpo=$(jq -n --arg url "$CHATWOOT_URL" '{conexao: {url: $url}}')
    api_com_token POST /admin/canais/chatwoot/descobrir "$corpo" "Conectando…"
    if [ "$API_STATUS" = 200 ]; then
      estado_set chatwoot_url "$CHATWOOT_URL"
      CHATWOOT_CONTAS=$API_RESPOSTA
      return 0
    fi
    falha "$(detalhe_erro "$API_RESPOSTA")"
    [ -z "$url_fixa" ] || return 1
  done
}

# escolha_da_lista VAR "texto" JSON_ARRAY_DE_NOMES -> índice (0..n-1). Uma opção só: escolhe sozinho.
escolha_da_lista() {
  local __var=$1 texto=$2 lista=$3 numero linha
  local -a nomes=()
  while IFS= read -r linha; do nomes+=("$linha"); done < <(jq -r '.[]' <<<"$lista")
  if [ "${#nomes[@]}" -eq 1 ]; then
    ok "$texto: $(destaque "${nomes[0]}")"
    printf -v "$__var" '%s' 0
    return 0
  fi
  echo
  escolha numero "$texto" "${nomes[@]}"
  printf -v "$__var" '%s' "$((numero - 1))"
}

# escolhe_destino_handoff JSON_DA_CONTA: define HANDOFF_DESTINO (JSON) para quem chamou.
# Times primeiro, depois atendentes, e a caixa sem atribuição por último.
escolhe_destino_handoff() {
  local conta=$1 opcoes linha op
  local -a rotulos=()
  opcoes=$(jq -c '[(.times // [])[] | {tipo: "time", id, nome}]
    + [(.atendentes // [])[] | {tipo: "usuario", id, nome}]
    + [{tipo: "caixa", id: null, nome: null}]' <<<"$conta")
  while IFS= read -r linha; do rotulos+=("$linha"); done < <(jq -r --arg cinza "$CINZA" --arg normal "$NORMAL" '.[]
    | if .tipo == "time" then "\(.nome)  \($cinza)time\($normal)"
      elif .tipo == "usuario" then "\(.nome)"
      else "Quem estiver na caixa  \($cinza)sem atribuir\($normal)" end' <<<"$opcoes")
  echo
  dica "Quando o agente passar a conversa para uma pessoa, ela vai para quem você escolher."
  escolha op "Quem recebe o handoff" "${rotulos[@]}"
  HANDOFF_DESTINO=$(jq -c ".[$((op - 1))]" <<<"$opcoes")
}

# Serve aos dois canais: o tipo do destino diz de qual é (caixa, time e usuário no Chatwoot;
# número e grupo na WAHA).
nome_do_destino() {
  jq -r 'if . == null then "sem destino"
    elif .tipo == "caixa" then "quem estiver na caixa"
    elif .tipo == "time" then "time \(.nome // .id)"
    elif .tipo == "grupo" then "grupo \(.nome // .chat_id)"
    elif .tipo == "numero" then "+\(.telefone // (.chat_id | split("@")[0]))"
    else (.nome // "usuário \(.id)") end' <<<"$1"
}

# Canal primeiro, depois o fluxo dele. Define AGENTE_* para quem chamou.
fluxo_novo_agente() {
  local op
  AGENTE_CAIXA=""
  escolha op "Canal" \
    "Chatwoot  ${CINZA}caixa de entrada de um Chatwoot que já existe${NORMAL}" \
    "WhatsApp oficial  ${CINZA}Cloud API da Meta: número homologado, cobrado por mensagem${NORMAL}" \
    "WhatsApp pela WAHA  ${CINZA}seu número, pareado por QR code; API não oficial${NORMAL}" \
    "Nativo  ${CINZA}sem canal: você conversa com ele aqui no terminal${NORMAL}"
  echo
  escolhe_modelo_do_novo_agente
  case "$op" in
    1) fluxo_agente_chatwoot ;;
    2) fluxo_agente_whatsapp ;;
    3) fluxo_agente_waha ;;
    *) fluxo_agente_nativo ;;
  esac
}

# Nome → empresa → ritmo → ferramentas → cria. Nada para conectar: serve para testar prompt e ferramentas no terminal.
# Agente nasce cru (decisão do operador): o resto se ajusta em Editar agente ou no painel.
fluxo_agente_nativo() {
  local nome corpo ferramentas
  AGENTE_CANAL=nativo
  dica "Mesmo buffer, digitando, ferramentas, consumo e handoff dos outros canais; não atende ninguém de fora."
  pergunta nome "Nome do agente"
  escolhe_empresa ""
  configura_ritmo_novo
  escolhe_ferramentas ferramentas ""
  pergunta_emoji
  while true; do
    corpo=$(jq -n --arg nome "$nome" --argjson ajustes "$AJUSTES_AGENTE" --argjson f "$ferramentas" \
      --arg emojis "$EMOJIS" \
      '{nome: $nome, canal: "nativo", ferramentas: $f, emojis: $emojis} + $ajustes')
    api POST "/admin/clientes/$EMPRESA_ID/agentes" "$(com_modelos "$corpo")"
    if [ "$API_STATUS" = 201 ]; then
      AGENTE_NOME=$nome
      AGENTE_ID=$(jq -r .id <<<"$API_RESPOSTA")
      AGENTE=$API_RESPOSTA
      echo
      ok "Agente $(destaque "$nome") criado ${CINZA}· nativo · $EMPRESA_NOME${NORMAL}"
      dica "Prompt: prompts/$(jq -r .arquivo_prompt <<<"$API_RESPOSTA") (vale na próxima mensagem)"
      return 0
    fi
    falha "$(detalhe_erro "$API_RESPOSTA")"
    if [ "$API_STATUS" = 409 ]; then
      pergunta nome "Outro nome para o agente"
    else
      erro_fatal "Não consegui criar o agente" "Rode o comando de novo."
    fi
  done
}

# configura_ritmo_novo: o ritmo do agente novo. Define AJUSTES_AGENTE (JSON).
# Os três presets são os mesmos do painel e do Editar agente, e quem escolhe os tempos vira `manual`
# no servidor. O nome do ritmo é o que a plataforma guarda; os números saem dele.
configura_ritmo_novo() {
  local op buffer velocidade maximo
  echo
  dica "Muda depois em Editar agente."
  echo
  escolha op "Ritmo das respostas" \
    "Instantâneo  ${CINZA}responde na hora, bom para testar${NORMAL}" \
    "Natural  ${CINZA}lê, digita e responde como uma pessoa${NORMAL}" \
    "Reflexivo  ${CINZA}espera mais e escreve devagar${NORMAL}" \
    "Escolher os tempos"
  case "$op" in
    1) AJUSTES_AGENTE='{"ritmo": "instantaneo"}' ; return 0 ;;
    2) AJUSTES_AGENTE='{"ritmo": "natural"}' ; return 0 ;;
    3) AJUSTES_AGENTE='{"ritmo": "reflexivo"}' ; return 0 ;;
  esac
  pergunta_numero buffer "Segundos de buffer (1 a 60)" 1 60 8
  pergunta_numero velocidade "Caracteres digitados por segundo (1 a 30)" 1 30 6
  pergunta_numero maximo "Máximo de segundos digitando por mensagem (1 a 30)" 1 30 20
  AJUSTES_AGENTE=$(jq -n --argjson b "$buffer" --argjson v "$velocidade" --argjson m "$maximo" \
    '{buffer_segundos: $b, digitacao_caracteres_por_segundo: $v, digitacao_maximo_segundos: $m}')
}

# com_modelos JSON: junta ao corpo da criação a IA escolhida em escolhe_modelo_do_novo_agente.
com_modelos() {
  jq --argjson m "${MODELOS_NOVO_AGENTE:-{\}}" '. + {modelos: $m}' <<<"$1"
}

# escolhe_ferramentas VAR JSON_DO_AGENTE: lista de marcar com o catálogo da API; devolve o JSON dos nomes.
# Sem agente (criação), começam marcadas as que vêm ligadas por padrão: hoje nenhuma.
escolhe_ferramentas() {
  local __var=$1 __agente=${2:-} __catalogo __ligadas __ferramentas_marcadas __escolhidas="[]" __numero __linha
  local -a __rotulos=()
  [ -n "$__agente" ] || dica "O agente nasce só com as ferramentas que você marcar."
  api GET /admin/ferramentas
  exige_api
  __catalogo=$API_RESPOSTA
  while IFS= read -r __linha; do __rotulos+=("$__linha"); done \
    < <(jq -r --arg cinza "$CINZA" --arg normal "$NORMAL" '.[] | "\(.rotulo)  \($cinza)\(.descricao)\($normal)"' <<<"$__catalogo")
  __ligadas=$(jq -r --arg agente "$__agente" '[.[] | if ($agente == "") then (if .padrao then 1 else 0 end)
    else (if (.nome as $n | $agente | fromjson | .ferramentas | index($n)) then 1 else 0 end) end] | join(" ")' <<<"$__catalogo")
  echo
  marca __ferramentas_marcadas "Ferramentas do agente" "$__ligadas" "${__rotulos[@]}"
  for __numero in $__ferramentas_marcadas; do
    __escolhidas=$(jq -c --argjson catalogo "$__catalogo" --argjson i "$((__numero - 1))" '. + [$catalogo[$i].nome]' <<<"$__escolhidas")
  done
  printf -v "$__var" '%s' "$__escolhidas"
}

# pergunta_emoji [ATUAL]: define EMOJIS. Vale em todo canal: é jeito de escrever, não canal.
pergunta_emoji() {
  local atual=${1:-} op padrao=1
  case "$atual" in
    pouco) padrao=2 ;;
    medio) padrao=3 ;;
    muito) padrao=4 ;;
  esac
  echo
  dica "Vale para as respostas ao contato. Muda depois em Editar agente."
  [ "$atual" = livre ] && dica "Hoje este agente não tem regra: o modelo decide sozinho."
  echo
  ESCOLHA_ATUAL=$padrao escolha op "Emoji nas respostas" \
    "Nenhum  ${CINZA}nunca usa${NORMAL}" \
    "Pouco  ${CINZA}no máximo um na resposta, quando acrescenta algo${NORMAL}" \
    "Médio  ${CINZA}um por mensagem, quando ajuda o tom${NORMAL}" \
    "Muito  ${CINZA}um ou dois por mensagem${NORMAL}"
  case "$op" in
    2) EMOJIS=pouco ;;
    3) EMOJIS=medio ;;
    4) EMOJIS=muito ;;
    *) EMOJIS=nenhum ;;
  esac
}

# emoji_do_agente JSON: como o nível aparece na ficha.
emoji_do_agente() {
  jq -r '(.emojis // "") as $n
    | {"": "-", livre: "o modelo decide", nenhum: "nenhum", pouco: "pouco", medio: "médio", muito: "muito"}[$n] // $n' <<<"$1"
}

# escolhe_caixa_chatwoot: URL → conta → caixa → handoff. Define CHATWOOT_CONEXAO (JSON), CHATWOOT_CONTA_NOME,
# AGENTE_CAIXA e HANDOFF_DESTINO.
escolhe_caixa_chatwoot() {
  local conta_i caixa_i conta_id caixa_id caixas
  acessa_chatwoot

  escolha_da_lista conta_i "Conta do Chatwoot" "$(jq -c '[.contas[].nome]' <<<"$CHATWOOT_CONTAS")"
  conta_id=$(jq -r ".contas[$conta_i].id" <<<"$CHATWOOT_CONTAS")
  CHATWOOT_CONTA_NOME=$(jq -r ".contas[$conta_i].nome" <<<"$CHATWOOT_CONTAS")
  caixas=$(jq -c ".contas[$conta_i].caixas" <<<"$CHATWOOT_CONTAS")
  if [ "$(jq 'length' <<<"$caixas")" -eq 0 ]; then
    erro_fatal "A conta $CHATWOOT_CONTA_NOME não tem caixa de entrada" "Crie a caixa no Chatwoot e rode o comando de novo."
  fi
  escolha_da_lista caixa_i "Caixa de entrada" "$(jq -c '[.[].nome]' <<<"$caixas")"
  caixa_id=$(jq -r ".[$caixa_i].id" <<<"$caixas")
  AGENTE_CAIXA=$(jq -r ".[$caixa_i].nome" <<<"$caixas")
  escolhe_destino_handoff "$(jq -c ".contas[$conta_i]" <<<"$CHATWOOT_CONTAS")"
  CHATWOOT_CONEXAO=$(jq -n --arg url "$CHATWOOT_URL" --argjson conta "$conta_id" --argjson caixa "$caixa_id" \
    '{url: $url, account_id: $conta, inbox_ids: [$caixa]}')
}

# Chatwoot → conta → caixa → handoff → nome → empresa → ferramentas → cria.
fluxo_agente_chatwoot() {
  local nome corpo ferramentas
  AGENTE_CANAL=chatwoot
  escolhe_caixa_chatwoot

  echo
  pergunta nome "Nome do agente"
  escolhe_empresa "$CHATWOOT_CONTA_NOME"
  escolhe_ferramentas ferramentas ""
  pergunta_emoji
  pergunta_retomada 4 chatwoot

  while true; do
    corpo=$(jq -n --arg nome "$nome" --argjson conexao "$CHATWOOT_CONEXAO" --argjson destino "$HANDOFF_DESTINO" \
      --argjson f "$ferramentas" --argjson horas "$RETOMADA_HORAS" --arg emojis "$EMOJIS" \
      '{nome: $nome, canal: "chatwoot", handoff_destino: $destino, conexao: $conexao, ferramentas: $f,
        retomada_automatica_horas: $horas, emojis: $emojis}')
    api_com_token POST "/admin/clientes/$EMPRESA_ID/agentes" "$(com_modelos "$corpo")" "Criando o bot no Chatwoot…"
    if [ "$API_STATUS" = 201 ]; then
      AGENTE_NOME=$nome
      AGENTE_ID=$(jq -r .id <<<"$API_RESPOSTA")
      ok "$(destaque "$nome") no ar na caixa $(destaque "$AGENTE_CAIXA") ${CINZA}· $EMPRESA_NOME${NORMAL}"
      ok "Handoff para $(destaque "$(nome_do_destino "$HANDOFF_DESTINO")")"
      return 0
    fi
    falha "$(detalhe_erro "$API_RESPOSTA")"
    if [ "$API_STATUS" = 409 ]; then
      pergunta nome "Outro nome para o agente"
    elif [ "$API_STATUS" = 422 ]; then
      fluxo_agente_chatwoot
      return 0
    else
      erro_fatal "Não consegui criar o agente" "Rode o comando de novo."
    fi
  done
}

tela_primeiro_agente() {
  estado_tem agente_id && return 0
  estado_tem primeiro_agente_no_painel && return 0
  secao "Primeiro agente"
  if painel_ligado; then
    local onde
    escolha onde "Onde criar o primeiro agente?" \
      "No painel  ${CINZA}passo a passo no navegador, com prévia de como ele responde${NORMAL}" \
      "Aqui no terminal"
    if [ "$onde" = 1 ]; then
      estado_set primeiro_agente_no_painel "$(date -Is)"
      return 0
    fi
    echo
  fi
  AGENTE_ID=""
  fluxo_novo_agente
  # Sem id não houve criação (o operador desistiu no meio, e desistir é uma saída normal). Gravar
  # a etapa aqui fazia o setup seguinte pular o primeiro agente para sempre, com a instalação sem
  # agente nenhum (auditoria de 2026-09-18, A19).
  if [ -z "${AGENTE_ID:-}" ]; then
    aviso "Nenhum agente criado. Rode $(destaque "asimov novo-agente") quando quiser criar."
    return 0
  fi
  estado_set agente_nome "$AGENTE_NOME"
  estado_set agente_canal "$AGENTE_CANAL"
  estado_set agente_caixa "$AGENTE_CAIXA"
  estado_set agente_conta "$EMPRESA_NOME"
  estado_set agente_id "$AGENTE_ID"
}

lista_agentes() {
  local clientes tipo nome canal modelo destino situacao webhook
  api GET /admin/clientes
  exige_api
  clientes=$API_RESPOSTA
  api GET /admin/agentes
  exige_api
  secao "Agentes"
  if [ "$(jq 'length' <<<"$API_RESPOSTA")" -eq 0 ]; then
    dica "Nenhum agente ainda. Crie com: asimov novo-agente"
    return 0
  fi
  # Separador \x1f: com tab, campos vazios seguidos sumiriam no read.
  jq -r --argjson clientes "$clientes" '
    ($clientes | map({(.id): .nome}) | add // {}) as $nomes
    | group_by(.cliente_id) | sort_by($nomes[.[0].cliente_id] // "?") | .[]
    | "empresa\u001f\($nomes[.[0].cliente_id] // "?")",
      (.[] | ["agente", .nome, .canal, .modelo_conversa, (.handoff_destino | tojson), .situacao, .url_webhook] | map(tostring) | join("\u001f"))
  ' <<<"$API_RESPOSTA" | while IFS=$'\x1f' read -r tipo nome canal modelo destino situacao webhook; do
    if [ "$tipo" = empresa ]; then
      printf '  %s%s%s\n' "$NEGRITO" "$nome" "$NORMAL"
      continue
    fi
    # As três situações do agente, na mesma ordem do painel: atendendo, em treinamento (fala só
    # no painel e no terminal) e desligado.
    case "$situacao" in
      ativo) printf '    %s✓%s %s' "$VERDE" "$NORMAL" "$(destaque "$nome")" ;;
      treinamento)
        printf '    %s●%s %s %sem treinamento%s' "$AMARELO" "$NORMAL" "$(destaque "$nome")" "$AMARELO" "$NORMAL"
        ;;
      *) printf '    %s▲%s %s %sdesligado%s' "$VERMELHO" "$NORMAL" "$(destaque "$nome")" "$VERMELHO" "$NORMAL" ;;
    esac
    if [ "$canal" = nativo ]; then
      printf '  %snativo · %s · sem canal: asimov conversar, ou asimov editar para conectar%s\n' "$CINZA" "$modelo" "$NORMAL"
      continue
    fi
    printf '  %s%s · %s · handoff: %s%s\n' "$CINZA" "$canal" "$modelo" "$(nome_do_destino "$destino")" "$NORMAL"
    printf '      %swebhook %s%s\n' "$CINZA" "$webhook" "$NORMAL"
  done
  echo
}

# escolhe_agente [canais]: define AGENTE (JSON do agente) e AGENTE_EMPRESA. Com um ou mais canais
# separados por espaço, só agentes deles. Devolve 1 se não há agentes.
escolhe_agente() {
  local canal=${1:-} op linha clientes agentes
  local -a rotulos=()
  api GET /admin/clientes
  exige_api
  clientes=$API_RESPOSTA
  api GET /admin/agentes
  exige_api
  agentes=$(jq -c --argjson clientes "$clientes" '
    ($clientes | map({(.id): .nome}) | add // {}) as $nomes
    | map(. + {empresa: ($nomes[.cliente_id] // "?")}) | sort_by(.empresa, .nome)' <<<"$API_RESPOSTA")
  [ -z "$canal" ] || agentes=$(jq -c --arg canais "$canal" \
    'map(select(.canal as $c | ($canais | split(" ")) | index($c)))' <<<"$agentes")
  if [ "$(jq 'length' <<<"$agentes")" -eq 0 ]; then
    dica "Nenhum agente${canal:+ em $canal} ainda. Crie com: asimov novo-agente"
    return 1
  fi
  while IFS= read -r linha; do rotulos+=("$linha"); done \
    < <(jq -r --arg cinza "$CINZA" --arg normal "$NORMAL" '.[] | "\(.nome)  \($cinza)\(.empresa)\($normal)"' <<<"$agentes")
  if [ "${#rotulos[@]}" -eq 1 ]; then
    op=1
    ok "Agente: ${rotulos[0]}"
  else
    echo
    escolha op "Agente" "${rotulos[@]}"
  fi
  AGENTE=$(jq -c ".[$((op - 1))] | del(.empresa)" <<<"$agentes")
  # shellcheck disable=SC2034  # lida pelas telas de editar e remover (menu.sh)
  AGENTE_EMPRESA=$(jq -r ".[$((op - 1))].empresa" <<<"$agentes")
}

caminho_do_agente() {
  jq -r '"/admin/clientes/\(.cliente_id)/agentes/\(.id)"' <<<"$1"
}

# configura_handoff JSON_DO_AGENTE: pede o token de administrador, lista quem pode receber e grava.
configura_handoff() {
  local agente=$1 nome url conta_id conta corpo
  nome=$(jq -r .nome <<<"$agente")
  url=$(jq -r .credenciais.url <<<"$agente")
  conta_id=$(jq -r .credenciais.account_id <<<"$agente")
  echo
  printf '  %s%s%s %s· hoje: %s%s\n' "$NEGRITO" "$nome" "$NORMAL" "$CINZA" "$(nome_do_destino "$(jq -c .handoff_destino <<<"$agente")")" "$NORMAL"
  if ! acessa_chatwoot "$url"; then
    RESULTADO=$(falha "Não consegui listar quem pode receber o handoff. Tente de novo em instantes.")
    return 0
  fi
  conta=$(jq -c --argjson id "$conta_id" '.contas[] | select(.id == $id)' <<<"$CHATWOOT_CONTAS")
  if [ -z "$conta" ]; then
    RESULTADO=$(falha "Esse token não enxerga a conta $conta_id do Chatwoot. Use o token de um administrador dela.")
    printf '%s\n' "$RESULTADO"
    return 0
  fi
  escolhe_destino_handoff "$conta"
  pergunta_retomada "$(jq -r '.retomada_automatica_horas // 0' <<<"$agente")" chatwoot
  corpo=$(jq -n --argjson destino "$HANDOFF_DESTINO" --argjson horas "$RETOMADA_HORAS" \
    '{handoff_destino: $destino, retomada_automatica_horas: $horas}')
  api PATCH "$(caminho_do_agente "$agente")" "$corpo"
  if [ "$API_STATUS" = 200 ]; then
    AGENTE=$API_RESPOSTA
    RESULTADO=$(ok "Handoff de $(destaque "$nome") para $(destaque "$(nome_do_destino "$HANDOFF_DESTINO")")")
  else
    RESULTADO=$(falha "$(detalhe_erro "$API_RESPOSTA")")
  fi
  printf '%s\n' "$RESULTADO"
}

# asimov handoff: escolhe o agente e troca quem recebe o handoff, no canal dele.
fluxo_handoff() {
  secao "Handoff"
  escolhe_agente "chatwoot waha whatsapp" || return 0
  if [ "$(jq -r '.canal' <<<"$AGENTE")" = whatsapp ]; then
    templates_do_agente || aviso "Não consegui listar os templates agora."
    escolhe_destino_whatsapp "$WHATSAPP_TEMPLATES" "$(jq -c '.handoff_destino // {}' <<<"$AGENTE")" || return 0
    api PATCH "$(caminho_do_agente "$AGENTE")" "$(jq -n --argjson d "$HANDOFF_DESTINO" '{handoff_destino: $d}')"
    if [ "$API_STATUS" = 200 ]; then
      AGENTE=$API_RESPOSTA
      ok "Handoff de $(destaque "$(jq -r .nome <<<"$AGENTE")") para $(destaque "$(nome_do_destino "$HANDOFF_DESTINO")")"
    else
      falha "$(detalhe_erro "$API_RESPOSTA")"
    fi
  elif [ "$(jq -r '.canal' <<<"$AGENTE")" = waha ]; then
    escolhe_destino_waha "$AGENTE"
    api PATCH "$(caminho_do_agente "$AGENTE")" "$(jq -n --argjson d "$HANDOFF_DESTINO" '{handoff_destino: $d}')"
    if [ "$API_STATUS" = 200 ]; then
      AGENTE=$API_RESPOSTA
      ok "Handoff de $(destaque "$(jq -r .nome <<<"$AGENTE")") para $(destaque "$(nome_do_destino "$HANDOFF_DESTINO")")"
    else
      falha "$(detalhe_erro "$API_RESPOSTA")"
    fi
  else
    configura_handoff "$AGENTE"
  fi
  echo
}

# Atualização para a v0.4: agentes criados antes do handoff não têm destino. Pergunta uma vez.
tela_handoff_pendente() {
  local sem_destino agente
  estado_tem handoff_perguntado && return 0
  api GET /admin/agentes
  [ "$API_STATUS" = 200 ] || return 0
  sem_destino=$(jq -c '[.[] | select(.canal == "chatwoot" and .handoff_destino == null)]' <<<"$API_RESPOSTA")
  if [ "$(jq 'length' <<<"$sem_destino")" -gt 0 ]; then
    secao "Handoff"
    info "O agente agora passa a conversa para uma pessoa quando o contato pede."
    aviso "Sem destino, a conversa transferida fica na caixa sem atribuição."
    if confirma "Escolher quem recebe agora?"; then
      while IFS= read -r agente; do
        configura_handoff "$agente"
      done < <(jq -c '.[]' <<<"$sem_destino")
    fi
    dica "Para mudar depois: asimov handoff"
  fi
  estado_set handoff_perguntado "$(date -Is)"
}
