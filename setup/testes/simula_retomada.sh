#!/usr/bin/env bash
# shellcheck disable=SC2329  # Comandos falsos chamados pelas funções importadas.
# Nenhum Docker, Caddy, firewall ou pacote real é alterado. Configuração e estado são temporários.
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_TESTE=$(mktemp -d)
trap 'rm -rf "$TEMP_TESTE"' EXIT
RAIZ_PROJETO="$TEMP_TESTE/projeto"
DIR_ESTADO="$TEMP_TESTE/estado"
ARQ_ESTADO="$DIR_ESTADO/estado"
ARQ_ENV="$TEMP_TESTE/configuracao-teste"
LOG="$TEMP_TESTE/teste.log"
SUDO=""
mkdir -p "$RAIZ_PROJETO/deploy/caddy" "$DIR_ESTADO"
touch "$ARQ_ESTADO" "$ARQ_ENV" "$LOG"
# shellcheck source=setup/lib/estado.sh
source "$REPO/setup/lib/estado.sh"
# shellcheck source=setup/lib/retomada.sh
source "$REPO/setup/lib/retomada.sh"
# shellcheck source=setup/lib/proxy.sh
source "$REPO/setup/lib/proxy.sh"
# shellcheck source=setup/lib/instalacao.sh
source "$REPO/setup/lib/instalacao.sh"
# shellcheck source=setup/lib/painel.sh
source "$REPO/setup/lib/painel.sh"
ARQ_CADDY_PAINEL="$RAIZ_PROJETO/deploy/caddy/painel.caddy"
date() { command date '+%Y-%m-%dT%H:%M:%S'; }
info() { :; }; dica() { :; }; aviso() { :; }; ok() { :; }; secao() { :; }
erro_fatal() { echo "$*" >&2; exit 1; }
linha_ok() { :; }; linha_rodando() { :; }; linha_erro() { :; }
confirma() { return 1; }
# Retorno de subida não pode ser mascarado pelo reload.
dc() { [ "$1" != up ]; }
if sobe_servicos; then echo 'FALHOU: up recusado virou sucesso'; exit 1; fi
dc() { [ "$1" != exec ]; }
if sobe_servicos; then echo 'FALHOU: reload recusado virou sucesso'; exit 1; fi
echo 'ok: erros de subida e reload propagados'

# Checkpoint válido não repete; inválido reconcilia, depois grava novamente.
(
  confere_passo() { [ "$1" = preservado ]; }
  tarefa() { echo executou >>"$TEMP_TESTE/tarefa"; }
  estado_set passo_preservado 1; estado_set passo_reparar 1
  passo preservado 'preservado' '' --sem-repetir tarefa
  [ ! -e "$TEMP_TESTE/tarefa" ]
  passo reparar 'reparar' '' --sem-repetir tarefa
  [ "$(wc -l <"$TEMP_TESTE/tarefa" | tr -d ' ')" = 1 ]
  estado_tem passo_reparar
)
echo 'ok: retomada revalida antes de pular'

# Banco existente sem segredos não pode criar outra identidade.
(
  docker() { if [ "$1 $2" = 'volume ls' ]; then echo asimov_postgres; fi; }
  if (inventario_instalacao) 2>/dev/null; then exit 1; fi
  for chave in POSTGRES_PASSWORD CHAVE_CRIPTOGRAFIA CHAVE_API_ADMIN; do env_set "$chave" teste; done
  inventario_instalacao
)
echo 'ok: volumes sem chaves impedem regeneração'

# Porta de terceiro é preservada e o gateway fica somente no loopback.
(
  porta_ocupada() { case "$1" in 80|443|8000|18080) return 0 ;; *) return 1 ;; esac; }
  porta_do_asimov() { return 1; }
  escolha() { printf -v "$1" 1; }
  prepara_rede
  [ "$(env_get ASIMOV_PROXY)" = externo ]
  [ "$(env_get ASIMOV_HTTP_BIND)" = 127.0.0.1:18081 ]
  [ "$API_LOCAL" = http://127.0.0.1:8001 ]
)
echo 'ok: portas de terceiros preservadas e API alternativa'
(
  env_set ASIMOV_PROXY proprio
  porta_ocupada() { [ "$1" = 80 ] || [ "$1" = 443 ]; }
  porta_do_asimov() { return 0; }
  escolha() { exit 1; }
  prepara_rede
  [ "$(env_get ASIMOV_PROXY)" = proprio ]
)
echo 'ok: portas do próprio projeto não são conflito'

