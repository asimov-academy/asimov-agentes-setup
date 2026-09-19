#!/usr/bin/env bash
# shellcheck disable=SC2034  # AGENTE_*, WHATSAPP_* e HANDOFF_DESTINO são lidas pelas telas
# WhatsApp oficial (Cloud API da Meta): credenciais do app, número da conta e template do aviso.
#
# Nada sobe na VPS por causa deste canal: quem fala com a Meta é a própria API. O endereço do
# webhook é apontado no número pela API, no momento em que o agente é criado; o operador não cola
# URL nenhuma no painel da Meta.

# Texto do template que o operador manda aprovar. Três parâmetros, na ordem em que o aviso usa.
TEMPLATE_SUGERIDO_NOME="aviso_handoff"

mostra_template_sugerido() {
  echo
  dica "Crie na Meta um template de categoria Utilidade, em português, com este corpo:"
  echo
  printf '    %sO agente passou uma conversa para voce.%s\n' "$CINZA" "$NORMAL"
  printf '    %s%s\n' "$CINZA" "$NORMAL"
  printf '    %sContato: {{1}}%s\n' "$CINZA" "$NORMAL"
  printf '    %sResumo: {{2}}%s\n' "$CINZA" "$NORMAL"
  printf '    %sCodigo: {{3}}%s\n' "$CINZA" "$NORMAL"
  printf '    %s%s\n' "$CINZA" "$NORMAL"
  printf '    %sResponda /retomar neste chat quando terminar.%s\n' "$CINZA" "$NORMAL"
  echo
  dica "Nome sugerido: $TEMPLATE_SUGERIDO_NOME. A aprovação costuma sair em alguns minutos."
  dica "Onde criar: WhatsApp Manager > Modelos de mensagem."
}

# aviso_oficial: o que decide a escolha, em duas linhas. Devolve 1 se o operador desistir.
# O resto (o que a Meta pede para publicar o app) só aparece depois do sim.
aviso_oficial() {
  echo
  info "Na Meta você precisa ter: app, número na conta de WhatsApp Business, token permanente,"
  info "chave secreta do app e um modelo de mensagem aprovado para avisar quem vai atender."
  dica "A Meta cobra por mensagem, com 1.000 grátis por número por mês, e sem forma de pagamento na conta ela não entrega as respostas."
  echo
  confirma "Tenho isso em mãos. Continuar?" || return 1
  dados_para_publicar_o_app
}

# dados_para_publicar_o_app: o que a Meta pede para o app sair do modo de desenvolvimento.
# A página de privacidade é servida por esta instalação, no domínio dela.
dados_para_publicar_o_app() {
  local sub
  sub=$(env_get SUBDOMINIO_BOT)
  echo
  info "Para publicar o app, a Meta pede dois endereços. Os dois já estão no ar aqui:"
  echo
  printf '    %s%s%s\n' "$NEGRITO" "https://$sub/privacidade" "$NORMAL"
  dica "  A do agente, que é a que o app do número quer, aparece no fim desta tela."
  printf '    %s%s%s\n' "$NEGRITO" "https://$sub/icone-app.png" "$NORMAL"
  dica "  Abra e salve a imagem. Para trocar: substitua modelos/icone-app.png."
  # Confere de fora, pelo domínio: é assim que a Meta vai abrir. Caminho público novo já respondeu
  # 404 por o Caddy estar com a configuração antiga em memória, e ninguém viu até tentar.
  if ! confere_publico "https://$sub/privacidade" && ! confere_publico "https://$sub/icone-app.png"; then
    echo
    aviso "Os dois endereços não responderam, e a Meta vai recusar a URL assim."
    dica "Recarregue o servidor web: cd $RAIZ_PROJETO && source deploy/compose.sh && dc restart caddy"
  fi
  echo
}

# confere_publico URL: 0 quando o endereço responde 200 de fora. Avisa quando não.
confere_publico() {
  local url=$1 codigo
  codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)
  [ "$codigo" = 200 ] && return 0
  echo
  aviso "$url não respondeu ($codigo)."
  return 1
}

