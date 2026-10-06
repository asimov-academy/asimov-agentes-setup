#!/usr/bin/env bash
# shellcheck disable=SC2034  # PASSO_ATUAL e PASSO_TOTAL são lidas por passo(), em estado.sh
# Tela 7: contexto dos assistentes, comando asimov e resumo.

# Só cria arquivos ausentes. Publicação por hard link impede sobrescrever uma edição
# concorrente e só torna visível conteúdo completo; temporário fica no mesmo filesystem.
gera_arquivos_de_contexto() {
  local nome destino temporario
  for nome in AGENTS CLAUDE; do
    destino="$RAIZ_PROJETO/$nome.md"
    [ ! -e "$destino" ] && [ ! -L "$destino" ] || continue
    temporario=$(mktemp "$RAIZ_PROJETO/.contexto.XXXXXX") || return 1
    if ! cat "$RAIZ_PROJETO/modelos/$nome.md.tmpl" >"$temporario" ||
        ! chmod 644 "$temporario"; then
      rm -f "$temporario"
      return 1
    fi
    if ! ln "$temporario" "$destino" 2>/dev/null; then
      rm -f "$temporario"
      [ -e "$destino" ] || [ -L "$destino" ] || return 1
    else
      rm -f "$temporario"
    fi
  done
  garante_contexto_de_evolucao
  garante_permissoes_dos_assistentes
}

# A área de trabalho do assistente de código: `agentes/`. Ele grava só ali (o sandbox do Codex
# limita a escrita à pasta onde abriu; o Claude Code pede aprovação para editar fora), e o código que
# os comandos `asimov` executam (`setup/`, `deploy/`) e o `.env` ficam fora do alcance. Por isso as
# regras que liberam os comandos moram só nesta pasta: aberto na raiz, o assistente que pudesse
# editar `setup/lib` e rodar `asimov` sem aprovação rodaria o que quisesse como root.
AREA_DO_ASSISTENTE="$RAIZ_PROJETO/agentes"
CABECALHO_REGRAS="# Gerado pelo instalador do Asimov Agentes: asimov atualizar reescreve este arquivo."
COMANDOS_LIBERADOS=("asimov agente" "asimov ferramenta" "asimov agentes" "asimov diagnostico")
# Mudam o atendimento ou um sistema de fora: o operador aprova cada um.
COMANDOS_COM_APROVACAO=(
  "asimov agente prompt aplicar" "asimov agente prompt restaurar" "asimov agente conversa"
  "asimov ferramenta ativar" "asimov ferramenta ligar" "asimov ferramenta restaurar"
  "asimov ferramenta segredo" "asimov ferramenta executar"
)

# substitui_bloco ARQUIVO MARCA ARQUIVO_DO_BLOCO: o trecho entre `<!-- MARCA -->` e `<!-- /MARCA -->`
# vira o do bloco (que traz as marcas); sem as duas marcas, o bloco entra no fim. O resto do arquivo
# é do operador e fica. Publica por rename: quem lê nunca vê o arquivo pela metade.
substitui_bloco() {
  local arquivo=$1 ini="<!-- $2 -->" fim="<!-- /$2 -->" bloco=$3 temporario
  temporario=$(mktemp "$(dirname "$arquivo")/.contexto.XXXXXX") || return 1
  if [ -f "$arquivo" ] && grep -qxF "$ini" "$arquivo" && grep -qxF "$fim" "$arquivo"; then
    awk -v ini="$ini" -v fim="$fim" -v bloco="$bloco" '
      $0 == ini && !feito { while ((getline linha < bloco) > 0) print linha; pulando = 1; feito = 1; next }
      pulando { if ($0 == fim) pulando = 0; next }
      { print }' "$arquivo" >"$temporario" || { rm -f "$temporario"; return 1; }
  else
    { if [ -s "$arquivo" ]; then cat "$arquivo"; printf '\n'; fi; cat "$bloco"; } >"$temporario" ||
      { rm -f "$temporario"; return 1; }
  fi
  chmod 644 "$temporario" && mv "$temporario" "$arquivo"
}

