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

# Nome do agente com o que o Compose interpreta no .env: sai limpo, e o .env continua legível.
prepara_aparelho "Ofertas R\$ 10 \"top\"" "'Loja #1\`" >/dev/null
aparelho=$(env_get WAHA_CLIENT_DEVICE_NAME)
case "$aparelho" in
  *[\$\"\'\`\\#]*) echo "FALHOU: nome do aparelho cru no .env: $aparelho"; exit 1 ;;
esac
[ "$aparelho" = "Ofertas R 10 top (Loja 1)" ] || { echo "FALHOU: nome inesperado: $aparelho"; exit 1; }
prepara_aparelho "\$\$\$" >/dev/null
[ "$(env_get WAHA_CLIENT_DEVICE_NAME)" = "Asimov Agentes" ] ||
  { echo "FALHOU: nome vazio no aparelho"; exit 1; }
# Valor com quebra de linha nunca entra no .env: viraria outra chave.
if env_set TESTE "$(printf 'a\nINJETADA=1')"; then echo "FALHOU: quebra de linha no .env"; exit 1; fi
! grep -q '^INJETADA=' "$ARQ_ENV" || { echo "FALHOU: chave injetada no .env"; exit 1; }
echo 'ok: nome do aparelho e valores do .env não quebram o Compose'
