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
info() { :; }; dica() { :; }; aviso() { :; }; ok() { :; }; secao() { :; }; falha() { :; }; destaque() { printf "%s" "$1"; }
erro_fatal() { echo "$*" >&2; exit 1; }
linha_ok() { :; }; linha_rodando() { :; }; linha_erro() { :; }
confirma() { echo "Pergunta técnica inesperada" >&2; exit 99; }
# Retorno de subida não pode ser mascarado pelo reload.
dc() { [ "$1" != up ]; }
if sobe_servicos; then echo 'FALHOU: up recusado virou sucesso'; exit 1; fi
printf 'bot.exemplo {\n}\n' >"$RAIZ_PROJETO/deploy/Caddyfile"
printf '# painel\n' >"$RAIZ_PROJETO/deploy/caddy/painel.caddy"
# O contêiner enxerga o que está no disco: vale o reload, e o reload recusado propaga.
dc() {
  case "$*" in
    *"caddy reload"*) echo reload >>"$TEMP_TESTE/caddy"; return 1 ;;
    *restart*) echo restart >>"$TEMP_TESTE/caddy" ;;
    "exec -T caddy cat /etc/caddy/Caddyfile") cat "$RAIZ_PROJETO/deploy/Caddyfile" ;;
    "exec -T caddy cat /etc/caddy/extras/"*) cat "$RAIZ_PROJETO/deploy/caddy/$(basename "$5")" ;;
  esac
}
if sobe_servicos; then echo 'FALHOU: reload recusado virou sucesso'; exit 1; fi
[ "$(cat "$TEMP_TESTE/caddy")" = reload ] || { echo 'FALHOU: reiniciou com o arquivo em dia'; exit 1; }
# O contêiner preso ao inode antigo do Caddyfile: reinicia, e o restart recusado propaga.
rm -f "$TEMP_TESTE/caddy"
dc() {
  case "$*" in
    *restart*) echo restart >>"$TEMP_TESTE/caddy"; return 1 ;;
    *"caddy reload"*) echo reload >>"$TEMP_TESTE/caddy" ;;
    "exec -T caddy cat /etc/caddy/Caddyfile") echo "Caddyfile antigo" ;;
  esac
}
if sobe_servicos; then echo 'FALHOU: restart recusado virou sucesso'; exit 1; fi
[ "$(cat "$TEMP_TESTE/caddy")" = restart ] || { echo 'FALHOU: recarregou o Caddyfile antigo'; exit 1; }
rm -f "$TEMP_TESTE/caddy" "$RAIZ_PROJETO/deploy/Caddyfile"
echo 'ok: erros de subida, reload e restart propagados; Caddyfile antigo reinicia o Caddy'

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
  escolha() { echo "Escolha técnica inesperada" >&2; exit 99; }
  prepara_rede
  [ "$(env_get ASIMOV_PROXY)" = externo ]
  [ "$(env_get ASIMOV_HTTP_BIND)" = 127.0.0.1:18081 ]
  [ "$API_LOCAL" = http://127.0.0.1:8001 ]
  # Atrás do proxy do host, todo pedido chega pelo gateway da rede do Docker: sem confiar nele, todo
  # visitante tinha o mesmo IP, e cinco senhas erradas de qualquer um trancavam o painel.
  [ "$(env_get ASIMOV_PROXIES_CONFIAVEIS)" = private_ranges ]
)
echo 'ok: portas de terceiros preservadas e API alternativa'
(
  env_set ASIMOV_PROXY proprio
  porta_ocupada() { [ "$1" = 80 ] || [ "$1" = 443 ]; }
  porta_do_asimov() { return 0; }
  escolha() { exit 1; }
  prepara_rede
  [ "$(env_get ASIMOV_PROXY)" = proprio ]
  [ "$(env_get ASIMOV_PROXIES_CONFIAVEIS)" = 127.0.0.1/32 ]
)
echo 'ok: portas do próprio projeto não são conflito'

