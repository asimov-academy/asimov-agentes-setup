#!/usr/bin/env bash
# Segredo nunca vai como argumento de processo: `jq --arg` ou `--argjson` com token, chave secreta
# ou chave de provedor deixa o valor em `ps` para qualquer usuário da VPS (auditoria A13). Passa
# pelo ambiente (env.NOME) ou pelo stdin.
#   bash setup/testes/simula_segredos.sh
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if grep -nE -- '--arg(json)? +[A-Za-z_]+ +"\$\{?(chave|token|segredo|senha|WHATSAPP_CONEXAO)\b' \
  "$REPO"/setup/lib/*.sh "$REPO"/setup/*.sh "$REPO"/deploy/*.sh; then
  echo 'FALHOU: segredo como argumento do jq (acima)'
  exit 1
fi
echo 'ok: nenhum segredo como argumento do jq'
