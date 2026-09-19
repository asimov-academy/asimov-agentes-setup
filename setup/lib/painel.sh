#!/usr/bin/env bash
# Painel do operador no navegador, em app.<dominio>.
#
# Nasce desligado: quem prefere o terminal segue com `asimov` e nada muda na instalação. Ligar
# escreve o bloco do Caddy em deploy/caddy/painel.caddy, liga PAINEL_ATIVO no .env e reinicia a API,
# que é quem monta as telas.
#
# O primeiro acesso exige um código de uso único mostrado aqui: quem tem a VPS é quem vira dono do
# painel, não quem descobrir o endereço primeiro.

ARQ_CADDY_PAINEL="$RAIZ_PROJETO/deploy/caddy/painel.caddy"

painel_endereco() {
  local sub
  sub=$(env_get SUBDOMINIO_APP)
  [ -n "$sub" ] && printf 'https://%s/painel' "$sub"
}

painel_ligado() { [ "$(env_get PAINEL_ATIVO)" = 1 ]; }

# painel_escreve_caddy [subdominio]: sem subdomínio, deixa o arquivo só com o comentário.
# O domínio vai literal: assim o contêiner do Caddy não precisa de variável nova.
painel_escreve_caddy() {
  local sub=${1:-}
  if [ -z "$sub" ]; then
    printf '# Painel desligado. O comando asimov painel escreve o bloco de app.<dominio> aqui.\n' \
      >"$ARQ_CADDY_PAINEL"
    return 0
  fi
  cat >"$ARQ_CADDY_PAINEL" <<CADDY
# Escrito por asimov painel. Só o painel responde neste host: /admin e /webhook, nunca.
$sub {
	@bloqueado path /admin* /webhook*
	handle @bloqueado {
		respond 404
	}
	redir / /painel 302
	handle {
		reverse_proxy api:8000
	}
}
CADDY
}

# Recarrega o Caddy com o arquivo novo. Mudar o arquivo montado não muda o que ele já carregou.
painel_recarrega_caddy() {
  dc up -d caddy >>"$LOG" 2>&1
  dc exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >>"$LOG" 2>&1 ||
    dc restart caddy >>"$LOG" 2>&1 || true
}

# A API monta as telas do painel no boot, lendo PAINEL_ATIVO: ligar ou desligar pede recriar.
painel_reinicia_api() { dc up -d --force-recreate api >>"$LOG" 2>&1; }

painel_espera_dns() {
  local sub=$1 dominio=$2 ip resolvido resposta anterior=""
  ip=$(ip_publico)
  [ -n "$ip" ] || erro_fatal "Não consegui descobrir o IP público da VPS" "Confira a internet da VPS."

  resolvido=$(ip_do_dominio "$sub" "$dominio")
  if [ "$resolvido" = "$ip" ]; then
    ok "$(destaque "$sub") aponta para esta VPS"
    return 0
  fi
  instrucoes_dns_painel "$ip" "$dominio" "${sub%%.*}"

  while true; do
    resolvido=$(ip_do_dominio "$sub" "$dominio")
    if [ "$resolvido" = "$ip" ]; then
      printf '\r\033[K'
      ok "$(destaque "$sub") aponta para esta VPS"
      return 0
    fi
    if [ "$resolvido" != "$anterior" ] && [ -n "$resolvido" ]; then
      printf '\r\033[K'
      aviso "O registro aponta para $resolvido. Troque o valor para $ip."
      anterior=$resolvido
    fi
    printf '\r\033[K  %s⟳%s Aguardando o DNS %s(checado às %s · Enter checa agora · S desiste)%s ' \
      "$CIANO" "$NORMAL" "$CINZA" "$(date +%H:%M:%S)" "$NORMAL"
    resposta=""
    if IFS= read -r -t "$INTERVALO_DNS" resposta <&3; then
      if [[ "$resposta" =~ ^[Ss]$ ]]; then
        printf '\r\033[K'
        dica "Quando o domínio apontar, rode asimov painel de novo."
        return 1
      fi
      printf '\033[1A'
    fi
  done
}

