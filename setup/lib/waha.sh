#!/usr/bin/env bash
# shellcheck disable=SC2034  # PASSO_*, AGENTE_* e WAHA_* são lidas por passo() e pelas telas
# WhatsApp pela WAHA: contêiner sob demanda, pareamento do número por QR code e destino do handoff.
#
# A WAHA sobe na instalação, junto com o resto da plataforma (`instala_waha`). Antes ela só subia
# no primeiro agente WAHA do terminal, e quem ligava o WhatsApp pelo painel caía num contêiner que
# ninguém tinha subido: o painel não fala com o Docker e nunca teria como subi-lo.

WAHA_ESPERA_STATUS=3
# Versão da WAHA que esta versão do setup instala. O timer semanal troca por uma mais nova.
WAHA_VERSAO_BASE="2026.8.2"
WAHA_TAGS_URL="https://hub.docker.com/v2/repositories/devlikeapro/waha/tags?page_size=100&ordering=last_updated"
WAHA_ESPERA_VOLTAR=120

# Prefixo da tag conforme a arquitetura da VPS (a WAHA publica uma imagem própria para arm).
prefixo_waha() {
  case "$(uname -m)" in
    aarch64 | arm64) echo "gows-arm-" ;;
    *) echo "gows-" ;;
  esac
}

versao_waha() { echo "$(prefixo_waha)$WAHA_VERSAO_BASE"; }