# pede_credenciais_whatsapp: pergunta app, token e chave secreta, descobre as contas de WhatsApp
# que o token alcança e lista números e templates da escolhida.
# Define WHATSAPP_CONEXAO (JSON com app_id, token, chave e waba_id) e WHATSAPP_ACHADO.
pede_credenciais_whatsapp() {
  local app token segredo
  echo
  dica "Passo a passo com links: docs/whatsapp-oficial.md, no repositório."
  while true; do
    dica "ID do app: painel do app, em Configurações do app > Básico, no topo."
    pergunta app "ID do app" "$(estado_get whatsapp_app)"
    app=$(tr -cd '0-9' <<<"$app")
    if [ -z "$app" ]; then
      falha "O ID do app é só números."
      continue
    fi
    dica "Token de acesso permanente (usuário do sistema), não o token de teste de 24 horas."
    pergunta_secreta token "Token de acesso"
    dica "Chave secreta do app: painel do app, em Configurações do app > Básico."
    pergunta_secreta segredo "Chave secreta do app"
    # Pelo ambiente, não por argumento: `jq --arg` deixaria token e chave secreta visíveis em
    # `ps` para qualquer usuário da máquina (auditoria de 2026-09-18, A13).
    WHATSAPP_CONEXAO=$(ASIMOV_APP="$app" ASIMOV_TOKEN="$token" ASIMOV_SEGREDO="$segredo" jq -n \
      '{app_id: env.ASIMOV_APP, access_token: env.ASIMOV_TOKEN, app_secret: env.ASIMOV_SEGREDO}')
    unset token segredo

    # O ID da conta de WhatsApp Business é o dado mais escondido do painel: em vez de mandar o
    # operador procurar, pergunta ao próprio token quais contas ele alcança.
    if ! descobre_whatsapp "Conferindo o token na Meta…"; then
      falha "$(detalhe_erro "$API_RESPOSTA")"
      continue
    fi
    escolhe_conta_whatsapp || continue
    if descobre_whatsapp "Lendo a conta na Meta…"; then
      estado_set whatsapp_app "$app"
      return 0
    fi
    falha "$(detalhe_erro "$API_RESPOSTA")"
  done
}

# descobre_whatsapp "aguarde": chama o descobrir com o que já está em WHATSAPP_CONEXAO.
# Devolve 1 quando a API recusou; o corpo fica em WHATSAPP_ACHADO.
descobre_whatsapp() {
  api_com_token POST /admin/canais/whatsapp/descobrir \
    "$(jq -n --argjson c "$WHATSAPP_CONEXAO" '{conexao: $c}')" "$1"
  [ "$API_STATUS" = 200 ] || return 1
  WHATSAPP_ACHADO=$API_RESPOSTA
  return 0
}

# escolhe_conta_whatsapp: põe o `waba_id` em WHATSAPP_CONEXAO, a partir do que o token alcança.
# Sem nenhuma conta encontrada, pergunta o ID à mão. Devolve 1 para recomeçar as credenciais.
escolhe_conta_whatsapp() {
  local contas total op conta linha
  local -a rotulos=()
  contas=$(jq -c '.contas // []' <<<"$WHATSAPP_ACHADO")
  total=$(jq 'length' <<<"$contas")
  if [ "$total" -eq 0 ]; then
    echo
    aviso "Esse token não enxerga nenhuma conta de WhatsApp Business."
    dica "Quase sempre é token gerado antes de a conta virar ativo do usuário do sistema: gere outro"
    dica "em Usuários do sistema > Gerar token. Detalhes em docs/whatsapp-oficial.md, passo 7."
    echo
    dica "Se o token estiver certo e você só quiser seguir, informe o ID da conta à mão: ele fica no"
    dica "Gerenciador de Negócios, em Configurações > Contas > Contas do WhatsApp, em Identificação,"
    dica "na conta que tem o número do agente."
    echo
    confirma "Informar o ID da conta à mão?" || return 1
    pergunta conta "ID da conta de WhatsApp Business" "$(estado_get whatsapp_waba)"
    conta=$(tr -cd '0-9' <<<"$conta")
    if [ -z "$conta" ]; then
      falha "O ID da conta é só números."
      return 1
    fi
  elif [ "$total" -eq 1 ]; then
    conta=$(jq -r '.[0].waba_id' <<<"$contas")
    ok "Conta de WhatsApp Business: $(destaque "$(jq -r '.[0].nome // .[0].waba_id' <<<"$contas")")"
  else
    while IFS= read -r linha; do rotulos+=("$linha"); done \
      < <(jq -r --arg cinza "$CINZA" --arg normal "$NORMAL" '.[] | "\(.nome // .waba_id)  \($cinza)\(.waba_id)\($normal)"' <<<"$contas")
    echo
    escolha op "Conta de WhatsApp Business" "${rotulos[@]}"
    conta=$(jq -r ".[$((op - 1))].waba_id" <<<"$contas")
  fi
  estado_set whatsapp_waba "$conta"
  WHATSAPP_CONEXAO=$(jq -c --arg c "$conta" '. + {waba_id: $c}' <<<"$WHATSAPP_CONEXAO")
  return 0
}