instrucoes_dns_painel() {
  local ip=$1 dominio=$2 nome=$3
  info "Crie este registro no painel do domínio $(destaque "$dominio"):"
  echo
  printf '    %sTipo%s %sA%s   %sNome%s %s%s%s   %sValor%s %s%s%s   %sTTL%s %s300%s\n' \
    "$CINZA" "$NORMAL" "$NEGRITO" "$NORMAL" "$CINZA" "$NORMAL" "$NEGRITO" "$nome" "$NORMAL" \
    "$CINZA" "$NORMAL" "$NEGRITO" "$ip" "$NORMAL" "$CINZA" "$NORMAL" "$NEGRITO" "$NORMAL"
  echo
  dica "Cloudflare: proxy desligado (nuvem cinza), como no bot."
  echo
}

# Mostra o código de uso único para criar o acesso no navegador.
painel_mostra_codigo() {
  api POST /admin/painel/codigo
  if [ "$API_STATUS" != 200 ]; then
    falha "$(detalhe_erro "$API_RESPOSTA")"
    return 1
  fi
  echo
  campo "Endereço" "$(destaque "$(jq -r '.endereco' <<<"$API_RESPOSTA")")"
  campo "Código" "$(destaque "$(jq -r '.codigo' <<<"$API_RESPOSTA")")"
  dica "Vale por $(jq -r '.minutos' <<<"$API_RESPOSTA") minutos e serve uma vez só."
  echo
}

# O `painel.caddy` é versionado (vazio, com o painel desligado), então o pacote de uma atualização
# passa por cima do bloco que o operador tinha: quem estava com o painel ligado perdia o host
# app.<dominio> depois de `asimov atualizar`, e ele só voltava desligando e ligando de novo.
# Roda em toda atualização e só faz alguma coisa quando o arquivo não tem mais o bloco.
painel_garante_caddy() {
  painel_ligado || return 0
  local sub
  sub=$(env_get SUBDOMINIO_APP)
  [ -n "$sub" ] || return 0
  grep -q "^$sub {" "$ARQ_CADDY_PAINEL" 2>/dev/null && return 0
  painel_escreve_caddy "$sub"
  painel_recarrega_caddy
  ok "Endereço do painel reescrito no servidor web: $(destaque "$sub")"
}