# tag_waha_mais_nova JSON PREFIXO: a maior versão publicada com aquele prefixo, ou vazio.
# Só tags de versão (`gows-2026.8.2`): rótulos móveis como `gows` e `dev` mudam debaixo do pé.
tag_waha_mais_nova() {
  local json=$1 prefixo=$2 versao
  versao=$(jq -r --arg p "$prefixo" '.results[]?.name | select(startswith($p)) | ltrimstr($p)' <<<"$json" 2>/dev/null |
    grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
  [ -n "$versao" ] && printf '%s%s' "$prefixo" "$versao"
}

# Avisa a plataforma antes de mexer no contêiner: a sessão vai passar por STOPPED, e isso não é
# número fora do ar.
avisa_manutencao() { api POST /admin/canais/waha/manutencao '{}' || true; }

sobe_waha() { avisa_manutencao; dc up -d --wait waha; }
sobe_api() { dc up -d api worker; }

# instala_waha: deixa a WAHA pronta na instalação, junto dos outros serviços. Roda dentro de
# `tela_instalacao`, que já desenha o passo e manda a saída para o log.
instala_waha() {
  env_set_se_vazio WAHA_API_KEY "$(openssl rand -hex 32)"
  env_set VERSAO_WAHA "$(versao_waha)"
  command -v qrencode >/dev/null 2>&1 || apt_instala qrencode
  sobe_waha || return 1
  # A imagem envelhece rápido (o WhatsApp muda o protocolo). O timer é conforto: falhar aqui não
  # pode derrubar a instalação, e o menu religa em WhatsApp (WAHA).
  instala_timer_waha || true
}

# garante_waha: deixa o contêiner da WAHA no ar antes de parear um número. A instalação já o subiu;
# isto cobre o contêiner removido à mão e a VPS instalada por uma versão anterior, que nunca o teve.
# Idempotente: com a WAHA já rodando, sai na hora, calado.
garante_waha() {
  if [ -n "$(dc ps -q waha 2>/dev/null || true)" ]; then
    return 0
  fi
  secao "WhatsApp na VPS"
  dica "O WhatsApp direto roda num contêiner aqui mesmo (WAHA), sem porta aberta para fora."
  dica "Na primeira vez a imagem é baixada: pode levar alguns minutos."
  echo
  env_set_se_vazio WAHA_API_KEY "$(openssl rand -hex 32)"
  env_set_se_vazio VERSAO_WAHA "$(versao_waha)"

  PASSO_ATUAL=0
  PASSO_TOTAL=2
  if ! command -v qrencode >/dev/null 2>&1; then
    PASSO_TOTAL=3
    passo qrencode_waha "Leitor de QR code no terminal" "Veja o log." apt_instala qrencode
  fi
  passo waha_container "Serviço do WhatsApp (WAHA)" \
    "Veja: source deploy/compose.sh && dc logs waha" sobe_waha
  passo waha_api "Plataforma ligada ao WhatsApp" \
    "Veja: source deploy/compose.sh && dc logs api" --sem-repetir sobe_api
  # A API acabou de ser recriada para enxergar a chave da WAHA: espera ela responder de novo,
  # senão a primeira chamada do fluxo do agente cai em cima de uma API que ainda está subindo.
  espera_url http://127.0.0.1:8000/health 24 >/dev/null 2>&1 || true
  # Os passos valem só para esta subida: o contêiner pode ser removido e precisar subir de novo.
  estado_remove passo_qrencode_waha passo_waha_container passo_waha_api
  # Versão da WAHA envelhece rápido: o WhatsApp muda o protocolo e a imagem antiga para de conectar.
  # Nada aqui pode derrubar a criação do agente: o timer é conforto, o agente é o que o operador quer.
  if ! instala_timer_waha; then
    aviso "Não consegui ligar a atualização automática da WAHA. Ligue depois no menu, em WhatsApp (WAHA)."
  fi
  echo
}

# instala_timer_waha: confere versão nova da WAHA toda semana, domingo de madrugada.
# O timer roda no host (o contêiner não fala com o Docker), como o serviço que instalou o setup.
instala_timer_waha() {
  local quando="Sun *-*-* 04:00:00 America/Sao_Paulo"
  command -v systemctl >/dev/null 2>&1 || return 0
  # Fuso no OnCalendar pede systemd 252+; em systemd mais velho, vale o fuso da VPS.
  if ! systemd-analyze calendar "$quando" >/dev/null 2>&1; then
    quando="Sun *-*-* 04:00:00"
  fi
  $SUDO tee /etc/systemd/system/asimov-waha.service >/dev/null <<UNIDADE || return 1
[Unit]
Description=Atualiza a WAHA (WhatsApp) do Asimov Agentes
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
Environment=HOME=$HOME
ExecStart=$RAIZ_PROJETO/deploy/atualiza_waha.sh
UNIDADE
  $SUDO tee /etc/systemd/system/asimov-waha.timer >/dev/null <<UNIDADE || return 1
[Unit]
Description=Confere toda semana se saiu versão nova da WAHA

[Timer]
OnCalendar=$quando
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
UNIDADE
  $SUDO systemctl daemon-reload >/dev/null 2>&1 || return 1
  $SUDO systemctl enable --now asimov-waha.timer >/dev/null 2>&1 || return 1
  return 0
}

timer_waha_ligado() {
  command -v systemctl >/dev/null 2>&1 || return 1
  $SUDO systemctl is-enabled asimov-waha.timer >/dev/null 2>&1
}

# agentes_waha_pareados: ids dos agentes cujo número está conectado agora, um por linha.
agentes_waha_pareados() {
  local lista linha
  api GET /admin/agentes
  [ "$API_STATUS" = 200 ] || return 0
  lista=$(jq -c '[.[] | select(.canal == "waha" and .situacao != "inativo")]' <<<"$API_RESPOSTA")
  while IFS= read -r linha; do
    api GET "$(caminho_do_agente "$linha")/waha"
    if [ "$API_STATUS" = 200 ] && [ "$(jq -r '.pareado' <<<"$API_RESPOSTA")" = true ]; then
      jq -r '.id' <<<"$linha"
    fi
  done < <(jq -c '.[]' <<<"$lista")
  return 0
}

# espera_numeros_voltarem IDS SEGUNDOS: 0 quando todos voltaram a ficar conectados.
espera_numeros_voltarem() {
  local ids=$1 limite=$2 passados=0 voltaram
  [ -n "$ids" ] || return 0
  while [ "$passados" -lt "$limite" ]; do
    voltaram=$(agentes_waha_pareados)
    if [ -z "$(comm -23 <(sort <<<"$ids") <(sort <<<"$voltaram"))" ]; then
      return 0
    fi
    sleep 5
    passados=$((passados + 5))
  done
  return 1
}

sobe_waha_de_novo() { avisa_manutencao; dc up -d --wait waha; }

# atualiza_waha [--silencioso]: troca a imagem da WAHA pela versão nova, se houver, e volta para a
# anterior se algum número que estava conectado não voltar. O timer chama com --silencioso.
# Deixa o resultado no estado: waha_checado, waha_versao e waha_aviso (lido pelo menu).
atualiza_waha() {
  local silencioso=${1:-} json atual nova pareados
  atual=$(env_get VERSAO_WAHA)
  [ -n "$atual" ] || atual=$(versao_waha)
  json=$(curl -fsSL --max-time 30 "$WAHA_TAGS_URL" 2>/dev/null || true)
  nova=$(tag_waha_mais_nova "$json" "$(prefixo_waha)")
  estado_set waha_checado "$(date -Is)"

  if [ -z "$nova" ]; then
    [ -n "$silencioso" ] || aviso "Não consegui consultar as versões da WAHA agora. Tente mais tarde."
    return 1
  fi
  if [ "$nova" = "$atual" ]; then
    [ -n "$silencioso" ] || ok "A WAHA já está na versão mais nova ($(destaque "$atual"))."
    return 0
  fi

  [ -n "$silencioso" ] || dica "Versão nova: $atual → $nova. A WAHA fica fora do ar por alguns segundos."
  pareados=$(agentes_waha_pareados)
  env_set VERSAO_WAHA "$nova"
  if ! dc pull waha >>"$LOG" 2>&1 || ! sobe_waha_de_novo >>"$LOG" 2>&1; then
    _volta_waha "$atual" "não consegui subir a WAHA $nova" "$silencioso"
    return 1
  fi
  if ! espera_numeros_voltarem "$pareados" "$WAHA_ESPERA_VOLTAR"; then
    _volta_waha "$atual" "os números não voltaram a conectar na WAHA $nova" "$silencioso"
    return 1
  fi

  estado_set waha_versao "$nova"
  estado_remove waha_aviso
  [ -n "$silencioso" ] || ok "WAHA atualizada para $(destaque "$nova")."
  printf '%s waha atualizada: %s -> %s\n' "$(date -Is)" "$atual" "$nova" >>"$LOG"
  return 0
}

# _volta_waha VERSAO MOTIVO SILENCIOSO: desfaz a atualização e deixa o aviso para o menu mostrar.
_volta_waha() {
  local anterior=$1 motivo=$2 silencioso=$3
  env_set VERSAO_WAHA "$anterior"
  sobe_waha_de_novo >>"$LOG" 2>&1 || true
  espera_numeros_voltarem "$(agentes_waha_pareados)" 30 || true
  estado_set waha_aviso "$motivo; voltei para $anterior em $(date -Is)"
  printf '%s waha: %s; voltei para %s\n' "$(date -Is)" "$motivo" "$anterior" >>"$LOG"
  [ -n "$silencioso" ] || falha "$motivo. Voltei para $anterior."
}

# Tela do menu: versão, última conferida, atualização automática e atualizar agora.
fluxo_waha() {
  local op
  secao "WhatsApp (WAHA)"
  campo "Versão" "$(env_get VERSAO_WAHA)"
  campo "Conferida" "$(estado_get waha_checado | cut -c1-16 | tr T ' ')"
  campo "Automática" "$(timer_waha_ligado && echo 'sim, domingo de madrugada' || echo não)"
  if [ -n "$(estado_get waha_aviso)" ]; then
    echo
    aviso "$(estado_get waha_aviso)"
    dica "Detalhes: source deploy/compose.sh && dc logs waha"
  fi
  echo
  ESC_ESCOLHE=3 escolha op "O que fazer?" \
    "Procurar versão nova agora" \
    "$(timer_waha_ligado && echo "Desligar a atualização automática" || echo "Ligar a atualização automática")" \
    "Voltar"
  case "$op" in
    1)
      echo
      atualiza_waha || true
      estado_remove waha_aviso
      ;;
    2)
      if timer_waha_ligado; then
        $SUDO systemctl disable --now asimov-waha.timer >/dev/null 2>&1 || true
        ok "Atualização automática desligada. Confira de vez em quando por aqui."
      else
        instala_timer_waha
        ok "Atualização automática ligada: domingo de madrugada."
      fi
      ;;
  esac
}

