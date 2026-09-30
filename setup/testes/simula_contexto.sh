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
  ! grep -q '{{' "$RAIZ_PROJETO/AGENTS.md"
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
[ "$(cat "$RAIZ_PROJETO/AGENTS.md")" = 'Contexto personalizado' ]
[ "$(cat "$RAIZ_PROJETO/CLAUDE.md")" = 'Configuração personalizada' ]
echo 'ok: contexto personalizado preservado'
# Carrega só a função de atualização, sem executar o entrypoint real nem acessar .env.
sed -n '/^atualiza() {/,/^}/p' "$REPO/setup/instalar.sh" >"$TEMP_TESTE/atualiza.sh"
# shellcheck source=/dev/null
source "$TEMP_TESTE/atualiza.sh"
banner_asimov() { :; }; tela_modo() { :; }; atualiza_plataforma() { :; }
confere_https_depois_de_atualizar() { :; }
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