# Firewall é opt-in e não pode executar nenhum comando quando recusado.
(
  estado_set configurar_firewall nao
  ufw() { exit 99; }
  firewall
)
echo 'ok: firewall preservado por padrão'

# Em modo externo, ambos os hosts do gateway usam HTTP; segredo/admin não entra no snippet.
env_set SUBDOMINIO_BOT bot.exemplo.com.br
env_set SUBDOMINIO_APP app.exemplo.com.br
env_set PAINEL_ATIVO 1
env_set ASIMOV_ESQUEMA http
env_set ASIMOV_PORTA_HTTP 18081
gera_proxy_externo
painel_escreve_caddy app.exemplo.com.br
grep -q '^http://app.exemplo.com.br {' "$ARQ_CADDY_PAINEL"
grep -q '@bloqueado path /admin' "$ARQ_CADDY_PAINEL"
grep -q 'reverse_proxy 127.0.0.1:18081' "$RAIZ_PROJETO/deploy/proxy-externo.caddy"
# já escrito: garante não recarrega nem referencia variável inexistente.
( painel_recarrega_caddy() { exit 99; }; painel_garante_caddy )
echo 'ok: painel retomado usa esquema correto e mantém bloqueios'

# Integração no host: invalidar antes de escrever, rollback no reload e recuperar interrupção.
(
  HOST_CONFIG="$TEMP_TESTE/Caddyfile"
  printf 'outro.exemplo.com.br { respond "preservado" }\n' >"$HOST_CONFIG"
  cp "$HOST_CONFIG" "$TEMP_TESTE/original"
  VALIDACAO=1 RELOAD=0 ATIVO=0
  caddy() { return "$VALIDACAO"; }
  systemctl() {
    case "$1" in
      is-active) return "$ATIVO" ;;
      show) echo "{ argv[]=caddy run --config $HOST_CONFIG --adapter caddyfile ; }" ;;
      reload) return "$RELOAD" ;;
      start) touch "$TEMP_TESTE/iniciou"; return 0 ;;
    esac
  }
  if integra_caddy_host "$HOST_CONFIG"; then exit 1; fi
  cmp "$HOST_CONFIG" "$TEMP_TESTE/original"
  [ ! -e "$TEMP_TESTE/asimov.caddy" ]
  VALIDACAO=0
  integra_caddy_host "$HOST_CONFIG"
  grep -q 'preservado' "$HOST_CONFIG"
  [ "$(grep -c '^import ' "$HOST_CONFIG")" = 1 ]
  integra_caddy_host "$HOST_CONFIG"
  [ "$(grep -c '^import ' "$HOST_CONFIG")" = 1 ]
  cp "$HOST_CONFIG" "$TEMP_TESTE/integrado"
  RELOAD=1
  if integra_caddy_host "$HOST_CONFIG"; then exit 1; fi
  cmp "$HOST_CONFIG" "$TEMP_TESTE/integrado"
  # Reload indisponível conserva a transação; próxima execução restaura e limpa.
  estado_tem proxy_transacao
  printf '# site acrescentado depois\n' >>"$HOST_CONFIG"
  if restaura_proxy 2>/dev/null; then exit 1; fi
  grep -q 'site acrescentado depois' "$HOST_CONFIG"
  cp "$TEMP_TESTE/integrado" "$HOST_CONFIG"
  RELOAD=0 ATIVO=1
  restaura_proxy
  [ -f "$TEMP_TESTE/iniciou" ]
  if estado_tem proxy_transacao; then exit 1; fi
  cmp "$HOST_CONFIG" "$TEMP_TESTE/integrado"
)
echo 'ok: candidato inválido não altera host; reload falho e interrupção recuperáveis'

# Estado e configuração sempre são arquivos completos após substituição.
estado_set teste preservado
env_set TESTE valor
[ "$(estado_get teste)" = preservado ] && [ "$(env_get TESTE)" = valor ]
[ -z "$(find "$DIR_ESTADO" -name '.estado.*' -print)" ]
echo 'ok: escrita atômica preserva estado e configuração'
echo 'Retomada e coexistência: todos os cenários passaram.'
