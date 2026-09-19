#!/usr/bin/env bash
# Chamado pelo timer asimov-waha.timer (domingo de madrugada), nunca à mão no dia a dia.
# Confere se saiu versão nova da WAHA, atualiza e volta para a anterior se algum número que estava
# conectado não voltar. O resultado fica no estado do setup e aparece no menu `asimov`.
# Para rodar na hora, use o menu: asimov > WhatsApp (WAHA) > Procurar versão nova agora.
set -Eeuo pipefail

RAIZ_PROJETO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=setup/lib/base.sh
source "$RAIZ_PROJETO/setup/lib/base.sh"

estado_iniciar

printf '\n===== conferindo a versão da WAHA em %s =====\n' "$(date -Is)" >>"$LOG"
atualiza_waha --silencioso