# garante_permissoes_dos_assistentes: tira as regras antigas (globais no Codex, na raiz no Claude
# Code) e grava as da área do assistente.
garante_permissoes_dos_assistentes() {
  local regras_antigas="$HOME/.codex/rules/asimov.rules" settings="$RAIZ_PROJETO/.claude/settings.json" limpo
  if [ -f "$regras_antigas" ] && [ "$(head -1 "$regras_antigas")" = "$CABECALHO_REGRAS" ]; then
    rm -f "$regras_antigas"
  fi
  # O sandbox do Codex usa o bubblewrap do sistema; sem ele, avisa em toda abertura.
  if [ -d "$HOME/.codex" ] && ! command -v bwrap >/dev/null 2>&1 && command -v apt_instala >/dev/null 2>&1; then
    apt_instala bubblewrap >>"$LOG" 2>&1 || true
  fi
  if [ -s "$settings" ] && jq -e . "$settings" >/dev/null 2>&1; then
    limpo=$(jq --argjson nossos "$(_regras_do_claude | jq -c '.permissions.allow + .permissions.ask')" '
      if .permissions then
        .permissions.allow = ((.permissions.allow // []) - $nossos)
        | .permissions.ask = ((.permissions.ask // []) - $nossos)
      else . end' "$settings") && printf '%s\n' "$limpo" >"$settings"
  fi
  garante_area_do_assistente
}

# _regras_do_claude: allow, ask e deny do `.claude/settings.json` da área. Caminho com `//` é absoluto.
_regras_do_claude() {
  local comando raiz="/$RAIZ_PROJETO"
  {
    for comando in "${COMANDOS_LIBERADOS[@]}"; do printf 'allow\tBash(%s:*)\n' "$comando"; done
    for comando in "${COMANDOS_COM_APROVACAO[@]}"; do printf 'ask\tBash(%s:*)\n' "$comando"; done
    printf 'deny\t%s\n' "Edit(/.claude/**)" "Edit(/.codex/**)" "Edit($raiz/setup/**)" "Edit($raiz/deploy/**)" \
      "Edit($raiz/.env)" "Read($raiz/.env)"
  } | jq -Rn '[inputs | split("\t")] | {permissions: {
      allow: map(select(.[0] == "allow") | .[1]),
      ask: map(select(.[0] == "ask") | .[1]),
      deny: map(select(.[0] == "deny") | .[1])}}'
}

# garante_area_do_assistente: `agentes/` com AGENTS.md, CLAUDE.md e as permissões dos dois CLIs. O
# Codex só carrega `.codex/rules` de pasta em que o operador confiou, e mantém `.codex` só de
# leitura dentro do sandbox.
garante_area_do_assistente() {
  local area=$AREA_DO_ASSISTENTE settings="$AREA_DO_ASSISTENTE/.claude/settings.json" atual comando prefixo
  mkdir -p "$area/.codex/rules" "$area/.claude"
  chmod 700 "$area"
  substitui_bloco "$area/AGENTS.md" asimov:area "$RAIZ_PROJETO/modelos/assistente/AGENTS.md" || return 1
  [ -e "$area/CLAUDE.md" ] || printf '@AGENTS.md\n' >"$area/CLAUDE.md"
  [ -e "$area/.codex/config.toml" ] ||
    printf '# Área do assistente do Asimov Agentes. As regras dos comandos estão em rules/.\n' >"$area/.codex/config.toml"
  {
    printf '%s\n' "$CABECALHO_REGRAS"
    printf '# Os comandos do Asimov falam com a API local e com o Docker: rodam fora do sandbox.\n'
    for comando in "${COMANDOS_LIBERADOS[@]}"; do
      prefixo=$(jq -cn --arg c "$comando" '$c | split(" ")')
      printf 'prefix_rule(pattern = %s, decision = "allow", justification = "fala com a API local do Asimov")\n' "$prefixo"
    done
    for comando in "${COMANDOS_COM_APROVACAO[@]}"; do
      prefixo=$(jq -cn --arg c "$comando" '$c | split(" ")')
      printf 'prefix_rule(pattern = %s, decision = "prompt", justification = "muda o atendimento: o operador aprova")\n' "$prefixo"
    done
  } >"$area/.codex/rules/asimov.rules"
  atual='{}'
  if [ -s "$settings" ]; then
    if ! atual=$(jq -c . "$settings" 2>/dev/null); then
      # Nunca troca o arquivo do operador por um só com as regras do Asimov.
      printf 'agentes/.claude/settings.json não é JSON válido; permissões do Claude Code não gravadas\n' >>"$LOG"
      return 0
    fi
  fi
  jq --argjson nossas "$(_regras_do_claude)" '
    .permissions.allow = ((.permissions.allow // []) + $nossas.permissions.allow | unique)
    | .permissions.ask = ((.permissions.ask // []) + $nossas.permissions.ask | unique)
    | .permissions.deny = ((.permissions.deny // []) + $nossas.permissions.deny | unique)' <<<"$atual" >"$settings.tmp" &&
    mv "$settings.tmp" "$settings"
}

# garante_contexto_de_evolucao: o AGENTS.md da raiz (do operador; o instalador nunca o troca inteiro)
# ganha ou atualiza só a seção de entrada, que manda evoluir agentes de dentro de `agentes/`.
MARCA_EVOLUCAO="<!-- asimov:evolucao -->"
garante_contexto_de_evolucao() {
  local agentes="$RAIZ_PROJETO/AGENTS.md" bloco
  [ -f "$agentes" ] || return 0
  bloco=$(mktemp) || return 1
  sed -n "/$MARCA_EVOLUCAO/,/<!-- \/asimov:evolucao -->/p" "$RAIZ_PROJETO/modelos/AGENTS.md.tmpl" >"$bloco"
  if ! cmp -s <(sed -n "/$MARCA_EVOLUCAO/,/<!-- \/asimov:evolucao -->/p" "$agentes") "$bloco"; then
    substitui_bloco "$agentes" asimov:evolucao "$bloco" || { rm -f "$bloco"; return 1; }
    printf 'AGENTS.md: seção de evolução de agentes atualizada\n' >>"$LOG"
  fi
  rm -f "$bloco"
}

# contexto_de_evolucao_ok: AGENTS.md da raiz com a orientação e a área do assistente montada.
contexto_de_evolucao_ok() {
  [ -s "$RAIZ_PROJETO/AGENTS.md" ] && grep -qF "$MARCA_EVOLUCAO" "$RAIZ_PROJETO/AGENTS.md" &&
    grep -qF '<!-- asimov:area -->' "$AREA_DO_ASSISTENTE/AGENTS.md" 2>/dev/null &&
    [ -f "$AREA_DO_ASSISTENTE/.codex/rules/asimov.rules" ]
}

instala_comando() {
  $SUDO ln -sf "$RAIZ_PROJETO/setup/asimov.sh" /usr/local/bin/asimov
}

# Painel ligado e ainda sem conta: o código de primeiro acesso aparece aqui, na última tela, que é
# a que fica no terminal. O mostrado ao ligar o painel some quando a tela seguinte limpa tudo.
resumo_acesso_ao_painel() {
  painel_ligado || return 0
  api GET /admin/painel
  [ "$API_STATUS" = 200 ] || return 0
  [ "$(jq -r '.tem_operador' <<<"$API_RESPOSTA" 2>/dev/null || echo true)" = false ] || return 0
  info "Primeiro acesso ao painel: abra o endereço e informe o código."
  painel_mostra_codigo || true
  if estado_tem primeiro_agente_no_painel && ! estado_tem agente_id; then
    dica "Depois de entrar, abra Agentes e clique em novo agente: o passo a passo começa ali."
    echo
  fi
}

mostra_resumo() {
  local sub
  sub=$(env_get SUBDOMINIO_BOT)

  secao "Pronto"
  if [ "$(estado_get agente_canal)" = nativo ]; then
    ok "Agente $(destaque "$(estado_get agente_nome)") criado para conversar no terminal ${CINZA}· $(estado_get agente_conta)${NORMAL}"
    echo
  elif [ "$(estado_get agente_canal)" = waha ]; then
    if [ -n "$(estado_get agente_caixa)" ]; then
      ok "$(destaque "$(estado_get agente_nome)") atende no WhatsApp $(destaque "$(estado_get agente_caixa)") ${CINZA}· $(estado_get agente_conta)${NORMAL}"
    else
      aviso "$(destaque "$(estado_get agente_nome)") criado, mas o número ainda não foi pareado: abra $(destaque asimov) > Editar agente > WhatsApp."
    fi
    echo
  elif [ -n "$(estado_get agente_id)" ]; then
    ok "$(destaque "$(estado_get agente_nome)") no ar na caixa $(destaque "$(estado_get agente_caixa)") ${CINZA}· $(estado_get agente_conta)${NORMAL}"
    echo
  fi
  campo "Versão" "$VERSAO"
  campo "Plataforma" "https://$sub/health"
  if painel_ligado; then
    campo "Painel" "$(painel_endereco)"
  fi
  if vinculo_ligado; then
    campo "Copiloto" "$(ia_nome)$([ -n "$(env_get IA_CONTA)" ] && printf ' · %s' "$(env_get IA_CONTA)")"
  fi
  campo "Pasta" "$RAIZ_PROJETO"
  campo "Assistentes" "evoluir agentes: cd $RAIZ_PROJETO/agentes && claude (ou codex)"
  campo "Uso" "$([ "$(env_get MODO_INSTALACAO)" = revenda ] && echo 'revenda para empresas clientes' || echo 'só a minha empresa')"
  echo
  resumo_acesso_ao_painel
  aviso "Guarde uma cópia do .env fora da VPS: sem ele as credenciais dos canais não abrem."
  echo
  printf '  %sComandos%s\n' "$NEGRITO" "$NORMAL"
  printf '    %sasimov%s               %smenu: criar, editar e remover agentes, ver consumo%s\n' "$CIANO" "$NORMAL" "$CINZA" "$NORMAL"
  printf '    %sasimov novo-agente%s   %soutro agente, para empresa nova ou existente%s\n' "$CIANO" "$NORMAL" "$CINZA" "$NORMAL"
  printf '    %sasimov conversar%s     %sconversa de teste com um agente aqui no terminal%s\n' "$CIANO" "$NORMAL" "$CINZA" "$NORMAL"
  printf '    %sasimov painel%s        %s%s%s\n' "$CIANO" "$NORMAL" "$CINZA" \
    "$(painel_ligado && echo 'código de acesso ao painel no navegador' || echo 'administrar pelo navegador, em app.<domínio>')" "$NORMAL"
  printf '    %sasimov ia%s            %s%s%s\n' "$CIANO" "$NORMAL" "$CINZA" \
    "$(vinculo_ligado && echo 'trocar a conta de IA que move o copiloto do painel' || echo "entrar na conta de $(ia_nome) e ligar o copiloto do painel")" "$NORMAL"
  printf '    %sasimov ajuda%s         %stodos os comandos%s\n' "$CIANO" "$NORMAL" "$CINZA" "$NORMAL"
  echo
}

tela_final() {
  gera_arquivos_de_contexto || erro_fatal "Não foi possível preparar o contexto dos assistentes" \
    "A instalação está salva. Confira $LOG e rode novamente."
  if ! estado_tem instalacao_concluida; then
    secao "Finalizando"
    PASSO_ATUAL=0
    PASSO_TOTAL=1
    passo comando "Comando asimov" "Veja o log." --sem-repetir instala_comando
    estado_set instalacao_concluida "$(date -Is)"
  fi
  mostra_resumo
}
