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

# garante_permissoes_dos_assistentes: `asimov agente` e `asimov ferramenta` falam com a API em
# 127.0.0.1 e com o Docker. O Codex roda cada comando num sandbox sem rede e pedia aprovação a cada
# um (o aluno via "a API não respondeu"). A regra `allow` roda fora do sandbox sem perguntar; ativar,
# segredo e executar ficam em `prompt`, e o operador aprova. O arquivo é da plataforma: a
# atualização o reescreve. No Claude Code o mesmo vai no settings do projeto, somando ao que existe.
garante_permissoes_dos_assistentes() {
  local regras="$HOME/.codex/rules" settings="$RAIZ_PROJETO/.claude/settings.json" atual
  if [ -d "$HOME/.codex" ]; then
    # O sandbox do Codex usa o bubblewrap do sistema; sem ele, avisa em toda abertura.
    if ! command -v bwrap >/dev/null 2>&1 && command -v apt_instala >/dev/null 2>&1; then
      apt_instala bubblewrap >>"$LOG" 2>&1 || true
    fi
    mkdir -p "$regras"
    cat >"$regras/asimov.rules" <<'REGRAS'
# Gerado pelo instalador do Asimov Agentes: asimov atualizar reescreve este arquivo.
# Os comandos do Asimov falam com a API local (127.0.0.1) e com o Docker: rodam fora do sandbox.
prefix_rule(pattern = ["asimov", "agente"], decision = "allow", justification = "fala com a API local do Asimov")
prefix_rule(pattern = ["asimov", "ferramenta"], decision = "allow", justification = "fala com a API local e com o Docker")
prefix_rule(pattern = ["asimov", "agentes"], decision = "allow", justification = "lista os agentes pela API local")
prefix_rule(pattern = ["asimov", "diagnostico"], decision = "allow", justification = "confere a instalação")
prefix_rule(pattern = ["asimov", "ferramenta", "ativar"], decision = "prompt", justification = "muda o atendimento: o operador aprova")
prefix_rule(pattern = ["asimov", "ferramenta", "segredo"], decision = "prompt", justification = "credencial: o operador aprova")
prefix_rule(pattern = ["asimov", "ferramenta", "executar"], decision = "prompt", justification = "chamada de verdade: o operador aprova")
REGRAS
  fi
  mkdir -p "$RAIZ_PROJETO/.claude"
  atual='{}'
  if [ -s "$settings" ]; then
    atual=$(jq -c . "$settings" 2>/dev/null || echo '{}')
  fi
  jq '.permissions.allow = ((.permissions.allow // []) + [
        "Bash(asimov agente:*)", "Bash(asimov ferramenta:*)", "Bash(asimov agentes:*)", "Bash(asimov diagnostico:*)"
      ] | unique)
      | .permissions.ask = ((.permissions.ask // []) + [
        "Bash(asimov ferramenta ativar:*)", "Bash(asimov ferramenta segredo:*)", "Bash(asimov ferramenta executar:*)"
      ] | unique)' <<<"$atual" >"$settings.tmp" && mv "$settings.tmp" "$settings"
}

# garante_contexto_de_evolucao: AGENTS.md que já existia (o instalador nunca o sobrescreve) ganha só
# a seção de entrada, uma vez. O resto do texto do operador fica como está.
MARCA_EVOLUCAO="<!-- asimov:evolucao -->"
garante_contexto_de_evolucao() {
  local agentes="$RAIZ_PROJETO/AGENTS.md"
  [ -f "$agentes" ] || return 0
  grep -qF "$MARCA_EVOLUCAO" "$agentes" && return 0
  {
    printf '\n'
    sed -n "/$MARCA_EVOLUCAO/,/<!-- \/asimov:evolucao -->/p" "$RAIZ_PROJETO/modelos/AGENTS.md.tmpl"
  } >>"$agentes"
  printf 'AGENTS.md: acrescentada a seção de evolução de agentes\n' >>"$LOG"
}

# contexto_de_evolucao_ok: AGENTS.md com a orientação de entrada. Diagnóstico avisa quando falta.
contexto_de_evolucao_ok() {
  [ -s "$RAIZ_PROJETO/AGENTS.md" ] && grep -qF "$MARCA_EVOLUCAO" "$RAIZ_PROJETO/AGENTS.md"
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
  campo "Assistentes" "AGENTS.md e CLAUDE.md disponíveis nesta pasta"
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