# Firewall é preservado inclusive se uma versão antiga salvou autorização.
(
  estado_set configurar_firewall sim
  ufw() { exit 99; }
  firewall
  [ "$(estado_get configurar_firewall)" = nao ]
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

# Painel que não sobe (pull falhou por rede ou disco) não fica ligado no .env nem no Caddy.
(
  env_set PAINEL_ATIVO ""
  env_set DOMINIO_BASE exemplo.com.br
  acesso_garante() { return 0; }
  pergunta() { printf -v "$1" '%s' app; }
  painel_espera_dns() { return 0; }
  CINZA="" NORMAL=""
  dc() { echo "dc $*" >>"$TEMP_TESTE/dc-painel"; [ "$1" != pull ]; }
  if painel_liga >/dev/null; then echo 'FALHOU: painel que não subiu virou sucesso'; exit 1; fi
  [ -z "$(env_get PAINEL_ATIVO)" ] || { echo 'FALHOU: PAINEL_ATIVO ficou ligado'; exit 1; }
  ! grep -q 'app.exemplo.com.br' "$ARQ_CADDY_PAINEL" || { echo 'FALHOU: bloco do painel ficou no Caddy'; exit 1; }
  grep -q '^dc rm -f painel' "$TEMP_TESTE/dc-painel" || { echo 'FALHOU: contêiner do painel ficou para trás'; exit 1; }
)
echo 'ok: painel que não sobe é desfeito'

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

# Integração perdida (outra ferramenta regravou o Caddyfile) é vista e refeita; domínio colado à
# mão não trava a atualização. O diagnóstico do dia 29/09 mostrava só `000`.
(
  HOST_CONFIG="$TEMP_TESTE/perdido/Caddyfile"
  mkdir -p "$(dirname "$HOST_CONFIG")"
  printf 'outro.exemplo.com.br { respond "preservado" }\n' >"$HOST_CONFIG"
  caddy() { return 0; }
  systemctl() {
    case "$1" in
      is-active) return 0 ;;
      show) echo "{ argv[]=caddy run --config $HOST_CONFIG --adapter caddyfile ; }" ;;
      reload) return 0 ;;
    esac
  }
  confirma() { return 0; }
  env_set ASIMOV_PROXY externo
  gera_proxy_externo
  integra_caddy_host "$HOST_CONFIG"
  [ "$(situacao_caddy_host)" = integrado ]
  # Outra ferramenta regrava o arquivo só com os sites dela.
  printf 'outro.exemplo.com.br { respond "preservado" }\n' >"$HOST_CONFIG"
  [ "$(situacao_caddy_host)" = perdido ]
  repara_caddy_host >/dev/null
  [ "$(situacao_caddy_host)" = integrado ]
  grep -q 'preservado' "$HOST_CONFIG"
  # Colado à mão: fica como está, e integrar de novo não duplica o domínio nem falha.
  printf 'outro.exemplo.com.br { respond "preservado" }\nbot.exemplo.com.br {\n reverse_proxy 127.0.0.1:18081\n}\n' >"$HOST_CONFIG"
  cp "$HOST_CONFIG" "$TEMP_TESTE/perdido/manual"
  [ "$(situacao_caddy_host)" = manual ]
  integra_caddy_ou_explica >/dev/null
  cmp "$HOST_CONFIG" "$TEMP_TESTE/perdido/manual"
  # Sem integração do Asimov (outro proxy), nada é oferecido.
  estado_remove proxy_host_integrado
  [ "$(situacao_caddy_host)" = sem_integracao ]
  repara_caddy_host
)
echo 'ok: integração perdida é vista e refeita; domínio colado à mão não trava'

# Caddy padrão é integrado sem pergunta; proxy desconhecido preserva o host e para.
(
  env_set ASIMOV_PROXY externo
  estado_remove proxy_host_integrado
  caddy() { :; }
  systemctl() { [ "$1" = is-active ]; }
  integra_caddy_host() { touch "$TEMP_TESTE/automatico"; }
  configura_proxy_externo
  [ -f "$TEMP_TESTE/automatico" ]
  systemctl() { return 1; }
  confere_https() { return 1; }
  if (configura_proxy_externo) 2>/dev/null; then exit 1; fi
  confere_https() { return 0; }
  configura_proxy_externo
)
echo 'ok: acesso automático sem perguntas; proxy desconhecido preservado'

# Estado e configuração sempre são arquivos completos após substituição.
estado_set teste preservado
env_set TESTE valor
[ "$(estado_get teste)" = preservado ] && [ "$(env_get TESTE)" = valor ]
[ -z "$(find "$DIR_ESTADO" -name '.estado.*' -print)" ]
echo 'ok: escrita atômica preserva estado e configuração'

# Timer do backup e da WAHA roda como root com o HOME do operador: o arquivo novo leva o dono do
# antigo, senão o estado e o .env viravam root e o `asimov` do operador parava de ler os dois.
(
  id() { [ "$1" = -u ] && echo 0; }
  chown() { printf '%s\n' "$*" >>"$TEMP_TESTE/chown"; }
  estado_set dono mantido
  estado_remove dono
  env_set DONO mantido
  [ "$(grep -c -- "--reference=$ARQ_ESTADO " "$TEMP_TESTE/chown")" = 2 ]
  grep -q -- "--reference=$ARQ_ENV " "$TEMP_TESTE/chown"
)
echo 'ok: estado e .env regravados como root mantêm o dono'
echo 'Retomada e coexistência: todos os cenários passaram.'
