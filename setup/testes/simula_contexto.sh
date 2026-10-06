#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2034
# Exercita finalização e atualização reais com os serviços substituídos, sem VPS.
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_TESTE=$(mktemp -d)
trap 'rm -rf "$TEMP_TESTE"' EXIT
RAIZ_PROJETO="$TEMP_TESTE/projeto"
DIR_ESTADO="$TEMP_TESTE/estado"
ARQ_ESTADO="$DIR_ESTADO/estado"
LOG="$TEMP_TESTE/teste.log"
mkdir -p "$RAIZ_PROJETO/modelos" "$DIR_ESTADO"
cp -a "$REPO/modelos/." "$RAIZ_PROJETO/modelos/"
touch "$ARQ_ESTADO" "$LOG"
# Casa própria: o teste grava as regras do Codex e nunca pode tocar nas de quem roda.
export HOME="$TEMP_TESTE/casa"
mkdir -p "$HOME/.codex"
# shellcheck source=setup/lib/estado.sh
source "$REPO/setup/lib/estado.sh"
# shellcheck source=setup/lib/final.sh
source "$REPO/setup/lib/final.sh"
secao() { :; }; mostra_resumo() { :; }; instala_comando() { :; }
erro_fatal() { echo "$*" >&2; exit 1; }
date() { command date '+%Y-%m-%dT%H:%M:%S'; }
passo() { shift 3; [ "${1:-}" != --sem-repetir ] || shift; "$@"; }
confere() {
  [ -s "$RAIZ_PROJETO/AGENTS.md" ]
  [ "$(cat "$RAIZ_PROJETO/CLAUDE.md")" = '@AGENTS.md' ]
  if grep -q '{{' "$RAIZ_PROJETO/AGENTS.md"; then return 1; fi
}
tela_final
confere
estado_tem instalacao_concluida
echo 'ok: instalação só termina com contexto disponível'
# Finalização repetida também recupera arquivo perdido.
rm "$RAIZ_PROJETO/CLAUDE.md"
tela_final
confere
# O texto do operador nunca é substituído, inclusive CLAUDE.md próprio.
printf 'Contexto personalizado\n' >"$RAIZ_PROJETO/AGENTS.md"
printf 'Configuração personalizada\n' >"$RAIZ_PROJETO/CLAUDE.md"
gera_arquivos_de_contexto
# O texto do operador fica; só a seção de evolução entra no fim, uma vez.
[ "$(head -1 "$RAIZ_PROJETO/AGENTS.md")" = 'Contexto personalizado' ]
[ "$(grep -c '<!-- asimov:evolucao -->' "$RAIZ_PROJETO/AGENTS.md")" = 1 ]
gera_arquivos_de_contexto
[ "$(grep -c '<!-- asimov:evolucao -->' "$RAIZ_PROJETO/AGENTS.md")" = 1 ]
[ "$(cat "$RAIZ_PROJETO/CLAUDE.md")" = 'Configuração personalizada' ]
echo 'ok: contexto personalizado preservado'
# Carrega só a função de atualização, sem executar o entrypoint real nem acessar .env.
sed -n '/^atualiza() {/,/^}/p' "$REPO/setup/instalar.sh" >"$TEMP_TESTE/atualiza.sh"
# shellcheck source=/dev/null
source "$TEMP_TESTE/atualiza.sh"
banner_asimov() { :; }; tela_modo() { :; }; atualiza_plataforma() { :; }
confere_https_depois_de_atualizar() { :; }
confere_painel_depois_de_atualizar() { :; }
ajusta_permissoes() { :; }; painel_garante_caddy() { :; }; garante_waha() { :; }
instala_timer_waha() { :; }; reconfigura_sessoes_waha() { :; }
tela_handoff_pendente() { :; }; tela_vinculo_ia() { :; }; tela_painel_oferta() { :; }
ASIMOV_ATUALIZAR=1
rm "$RAIZ_PROJETO/AGENTS.md" "$RAIZ_PROJETO/CLAUDE.md"
atualiza
confere
echo 'ok: atualização de instalação antiga recupera os dois arquivos'
# Falha na geração não pode marcar uma instalação nova como concluída.
rm "$RAIZ_PROJETO/AGENTS.md" "$RAIZ_PROJETO/modelos/AGENTS.md.tmpl"
estado_remove instalacao_concluida
if (tela_final) 2>/dev/null; then exit 1; fi
if estado_tem instalacao_concluida; then exit 1; fi
[ -z "$(find "$RAIZ_PROJETO" -name '.contexto.*' -print)" ]
echo 'ok: falha de geração impede sucesso falso e não deixa arquivo parcial'
# Permissões só na área do assistente (agentes/): a regra global antiga do Codex e as entradas da
# raiz no Claude Code saem; o que o operador tinha fica.
cp "$REPO/modelos/AGENTS.md.tmpl" "$RAIZ_PROJETO/modelos/"
mkdir -p "$HOME/.codex/rules" "$RAIZ_PROJETO/.claude"
printf '%s\n%s\n' "$CABECALHO_REGRAS" 'prefix_rule(pattern = ["asimov", "agente"], decision = "allow")' >"$HOME/.codex/rules/asimov.rules"
printf 'prefix_rule(pattern = ["git"], decision = "allow")\n' >"$HOME/.codex/rules/do-operador.rules"
printf '{"permissions":{"allow":["Bash(ls:*)","Bash(asimov agente:*)"],"ask":["Bash(asimov ferramenta ativar:*)"]},"model":"opus"}' \
  >"$RAIZ_PROJETO/.claude/settings.json"