# escolhe_numero_whatsapp: põe o `phone_number_id` escolhido em WHATSAPP_CONEXAO.
# Define WHATSAPP_NUMERO (como a Meta mostra). Devolve 1 se a conta não tem número.
escolhe_numero_whatsapp() {
  local numeros total op linha id
  local -a rotulos=()
  numeros=$(jq -c '.numeros' <<<"$WHATSAPP_ACHADO")
  total=$(jq 'length' <<<"$numeros")
  if [ "$total" -eq 0 ]; then
    falha "Essa conta não tem nenhum número. Adicione o número na Meta e tente de novo."
    return 1
  fi
  while IFS= read -r linha; do rotulos+=("$linha"); done \
    < <(jq -r --arg cinza "$CINZA" --arg normal "$NORMAL" '.[] | "\(.numero)  \($cinza)\(.nome)\($normal)"' <<<"$numeros")
  if [ "$total" -eq 1 ]; then
    op=1
    ok "Número: $(destaque "$(jq -r '.[0].numero' <<<"$numeros")")"
  else
    echo
    escolha op "Número do agente" "${rotulos[@]}"
  fi
  id=$(jq -r ".[$((op - 1))].phone_number_id" <<<"$numeros")
  WHATSAPP_NUMERO=$(jq -r ".[$((op - 1))].numero" <<<"$numeros")
  WHATSAPP_CONEXAO=$(jq -c --arg id "$id" '. + {phone_number_id: $id}' <<<"$WHATSAPP_CONEXAO")
  return 0
}

# escolhe_template_whatsapp JSON_DOS_TEMPLATES [NOME_ATUAL]: define TEMPLATE_HANDOFF (JSON ou null).
# Só entram os aprovados com três parâmetros: com outro formato o aviso não caberia.
escolhe_template_whatsapp() {
  local servem=$1 atual=${2:-} op total linha
  local -a rotulos=()
  servem=$(jq -c '[.[] | select(.serve // (.situacao == "APPROVED" and .parametros == 3))]' <<<"$servem")
  total=$(jq 'length' <<<"$servem")
  TEMPLATE_HANDOFF=null
  echo
  dica "Fora da janela de 24 horas, a Meta só entrega template aprovado: é ele que leva o aviso."
  if [ "$total" -eq 0 ]; then
    aviso "Nenhum template aprovado com três parâmetros nessa conta."
    mostra_template_sugerido
    dica "Sem ele, o aviso de handoff só chega se o destino tiver escrito ao agente nas últimas 24 h."
    confirma "Seguir sem template por enquanto?" && return 0
    return 1
  fi
  while IFS= read -r linha; do rotulos+=("$linha"); done \
    < <(jq -r --arg cinza "$CINZA" --arg normal "$NORMAL" '.[] | "\(.nome)  \($cinza)\(.idioma)\($normal)"' <<<"$servem")
  if [ -n "$atual" ]; then
    ok "Hoje: $(destaque "$atual")"
  fi
  echo
  escolha op "Template do aviso de handoff" "${rotulos[@]}"
  TEMPLATE_HANDOFF=$(jq -c --argjson i "$((op - 1))" '{nome: .[$i].nome, idioma: .[$i].idioma}' <<<"$servem")
  return 0
}

# escolhe_destino_whatsapp JSON_DOS_TEMPLATES [DESTINO_ATUAL]: define HANDOFF_DESTINO.
escolhe_destino_whatsapp() {
  local templates=$1 atual=${2:-null} telefone padrao
  padrao=$(jq -r '.telefone // ""' <<<"$atual")
  echo
  dica "Quando o agente passar a conversa para uma pessoa, o aviso com o resumo vai para cá."
  dica "Para devolver: 👍 no aviso, ou /retomar no mesmo chat."
  dica "Com DDI e DDD, como 5511988887777. Precisa ser um número que use WhatsApp."
  while true; do
    pergunta telefone "Número que recebe o handoff" "$padrao"
    telefone=$(tr -cd '0-9' <<<"$telefone")
    if [ "${#telefone}" -ge 10 ] && [ "${#telefone}" -le 15 ]; then
      break
    fi
    falha "Número fora do formato: use DDI, DDD e o número, só dígitos."
  done
  escolhe_template_whatsapp "$templates" "$(jq -r '.template.nome // ""' <<<"$atual")" || return 1
  HANDOFF_DESTINO=$(jq -n --arg t "$telefone" --argjson tpl "$TEMPLATE_HANDOFF" \
    '{tipo: "numero", telefone: $t} + (if $tpl == null then {} else {template: $tpl} end)')
  return 0
}