# aviso_nao_oficial: o operador precisa saber o que está escolhendo antes de parear um número.
# Devolve 1 se ele desistir. Aparece na criação e ao ligar um agente já existente no WhatsApp.
aviso_nao_oficial() {
  echo
  aviso "API $(destaque "não oficial"): a Meta não homologa e pode bloquear o número a qualquer momento, sem aviso."
  dica "Use um chip só do agente, nunca o número principal da empresa, e nada de disparo em massa."
  dica "O WhatsApp oficial, na opção anterior, não tem esse risco e cobra por mensagem."
  echo
  confirma "Entendi o risco. Continuar?"
}

# reconfigura_sessoes_waha: põe nas sessões que já existem a lista de eventos da versão atual.
# Roda em `asimov atualizar`: sessão criada por uma versão anterior não receberia, por exemplo, o
# joinha que devolve a conversa ao agente.
reconfigura_sessoes_waha() {
  local linha
  api GET /admin/agentes
  [ "$API_STATUS" = 200 ] || return 0
  while IFS= read -r linha; do
    api POST "$(caminho_do_agente "$linha")/waha/webhook" '{}'
  done < <(jq -c '.[] | select(.canal == "waha" and .situacao != "inativo")' <<<"$API_RESPOSTA")
  return 0
}