gera_arquivos_de_contexto
gera_arquivos_de_contexto
[ ! -e "$HOME/.codex/rules/asimov.rules" ] || { echo 'regra global do Codex ficou'; exit 1; }
[ -e "$HOME/.codex/rules/do-operador.rules" ]
jq -e '.model == "opus" and .permissions.allow == ["Bash(ls:*)"] and .permissions.ask == []' \
  "$RAIZ_PROJETO/.claude/settings.json" >/dev/null
area="$RAIZ_PROJETO/agentes"
grep -q 'pattern = \["asimov","agente","listar"\], decision = "allow"' "$area/.codex/rules/asimov.rules"
# Prefixo amplo liberado deixava passar o subcomando que pede aprovação escrito de outro jeito.
if grep -q 'pattern = \["asimov","agente"\], decision = "allow"' "$area/.codex/rules/asimov.rules"; then exit 1; fi
for prefixo in '"agente","prompt","aplicar"' '"agente","conversa"' '"ferramenta","ligar"' '"ferramenta","restaurar"' '"ferramenta","ativar"'; do
  grep -q "pattern = \[\"asimov\",$prefixo\], decision = \"prompt\"" "$area/.codex/rules/asimov.rules" ||
    { echo "sem aprovação: $prefixo"; exit 1; }
done
jq -e --arg env "Read(/$RAIZ_PROJETO/.env)" --arg setup "Edit(/$RAIZ_PROJETO/setup/**)" '
  (.permissions.allow | index("Bash(asimov agente listar:*)")) and (.permissions.allow | index("Bash(asimov agente:*)") | not)
  and (.permissions.ask | index("Bash(asimov agente conversa:*)"))
  and (.permissions.deny | index($env)) and (.permissions.deny | index($setup)) and (.permissions.deny | index("Edit(/.claude/**)"))
  and ([.permissions.allow[] | select(. == "Bash(asimov agente listar:*)")] | length == 1)' "$area/.claude/settings.json" >/dev/null
[ "$(cat "$area/CLAUDE.md")" = '@AGENTS.md' ]
[ -f "$area/.codex/config.toml" ]
[ "$(stat -c %a "$area" 2>/dev/null || stat -f %Lp "$area")" = 700 ]
echo 'ok: comandos do Asimov liberados só na área do assistente; o que o operador tinha fica'

# AGENTS.md da área: o trecho da plataforma é reescrito, a nota do operador fica.
printf '\nNota do operador: falar de você.\n' >>"$area/AGENTS.md"
sed -i.bak 's/Fale com o operador em português/TEXTO ANTIGO/' "$area/AGENTS.md" && rm -f "$area/AGENTS.md.bak"
gera_arquivos_de_contexto
grep -q 'Fale com o operador em português' "$area/AGENTS.md"
if grep -q 'TEXTO ANTIGO' "$area/AGENTS.md"; then exit 1; fi
grep -q 'Nota do operador' "$area/AGENTS.md"
[ "$(grep -c '<!-- asimov:area -->' "$area/AGENTS.md")" = 1 ]
echo 'ok: atualização reescreve só o trecho da plataforma na área'

# Seção antiga de evolução no AGENTS.md da raiz é trocada pela nova, sem mexer no resto.
printf 'Regra do operador\n<!-- asimov:evolucao -->\nSiga modelos/guias/evolucao-de-agente.md\n<!-- /asimov:evolucao -->\nFim do operador\n' \
  >"$RAIZ_PROJETO/AGENTS.md"
gera_arquivos_de_contexto
grep -q 'cd agentes' "$RAIZ_PROJETO/AGENTS.md"
if grep -q 'Siga modelos/guias' "$RAIZ_PROJETO/AGENTS.md"; then exit 1; fi
[ "$(head -1 "$RAIZ_PROJETO/AGENTS.md")" = 'Regra do operador' ] && [ "$(tail -1 "$RAIZ_PROJETO/AGENTS.md")" = 'Fim do operador' ]
echo 'ok: seção antiga da raiz trocada pela que manda abrir em agentes/'

# settings.json inválido da área nunca vira um arquivo só com as regras do Asimov.
printf '{ quebrado' >"$area/.claude/settings.json"
gera_arquivos_de_contexto
[ "$(cat "$area/.claude/settings.json")" = '{ quebrado' ]
echo 'ok: settings.json inválido do operador fica como está'
