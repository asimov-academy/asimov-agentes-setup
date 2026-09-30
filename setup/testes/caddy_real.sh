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
mkdir -p "$TEMP_CADDY/extras"
cp "$REPO/deploy/Caddyfile" "$TEMP_CADDY/Caddyfile"
echo '# Sem painel neste teste' >"$TEMP_CADDY/extras/painel.caddy"
# Backend fictício: /health responde, /webhook/xff devolve o X-Forwarded-For que chegou.
python3 -c '
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        corpo = {"/health": "saudavel", "/webhook/xff": self.headers.get("X-Forwarded-For", "")}.get(self.path, "privado")
        self.send_response(200); self.end_headers(); self.wfile.write(corpo.encode())
http.server.HTTPServer(("127.0.0.1", 8000), H).serve_forever()
' >"$TEMP_CADDY/http.log" 2>&1 &
PID_HTTP=$!
# Modo externo: o proxy do host fala com o Caddy pelo loopback, e o XFF dele precisa chegar à API.
docker run -d --name "$NOME_CADDY" --network host --add-host api:127.0.0.1 \
  -e SUBDOMINIO_BOT=bot.exemplo.test:18880 -e ASIMOV_ESQUEMA=http -e EMAIL_SSL=teste@exemplo.com.br \
  -e ASIMOV_PROXIES_CONFIAVEIS=private_ranges \
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
xff=$(curl -fsS -H 'Host: bot.exemplo.test:18880' -H 'X-Forwarded-For: 203.0.113.7' http://127.0.0.1:18880/webhook/xff)
case "$xff" in 203.0.113.7,*) ;; *) echo "IP do visitante perdido atrás do proxy do host: $xff"; exit 1 ;; esac
echo 'ok: atrás do proxy do host, o IP do visitante chega à API'