# Credenciais → número → nome → empresa → ferramentas → handoff → cria.
# O webhook é apontado no número pela própria criação: a Meta confere o endereço na hora.
fluxo_agente_whatsapp() {
  local nome corpo ferramentas
  AGENTE_CANAL=whatsapp
  secao "Agente no WhatsApp oficial"
  aviso_oficial || return 0
  pede_credenciais_whatsapp
  escolhe_numero_whatsapp || return 0
  AGENTE_CAIXA=$WHATSAPP_NUMERO

  echo
  pergunta nome "Nome do agente"
  escolhe_empresa ""
  escolhe_ferramentas ferramentas ""
  pergunta_emoji
  pergunta_retomada 4 whatsapp
  escolhe_contatos_permitidos
  escolhe_destino_whatsapp "$(jq -c '.templates_todos' <<<"$WHATSAPP_ACHADO")" || return 0

  while true; do
    corpo=$(jq -n --arg nome "$nome" --argjson conexao "$WHATSAPP_CONEXAO" --argjson f "$ferramentas" \
      --argjson destino "$HANDOFF_DESTINO" --argjson horas "$RETOMADA_HORAS" \
      --argjson permitidos "$CONTATOS_PERMITIDOS" --arg emojis "$EMOJIS" \
      '{nome: $nome, canal: "whatsapp", conexao: $conexao, ferramentas: $f, handoff_destino: $destino,
        retomada_automatica_horas: $horas, contatos_permitidos: $permitidos, emojis: $emojis}')
    api_com_token POST "/admin/clientes/$EMPRESA_ID/agentes" "$(com_modelos "$corpo")" "Apontando o webhook na Meta…"
    if [ "$API_STATUS" = 201 ]; then break; fi
    falha "$(detalhe_erro "$API_RESPOSTA")"
    if [ "$API_STATUS" = 409 ]; then
      pergunta nome "Outro nome para o agente"
    elif confirma "Tentar com outras credenciais?"; then
      pede_credenciais_whatsapp
      escolhe_numero_whatsapp || return 0
    else
      return 0
    fi
  done

  AGENTE=$API_RESPOSTA
  AGENTE_NOME=$nome
  AGENTE_ID=$(jq -r .id <<<"$AGENTE")
  echo
  ok "$(destaque "$nome") no ar no número $(destaque "$WHATSAPP_NUMERO") ${CINZA}· $EMPRESA_NOME${NORMAL}"
  ok "Handoff para $(destaque "$(nome_do_destino "$(jq -c .handoff_destino <<<"$AGENTE")")")"
  echo
  info "Política de privacidade deste agente, para o app da Meta dele:"
  printf '    %s\n' "$(destaque "$(jq -r '.url_privacidade' <<<"$AGENTE")")"
  dica "Mande uma mensagem para o número e o agente responde."
}

# conecta_whatsapp NOME: liga um agente nativo no WhatsApp oficial (Editar agente).
conecta_whatsapp() {
  local nome=$1 corpo rapido=""
  aviso_oficial || return 0
  pede_credenciais_whatsapp
  escolhe_numero_whatsapp || return 0
  pergunta_retomada 4 whatsapp
  escolhe_destino_whatsapp "$(jq -c '.templates_todos' <<<"$WHATSAPP_ACHADO")" || return 0
  ritmo_do_whatsapp && rapido=1

  corpo=$(jq -n --argjson conexao "$WHATSAPP_CONEXAO" --argjson destino "$HANDOFF_DESTINO" \
    --argjson horas "$RETOMADA_HORAS" \
    '{canal: "whatsapp", conexao: $conexao, handoff_destino: $destino, retomada_automatica_horas: $horas}')
  api_com_token POST "$(caminho_do_agente "$AGENTE")/canal" "$corpo" "Apontando o webhook na Meta…"
  if [ "$API_STATUS" != 200 ]; then
    RESULTADO=$(falha "$(detalhe_erro "$API_RESPOSTA")")
    return 0
  fi
  AGENTE=$API_RESPOSTA
  [ -n "$rapido" ] && aplica_ritmo_do_whatsapp
  RESULTADO=$(ok "$(destaque "$nome") atende no WhatsApp $(destaque "$WHATSAPP_NUMERO") ${CINZA}· handoff para $(nome_do_destino "$HANDOFF_DESTINO")${NORMAL}")
  return 0
}

