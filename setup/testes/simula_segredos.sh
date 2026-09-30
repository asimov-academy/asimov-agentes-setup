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

# O copiloto roda pela assinatura, nunca por chave de API: o `claude -p` herda o ambiente, e uma
# ANTHROPIC_API_KEY de instalação antiga no .env fazia cada turno ser cobrado na conta de API.
copiloto=$(awk '/^  copiloto:/ {dentro=1; next} dentro && /^  [a-z]/ {exit} dentro' "$REPO/deploy/docker-compose.yml")
for chave in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN OPENAI_API_KEY CODEX_API_KEY; do
  grep -qE "^ +$chave: \"\"$" <<<"$copiloto" ||
    { echo "FALHOU: o copiloto herda $chave do .env"; exit 1; }
done
echo 'ok: copiloto sem chave de API no ambiente'