# avisa_numeros_fora_do_ar: define AVISO_WAHA com os agentes cujo número saiu do ar no WhatsApp.
# Chamado uma vez ao abrir o menu: o agente fica mudo quando isso acontece, e é o operador que
# precisa ler o QR code de novo.
avisa_numeros_fora_do_ar() {
  AVISO_WAHA=""
  local linha nome
  api GET /admin/agentes
  [ "$API_STATUS" = 200 ] || return 0
  while IFS= read -r linha; do
    nome=$(jq -r '.nome' <<<"$linha")
    if waha_situacao "$linha" && [ "$WAHA_STATUS" != WORKING ] && [ "$WAHA_STATUS" != SCAN_QR_CODE ]; then
      AVISO_WAHA+="${AVISO_WAHA:+; }$nome ($WAHA_STATUS)"
    fi
  done < <(jq -c '.[] | select(.canal == "waha" and .situacao != "inativo")' <<<"$API_RESPOSTA")
  return 0
}

# prepara_aparelho NOME [EMPRESA]: nome que o celular mostra em Aparelhos conectados.
# O nome é da instalação inteira e vale no instante da leitura do QR code, então o contêiner é
# recriado antes de cada pareamento. Sessão já pareada volta sozinha em segundos.
prepara_aparelho() {
  local nome=$1 empresa=${2:-} aparelho
  aparelho=$(printf '%s%s' "$nome" "${empresa:+ ($empresa)}" | cut -c1-40)
  [ "$(env_get WAHA_CLIENT_DEVICE_NAME)" = "$aparelho" ] && return 0
  env_set WAHA_CLIENT_DEVICE_NAME "$aparelho"
  env_set WAHA_CLIENT_BROWSER_NAME Desktop
  printf '  %sPreparando o aparelho como %s…%s' "$CINZA" "$aparelho" "$NORMAL"
  avisa_manutencao
  dc up -d waha >>"$LOG" 2>&1 || true
  espera_waha_no_ar
  printf '\r\033[K'
  return 0
}

# espera_waha_no_ar: até a WAHA voltar a responder depois de subir ou reiniciar.
espera_waha_no_ar() {
  local tentativa
  for tentativa in $(seq 1 30); do
    api GET /admin/canais/waha
    [ "$API_STATUS" = 200 ] && [ "$(jq -r '.no_ar' <<<"$API_RESPOSTA")" = true ] && return 0
    sleep 2
  done
  return 1
}

# waha_situacao AGENTE_JSON: consulta a sessão. Define WAHA_STATUS, WAHA_QR e WAHA_NUMERO.
waha_situacao() {
  api GET "$(caminho_do_agente "$1")/waha"
  if [ "$API_STATUS" != 200 ]; then
    WAHA_STATUS=ERRO WAHA_QR="" WAHA_NUMERO=""
    return 1
  fi
  WAHA_STATUS=$(jq -r '.status' <<<"$API_RESPOSTA")
  WAHA_QR=$(jq -r '.qr // ""' <<<"$API_RESPOSTA")
  WAHA_NUMERO=$(jq -r '.numero // ""' <<<"$API_RESPOSTA")
  return 0
}