painel_liga() {
  local dominio sub nome
  dominio=$(env_get DOMINIO_BASE)
  [ -n "$dominio" ] || erro_fatal "Sem domínio na instalação" "Rode o setup de novo."

  secao "Ligar o painel"
  dica "Subdomínio do painel. Com app, ele fica em app.$dominio; pode colar do jeito que estiver."
  while true; do
    pergunta nome "Subdomínio do painel" "app"
    # Aceita colado inteiro (https://app.dominio/): fica só o primeiro rótulo.
    nome=$(tr '[:upper:]' '[:lower:]' <<<"$nome" | tr -d '[:space:]')
    nome=${nome#*://}
    nome=${nome%%/*}
    nome=${nome%%.*}
    if [ "$nome" = bot ]; then
      falha "bot.$dominio já é o endereço dos agentes. Escolha outro nome."
    elif [[ "$nome" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
      break
    else
      falha "Use só letras, números e hífen. Ex: app"
    fi
  done
  sub="$nome.$dominio"
  echo

  painel_espera_dns "$sub" "$dominio" || return 0
  echo

  env_set SUBDOMINIO_APP "$sub"
  env_set PAINEL_ATIVO 1
  painel_escreve_caddy "$sub"
  printf '  %sSubindo…%s' "$CINZA" "$NORMAL"
  if ! painel_reinicia_api; then
    printf '\r\033[K'
    falha "A API não reiniciou com o painel ligado. Veja o log: $LOG"
    return 1
  fi
  painel_recarrega_caddy
  printf '\r\033[K'

  # Com conta de IA vinculada, o painel nasce com o copiloto.
  copiloto_acerta || true

  if espera_url "https://$sub/painel/entrar" 24 >/dev/null 2>&1 ||
    espera_url "https://$sub/painel/primeiro-acesso" 6 >/dev/null 2>&1; then
    ok "Painel no ar em $(destaque "https://$sub")"
  else
    aviso "O painel subiu, mas o endereço ainda não respondeu. O certificado pode levar um minuto."
  fi
  painel_mostra_codigo
}

painel_desliga() {
  confirma "Desligar o painel? O endereço para de responder e a conta continua guardada." || return 0
  env_set PAINEL_ATIVO ""
  painel_escreve_caddy ""
  copiloto_desce
  printf '  %sAplicando…%s' "$CINZA" "$NORMAL"
  painel_reinicia_api
  painel_recarrega_caddy
  printf '\r\033[K'
  ok "Painel desligado. A administração segue pelo terminal."
}

painel_esquece_senha() {
  confirma "Apagar a conta do painel e criar outra senha?" || return 0
  api DELETE /admin/painel/operador
  if [ "$API_STATUS" != 204 ]; then
    falha "$(detalhe_erro "$API_RESPOSTA")"
    return 0
  fi
  ok "Conta apagada e sessões derrubadas."
  painel_mostra_codigo
}

# Tela do menu e do comando `asimov painel`.
fluxo_painel() {
  local op estado tem_conta
  local -a rotulos acoes

  if ! painel_ligado; then
    secao "Painel"
    info "Hoje a administração é pelo terminal."
    echo
    confirma "Quer ligar o painel no navegador?" || return 0
    painel_liga
    return 0
  fi

  api GET /admin/painel
  estado=$API_RESPOSTA
  tem_conta=$(jq -r '.tem_operador' <<<"$estado" 2>/dev/null || echo false)

  secao "Painel"
  campo "Endereço" "$(painel_endereco)"
  campo "Acesso" "$([ "$tem_conta" = true ] && echo "conta criada" || echo "ainda sem conta: use um código")"
  echo

  rotulos=("Gerar código de acesso" "Apagar a conta e criar outra senha" "Desligar o painel" "Voltar")
  acoes=(painel_mostra_codigo painel_esquece_senha painel_desliga)
  ESC_ESCOLHE=${#rotulos[@]} escolha op "O que fazer?" "${rotulos[@]}"
  [ "$op" -lt "${#rotulos[@]}" ] || return 0
  "${acoes[$((op - 1))]}"
}

# Oferece o painel uma vez, na instalação e na primeira atualização de quem já tinha instalado.
# Sem isso, o painel só existe para quem ler a lista de comandos no fim: o operador termina o setup
# sem saber que dá para administrar pelo navegador.
tela_painel_oferta() {
  estado_tem painel_perguntado && return 0
  painel_ligado && { estado_set painel_perguntado "$(date -Is)"; return 0; }

  local ip
  ip=$(ip_publico)
  secao "Painel no navegador"
  info "A plataforma está no ar. O painel administra agentes, canais, conversas e consumo pelo"
  info "navegador, no computador e no celular, com passo a passo para criar agente."
  echo
  aviso "Precisa de um registro DNS novo: $(destaque "app.$(env_get DOMINIO_BASE)") apontando para o IP $(destaque "${ip:-desta VPS}")."
  echo

  if confirma "Ligar o painel agora?"; then
    # Falha aqui (API ou contêiner) não pode derrubar a instalação: avisa e segue para o fim.
    painel_liga || aviso "O painel não terminou de ligar. Rode $(destaque "asimov painel") para conferir e gerar o código."
    # A próxima tela limpa o terminal: sem esta pausa o código de primeiro acesso sumia antes de
    # ser lido. Ele também volta no resumo final enquanto a conta não existir.
    pausa "Anote o código e aperte Enter para continuar"
  else
    dica "Quando quiser: asimov painel"
  fi
  estado_set painel_perguntado "$(date -Is)"
}
