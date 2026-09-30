#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2034  # Comandos falsos chamados pelas funções importadas.
# WAHA com Docker e API de mentira: versão escolhida pelo timer e nome do aparelho no .env.
#   bash setup/testes/simula_waha.sh
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_TESTE=$(mktemp -d)
trap 'rm -rf "$TEMP_TESTE"' EXIT
DIR_ESTADO="$TEMP_TESTE/estado"
ARQ_ESTADO="$DIR_ESTADO/estado"
ARQ_ENV="$TEMP_TESTE/env"
LOG="$TEMP_TESTE/teste.log"
mkdir -p "$DIR_ESTADO"
touch "$ARQ_ESTADO" "$ARQ_ENV" "$LOG"
# shellcheck source=setup/lib/ui.sh
source "$REPO/setup/lib/ui.sh"
# shellcheck source=setup/lib/estado.sh
source "$REPO/setup/lib/estado.sh"
# shellcheck source=setup/lib/waha.sh
source "$REPO/setup/lib/waha.sh"
dc() { echo "dc $*" >>"$TEMP_TESTE/dc"; }
avisa_manutencao() { :; }
espera_waha_no_ar() { :; }
instala_timer_waha() { :; }
apt_instala() { :; }
qrencode() { :; }

# Instalação nova grava a versão base.
instala_waha
[ "$(env_get VERSAO_WAHA)" = "$(versao_waha)" ] ||
  { echo "FALHOU: instalação nova sem a versão base"; exit 1; }
# O timer de domingo subiu a WAHA; `asimov atualizar` (tela_instalacao) não pode rebaixá-la.
env_set VERSAO_WAHA "$(prefixo_waha)2099.1.1"
instala_waha
[ "$(env_get VERSAO_WAHA)" = "$(prefixo_waha)2099.1.1" ] ||
  { echo "FALHOU: a atualização rebaixou a WAHA para $(env_get VERSAO_WAHA)"; exit 1; }
echo 'ok: atualização mantém a versão da WAHA escolhida pelo timer'