desenha_qr() {
  local texto=$1
  echo
  qrencode -t UTF8 -m 1 -- "$texto" || falha "Não consegui desenhar o QR code aqui."
}

# espera_waha AGENTE_JSON: mostra o QR code até o número parear. 0 pareou, 1 desistiu.
# O QR muda de tempos em tempos: cada texto novo é redesenhado.
espera_waha() {
  local agente=$1 qr_desenhado="" tecla nome
  nome=$(jq -r '.nome' <<<"$agente")
  while true; do
    if ! waha_situacao "$agente"; then
      falha "$(detalhe_erro "$API_RESPOSTA")"
      confirma "Tentar de novo?" || return 1
      continue
    fi
    case "$WAHA_STATUS" in
      WORKING)
        [ -n "$qr_desenhado" ] && secao "WhatsApp de $nome"
        ok "Número $(destaque "+$WAHA_NUMERO") conectado a $(destaque "$nome")"
        return 0
        ;;
      SCAN_QR_CODE)
        if [ -n "$WAHA_QR" ] && [ "$WAHA_QR" != "$qr_desenhado" ]; then
          qr_desenhado=$WAHA_QR
          secao "WhatsApp de $nome"
          dica "No celular: WhatsApp > Configurações > Aparelhos conectados > Conectar aparelho."
          dica "O código muda sozinho de tempos em tempos; se sumir, espere o próximo aqui."
          dica "Esc cancela (o agente fica criado e você pareia depois em Editar agente)."
          desenha_qr "$WAHA_QR"
          printf '  %saguardando a leitura…%s\n' "$CINZA" "$NORMAL"
        fi
        ;;
      FAILED)
        falha "A sessão do WhatsApp falhou."
        confirma "Começar de novo?" || return 1
        api POST "$(caminho_do_agente "$agente")/waha/reiniciar" '{}'
        qr_desenhado=""
        ;;
      STOPPED)
        api POST "$(caminho_do_agente "$agente")/waha/reiniciar" '{}'
        qr_desenhado=""
        ;;
    esac
    if tem_terminal; then
      le_tecla tecla "$WAHA_ESPERA_STATUS"
      [ "$tecla" = esc ] && return 1
    else
      sleep "$WAHA_ESPERA_STATUS"
    fi
  done
}

# escolhe_destino_waha AGENTE_JSON: número ou grupo que recebe o handoff. Define HANDOFF_DESTINO.
# O grupo só aparece com o número já pareado: a lista vem do WhatsApp.
escolhe_destino_waha() {
  local agente=$1 op telefone
  echo
  dica "Quando o agente passar a conversa para uma pessoa, o aviso com o resumo vai para cá."
  dica "Para devolver: 👍 em qualquer mensagem da conversa, ou /retomar com o código do aviso."
  echo
  escolha op "Quem recebe o handoff" \
    "Um número de WhatsApp" \
    "Um grupo  ${CINZA}de que o número do agente participa${NORMAL}"
  if [ "$op" = 2 ] && escolhe_grupo_waha "$agente"; then
    return 0
  fi

  dica "Com DDI e DDD, como 5511988887777. Precisa ser um número que use WhatsApp."
  while true; do
    pergunta telefone "Número que recebe o handoff"
    telefone=$(tr -cd '0-9' <<<"$telefone")
    if [ "${#telefone}" -lt 10 ] || [ "${#telefone}" -gt 15 ]; then
      falha "Número fora do formato: use DDI, DDD e o número, só dígitos."
      continue
    fi
    # Quem diz o id é o WhatsApp: o mesmo celular vale com e sem o nono dígito, e o aviso do
    # handoff só chega no id certo.
    api_com_token POST "$(caminho_do_agente "$agente")/waha/numero" \
      "$(jq -n --arg t "$telefone" '{telefone: $t}')" "Conferindo o número…"
    if [ "$API_STATUS" != 200 ]; then
      aviso "Não consegui conferir o número agora: $(detalhe_erro "$API_RESPOSTA")"
      confirma "Usar assim mesmo?" || continue
      HANDOFF_DESTINO=$(jq -n --arg t "$telefone" '{tipo: "numero", telefone: $t}')
      return 0
    fi
    if [ "$(jq -r '.existe' <<<"$API_RESPOSTA")" != true ]; then
      falha "$(destaque "+$telefone") não tem WhatsApp. Confira o DDD e o nono dígito."
      continue
    fi
    HANDOFF_DESTINO=$(jq -c '{tipo: "numero", telefone: .telefone, chat_id: .chat_id}' <<<"$API_RESPOSTA")
    ok "Número conferido no WhatsApp"
    return 0
  done
}

