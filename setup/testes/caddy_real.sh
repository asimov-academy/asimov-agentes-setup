#!/usr/bin/env bash
# Exercita o gateway com Caddy real em Linux; backend fictício só neste teste.
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_CADDY=$(mktemp -d)
NOME_CADDY="asimov-teste-caddy-$$"
PID_HTTP=""
limpa() {
  docker rm -f "$NOME_CADDY" >/dev/null 2>&1 || true
  [ -z "$PID_HTTP" ] || kill "$PID_HTTP" 2>/dev/null || true
  rm -rf "$TEMP_CADDY"
}
trap limpa EXIT
mkdir -p "$TEMP_CADDY/extras" "$TEMP_CADDY/backend/admin"
echo saudavel >"$TEMP_CADDY/backend/health"
echo privado >"$TEMP_CADDY/backend/admin/index.html"
cp "$REPO/deploy/Caddyfile" "$TEMP_CADDY/Caddyfile"
echo '# Sem painel neste teste' >"$TEMP_CADDY/extras/painel.caddy"
python3 -m http.server 8000 --bind 127.0.0.1 --directory "$TEMP_CADDY/backend" >"$TEMP_CADDY/http.log" 2>&1 &
PID_HTTP=$!
docker run -d --name "$NOME_CADDY" --network host --add-host api:127.0.0.1 \
  -e SUBDOMINIO_BOT=bot.exemplo.test:18880 -e ASIMOV_ESQUEMA=http -e EMAIL_SSL=teste@exemplo.com.br \
  -v "$TEMP_CADDY/Caddyfile:/etc/caddy/Caddyfile:ro" \
  -v "$TEMP_CADDY/extras:/etc/caddy/extras:ro" caddy:2-alpine >/dev/null
for _ in $(seq 1 30); do
  if curl -fsS -H 'Host: bot.exemplo.test:18880' http://127.0.0.1:18880/health >"$TEMP_CADDY/resposta"; then break; fi
  sleep 1
done
grep -q saudavel "$TEMP_CADDY/resposta"
for caminho in /admin /admin/ /admin/clientes /painel/api /openapi.json; do
  codigo=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Host: bot.exemplo.test:18880' "http://127.0.0.1:18880$caminho")
  [ "$codigo" = 404 ] || { echo "Caminho privado exposto: $caminho ($codigo)"; exit 1; }
done
echo 'ok: gateway real responde health e bloqueia caminhos privados'