# templates_do_agente: lista os templates da conta do AGENTE. Define WHATSAPP_TEMPLATES.
templates_do_agente() {
  api_com_token GET "$(caminho_do_agente "$AGENTE")/whatsapp/templates" "" "Procurando os templates…"
  if [ "$API_STATUS" != 200 ]; then
    WHATSAPP_TEMPLATES="[]"
    return 1
  fi
  WHATSAPP_TEMPLATES=$API_RESPOSTA
  return 0
}

# Editar agente, opção WhatsApp: confere o número na Meta e troca destino, prazo e quem atende.
edita_whatsapp() {
  local op nome
  nome=$(jq -r '.nome' <<<"$AGENTE")
  api_com_token GET "$(caminho_do_agente "$AGENTE")/whatsapp" "" "Conferindo o número na Meta…"
  secao "WhatsApp de $nome"
  if [ "$API_STATUS" = 200 ]; then
    campo "Número" "$(jq -r '.numero' <<<"$API_RESPOSTA") ${CINZA}$(jq -r '.nome' <<<"$API_RESPOSTA")${NORMAL}"
  else
    campo "Número" "não consegui falar com a Meta: $(detalhe_erro "$API_RESPOSTA")"
  fi
  campo "Handoff" "$(nome_do_destino "$(jq -c '.handoff_destino' <<<"$AGENTE")")"
  campo "Template" "$(jq -r '.handoff_destino.template.nome // "nenhum: o aviso só chega dentro da janela de 24 h"' <<<"$AGENTE")"
  campo "Retomada" "👍 no aviso$(jq -r 'if .retomada_automatica_horas then ", ou sozinho em \(.retomada_automatica_horas) h" else " ou /retomar" end' <<<"$AGENTE")"
  campo "Atende" "$(atende_do_agente "$AGENTE")"
  campo "Privacidade" "$(jq -r '.url_privacidade // "-"' <<<"$AGENTE")"
  echo
  ESC_ESCOLHE=5 escolha op "O que fazer?" \
    "Quem recebe o handoff  ${CINZA}número e template${NORMAL}" \
    "Horas até voltar sozinho" \
    "Quem o agente atende" \
    "Refazer o webhook na Meta  ${CINZA}se o agente parou de receber mensagem${NORMAL}" \
    "Voltar"
  case "$op" in
    1)
      templates_do_agente || aviso "Não consegui listar os templates agora."
      escolhe_destino_whatsapp "$WHATSAPP_TEMPLATES" "$(jq -c '.handoff_destino // {}' <<<"$AGENTE")" || return 0
      salva_agente "$(jq -n --argjson d "$HANDOFF_DESTINO" '{handoff_destino: $d}')"
      ;;
    2)
      pergunta_retomada "$(jq -r '.retomada_automatica_horas // 0' <<<"$AGENTE")" whatsapp
      salva_agente "$(jq -n --argjson h "$RETOMADA_HORAS" '{retomada_automatica_horas: $h}')"
      ;;
    3)
      escolhe_contatos_permitidos "$(jq -c '.contatos_permitidos // []' <<<"$AGENTE")"
      salva_agente "$(jq -n --argjson p "$CONTATOS_PERMITIDOS" '{contatos_permitidos: $p}')"
      ;;
    4)
      echo
      dica "Liga de novo os webhooks do app, inscreve a conta e aponta o número para este servidor."
      api_com_token POST "$(caminho_do_agente "$AGENTE")/whatsapp/webhook" '{}' "Refazendo na Meta…"
      if [ "$API_STATUS" = 204 ]; then
        ok "Webhook refeito. Mande uma mensagem para o número e confira com: asimov consumo"
      else
        falha "$(detalhe_erro "$API_RESPOSTA")"
      fi
      pausa
      ;;
  esac
}