# Quantos grupos cabem na tela antes de valer a pena filtrar por nome.
GRUPOS_POR_TELA=9

# escolhe_grupo_waha AGENTE_JSON: define HANDOFF_DESTINO com um grupo. 1 se não deu (aí vai por número).
# A lista vem do próprio número, então só existe depois do pareamento.
escolhe_grupo_waha() {
  local agente=$1 grupos filtrados termo op total linha
  local -a rotulos=()
  api_com_token GET "$(caminho_do_agente "$agente")/waha/grupos" "" "Procurando os grupos…"
  if [ "$API_STATUS" != 200 ]; then
    falha "$(detalhe_erro "$API_RESPOSTA")"
    return 1
  fi
  grupos=$API_RESPOSTA
  total=$(jq 'length' <<<"$grupos")
  if [ "$total" -eq 0 ]; then
    echo
    aviso "Não achei nenhum grupo nesse número."
    dica "O número do agente precisa participar do grupo, e o WhatsApp leva um tempo para sincronizar"
    dica "logo depois do pareamento. Você pode escolher um número agora e trocar depois em Editar agente."
    return 1
  fi

  filtrados=$grupos
  while true; do
    if [ "$(jq 'length' <<<"$filtrados")" -gt "$GRUPOS_POR_TELA" ]; then
      echo
      dica "$(jq 'length' <<<"$filtrados") grupos. Digite parte do nome para achar o que você quer."
      pergunta termo "Nome do grupo" "todos"
      if [ "$termo" != todos ]; then
        filtrados=$(filtra_grupos "$grupos" "$termo")
        if [ "$(jq 'length' <<<"$filtrados")" -eq 0 ]; then
          falha "Nenhum grupo com $(destaque "$termo") no nome."
          filtrados=$grupos
          continue
        fi
      fi
    fi
    rotulos=()
    while IFS= read -r linha; do rotulos+=("$linha"); done < <(jq -r '.[].nome' <<<"$filtrados")
    echo
    escolha op "Grupo que recebe o handoff" "${rotulos[@]}" "${CIANO}procurar outro nome${NORMAL}"
    if [ "$op" -gt "${#rotulos[@]}" ]; then
      filtrados=$grupos
      continue
    fi
    HANDOFF_DESTINO=$(jq -c --argjson i "$((op - 1))" '{tipo: "grupo", chat_id: .[$i].chat_id, nome: .[$i].nome}' <<<"$filtrados")
    return 0
  done
}

# filtra_grupos JSON TERMO: grupos cujo nome contém o termo, ignorando acento e maiúscula.
filtra_grupos() {
  local grupos=$1 termo=$2 alvo linhas
  alvo=$(normaliza "$termo")
  linhas=$(jq -r '.[].nome' <<<"$grupos" | normaliza_linhas)
  jq -c --arg alvo "$alvo" --arg linhas "$linhas" '
    ($linhas | split("\n")) as $nomes
    | [to_entries[] | select($nomes[.key] // "" | contains($alvo)) | .value]' <<<"$grupos"
}

# pergunta_retomada [PADRAO] [CANAL]: horas até o agente voltar sozinho depois que uma pessoa
# assume a conversa. Define RETOMADA_HORAS (JSON, `null` quando é para ficar parado).
pergunta_retomada() {
  local horas padrao=${1:-4} canal=${2:-waha}
  echo
  if [ "$canal" = chatwoot ]; then
    dica "Atendente que responde no Chatwoot fica com a conversa. O agente volta quando ela voltar para Pendente, ou sozinho no prazo abaixo. 0 deixa parado."
  elif [ "$canal" = whatsapp ]; then
    dica "Quem recebe o aviso atende pelo próprio WhatsApp e devolve com /retomar. Sem isso, o agente volta sozinho no prazo abaixo. 0 deixa parado."
  else
    dica "Responder pelo aparelho cala o agente na hora. Para devolver: 👍 na conversa ou /retomar. Sem isso, ele volta sozinho no prazo abaixo. 0 deixa parado."
  fi
  pergunta_numero horas "Horas até o agente voltar sozinho (0 a 720)" 0 720 "$padrao"
  if [ "$horas" -eq 0 ]; then
    RETOMADA_HORAS=null
  else
    RETOMADA_HORAS=$horas
  fi
}

# escolhe_contatos_permitidos [JSON_ATUAL]: define CONTATOS_PERMITIDOS (JSON de números).
# Lista vazia é o normal: o agente atende quem mandar mensagem. Grupo o agente nunca responde.
escolhe_contatos_permitidos() {
  local atuais=${1:-[]} op lista padrao invalidos
  padrao=$(jq -r 'join(", ")' <<<"$atuais")
  echo
  dica "Grupo o agente nunca responde; isso vale sempre."
  dica "Enquanto testa, dá para deixar só os seus números falando com ele."
  echo
  escolha op "Quem o agente atende" \
    "Qualquer pessoa que mandar mensagem" \
    "Só os números que eu listar  ${CINZA}para testar antes de abrir${NORMAL}"
  if [ "$op" = 1 ]; then
    CONTATOS_PERMITIDOS="[]"
    return 0
  fi
  dica "Com DDI e DDD, separados por vírgula: 5511988887777, 5511977776666"
  while true; do
    pergunta lista "Números que podem falar com o agente" "$padrao"
    CONTATOS_PERMITIDOS=$(jq -Rc '[splits("[,;]+")] | map(gsub("[^0-9]"; "")) | map(select(length > 0)) | unique' <<<"$lista")
    invalidos=$(jq -r 'map(select(length < 8 or length > 15)) | join(", ")' <<<"$CONTATOS_PERMITIDOS")
    if [ -n "$invalidos" ]; then
      falha "Não entendi: $invalidos. Um número por vírgula, com DDI e DDD."
      continue
    fi
    if [ "$(jq 'length' <<<"$CONTATOS_PERMITIDOS")" -gt 0 ]; then
      ok "Atende $(jq -r 'join(", ")' <<<"$CONTATOS_PERMITIDOS")"
      return 0
    fi
    falha "Nenhum número na lista. Digite ao menos um, com DDI e DDD."
  done
}

# Nome → empresa → ferramentas → cria → QR code → destino do handoff.
# O destino vem depois do pareamento porque a lista de grupos é do próprio número.
fluxo_agente_waha() {
  local nome corpo ferramentas
  AGENTE_CANAL=waha
  secao "Agente no WhatsApp"
  dica "Um número de WhatsApp por agente, pareado aqui pelo QR code."
  aviso_nao_oficial || return 0
  garante_waha
  secao "Agente no WhatsApp"
  pergunta nome "Nome do agente"
  escolhe_empresa ""
  escolhe_ferramentas ferramentas ""
  pergunta_emoji
  pergunta_retomada
  escolhe_contatos_permitidos
  prepara_aparelho "$nome" "$EMPRESA_NOME"

  while true; do
    corpo=$(jq -n --arg nome "$nome" --argjson f "$ferramentas" --argjson horas "$RETOMADA_HORAS" \
      --argjson permitidos "$CONTATOS_PERMITIDOS" --arg emojis "$EMOJIS" \
      '{nome: $nome, canal: "waha", ferramentas: $f, retomada_automatica_horas: $horas,
        contatos_permitidos: $permitidos, emojis: $emojis}')
    api_com_token POST "/admin/clientes/$EMPRESA_ID/agentes" "$(com_modelos "$corpo")" "Criando a sessão na WAHA…"
    if [ "$API_STATUS" = 201 ]; then break; fi
    falha "$(detalhe_erro "$API_RESPOSTA")"
    if [ "$API_STATUS" = 409 ]; then
      pergunta nome "Outro nome para o agente"
    else
      erro_fatal "Não consegui criar o agente" "Confira a WAHA: source deploy/compose.sh && dc logs waha"
    fi
  done

  AGENTE=$API_RESPOSTA
  AGENTE_NOME=$nome
  AGENTE_ID=$(jq -r .id <<<"$AGENTE")
  ok "Agente $(destaque "$nome") criado ${CINZA}· WhatsApp · $EMPRESA_NOME${NORMAL}"

  if espera_waha "$AGENTE"; then
    AGENTE_CAIXA="+$WAHA_NUMERO"
    escolhe_destino_waha "$AGENTE"
    api PATCH "$(caminho_do_agente "$AGENTE")" "$(jq -n --argjson d "$HANDOFF_DESTINO" '{handoff_destino: $d}')"
    if [ "$API_STATUS" = 200 ]; then
      AGENTE=$API_RESPOSTA
      ok "Handoff para $(destaque "$(nome_do_destino "$(jq -c .handoff_destino <<<"$AGENTE")")")"
    else
      falha "$(detalhe_erro "$API_RESPOSTA")"
    fi
  else
    aviso "Número ainda não pareado. Em Editar agente, opção WhatsApp, o QR code aparece de novo."
  fi
}

# Editar agente, opção WhatsApp: mostra o número, pareia de novo ou troca o destino do handoff.
edita_waha() {
  local op nome
  nome=$(jq -r '.nome' <<<"$AGENTE")
  garante_waha
  waha_situacao "$AGENTE" || true
  secao "WhatsApp de $nome"
  case "$WAHA_STATUS" in
    WORKING) campo "Número" "+$WAHA_NUMERO" ;;
    ERRO) campo "Número" "não consegui falar com a WAHA" ;;
    *) campo "Número" "não pareado ($WAHA_STATUS)" ;;
  esac
  campo "Handoff" "$(nome_do_destino "$(jq -c '.handoff_destino' <<<"$AGENTE")")"
  campo "Retomada" "👍 na conversa$(jq -r 'if .retomada_automatica_horas then ", ou sozinho em \(.retomada_automatica_horas) h" else " ou /retomar" end' <<<"$AGENTE")"
  campo "Atende" "$(atende_do_agente "$AGENTE")"
  echo
  ESC_ESCOLHE=5 escolha op "O que fazer?" \
    "Parear o número  ${CINZA}mostra o QR code${NORMAL}" \
    "Quem recebe o handoff" \
    "Horas até voltar sozinho" \
    "Quem o agente atende" \
    "Voltar"
  case "$op" in
    1)
      if [ "$WAHA_STATUS" = WORKING ]; then
        aviso "Parear de novo desconecta o número que está no ar agora."
        confirma "Trocar o número?" || return 0
      fi
      prepara_aparelho "$nome" "$AGENTE_EMPRESA"
      api POST "$(caminho_do_agente "$AGENTE")/waha/reiniciar" '{}'
      espera_waha "$AGENTE" || true
      ;;
    2)
      escolhe_destino_waha "$AGENTE"
      salva_agente "$(jq -n --argjson d "$HANDOFF_DESTINO" '{handoff_destino: $d}')"
      ;;
    3)
      pergunta_retomada "$(jq -r '.retomada_automatica_horas // 0' <<<"$AGENTE")"
      salva_agente "$(jq -n --argjson h "$RETOMADA_HORAS" '{retomada_automatica_horas: $h}')"
      ;;
    4)
      escolhe_contatos_permitidos "$(jq -c '.contatos_permitidos // []' <<<"$AGENTE")"
      salva_agente "$(jq -n --argjson p "$CONTATOS_PERMITIDOS" '{contatos_permitidos: $p}')"
      ;;
  esac
}

# atende_do_agente JSON: como a lista de quem pode falar aparece na ficha.
atende_do_agente() {
  jq -r '(.contatos_permitidos // []) | if length == 0 then "qualquer pessoa (grupos nunca)"
    else "só \(length) número\(if length > 1 then "s" else "" end): \(join(", "))" end' <<<"$1"
}
