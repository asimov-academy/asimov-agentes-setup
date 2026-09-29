#!/usr/bin/env bash
# Simula, sem VPS, o agente respondendo pela assinatura ChatGPT pelo terminal (experimental):
# ligar em `asimov ia`, escolher a assinatura ao criar o agente com a reserva pedida na hora,
# e desligar. API, Docker e registro são falsos; o que se confere é o .env, o `dc` e o JSON.
#   bash setup/testes/simula_assinatura.sh
set -Eeuo pipefail
RAIZ_PROJETO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR=$(mktemp -d)
export HOME=$DIR
RESPOSTAS="$DIR/respostas.txt"
# Na ordem das perguntas: ligar (Sim); criar agente escolhendo a assinatura (5), o segundo modelo
# dela (2), a reserva na OpenAI (1), a chave e o primeiro modelo (1); editar a resposta de um agente
# sem reserva (1) para a assinatura (5, modelo 1), com a reserva na OpenAI (1, modelo 1), que já tem
# chave; desligar (Sim).
printf '%s\n' s 5 2 1 boa 1 1 5 1 1 1 s >"$RESPOSTAS"
export ASIMOV_TTY=$RESPOSTAS
# shellcheck source=setup/lib/base.sh
source "$RAIZ_PROJETO/setup/lib/base.sh"
ARQ_ENV=$DIR/.env
estado_iniciar
clear() { :; }
dc() { echo "dc $*" >>"$DIR/dc.log"; }
acesso_valido() { return 0; }

env_set MODO_INSTALACAO empresa
env_set AGENTE_CODIGO codex
env_set IA_VINCULADA 1

# A API de verdade só oferece a assinatura com as três condições; aqui, a do .env basta.
api() {
  case "$1 $2" in
    "GET /admin/ia/chaves")
      API_STATUS=200
      API_RESPOSTA=$(jq -nc --arg c "$(cat "$DIR/chaves" 2>/dev/null || true)" \
        --argjson a "$([ "$(env_get ASSINATURA_NO_ATENDIMENTO)" = 1 ] && echo true || echo false)" \
        '{com_chave: ($c | split(" ") | map(select(. != ""))), assinatura: {disponivel: $a, motivo: "", campos: ["modelo_conversa", "modelo_auxiliar"]}}') ;;
    "PUT /admin/ia/chaves/"*)
      printf '%s ' "${2##*/}" >>"$DIR/chaves"
      API_STATUS=204
      API_RESPOSTA='' ;;
    "GET /admin/ia/modelos/assinatura?funcao=conversa") API_STATUS=200; API_RESPOSTA='["assinatura:gpt-6.1-sol","assinatura:gpt-6-luna"]' ;;
    "GET /admin/ia/modelos/openai?funcao=conversa") API_STATUS=200; API_RESPOSTA='["openai:gpt-6.1-sol","openai:gpt-6-astra"]' ;;
    *) API_STATUS=404; API_RESPOSTA='{"detail":"rota fora da simulação"}' ;;
  esac
}

falhou() {
  echo "FALHOU: $*" >&2
  exit 1
}

assinatura_vale && falhou "a assinatura apareceu antes de ser ligada"

assinatura_liga
[ "$(env_get ASSINATURA_NO_ATENDIMENTO)" = 1 ] || falhou "ligar não gravou ASSINATURA_NO_ATENDIMENTO=1"
[ "$(env_get COPILOTO_ATIVO)" = 1 ] || falhou "o contêiner da assinatura não subiu sem o painel"
grep -q 'up -d --force-recreate copiloto' "$DIR/dc.log" || falhou "o copiloto não foi recriado"
grep -q 'up -d --force-recreate api worker' "$DIR/dc.log" || falhou "API e worker não foram recriados"
assinatura_vale || falhou "a assinatura não apareceu depois de ligada"

escolhe_modelo_do_novo_agente
esperado='{"modelo_conversa":"assinatura:gpt-6-luna","modelo_fallback":"openai:gpt-6.1-sol"}'
[ "$(jq -cS . <<<"$MODELOS_NOVO_AGENTE")" = "$esperado" ] ||
  falhou "modelos do agente novo: $MODELOS_NOVO_AGENTE"

# Agente antigo, sem reserva: a troca para a assinatura já leva a reserva no mesmo PATCH.
AGENTE='{"modelo_conversa":"openai:gpt-5.5","modelo_fallback":null,"modelo_auxiliar":"openai:gpt-5-mini","modelo_visao":"openai:gpt-5-mini","modelo_transcricao":"openai:whisper-1"}'
escolhe_modelo_do_agente
esperado='{"modelo_conversa":"assinatura:gpt-6.1-sol","modelo_fallback":"openai:gpt-6.1-sol"}'
[ "$(jq -cS . <<<"$CORPO_MODELO")" = "$esperado" ] || falhou "edição para a assinatura: $CORPO_MODELO"

: >"$DIR/dc.log"
assinatura_desliga
[ -z "$(env_get ASSINATURA_NO_ATENDIMENTO)" ] || falhou "desligar não limpou ASSINATURA_NO_ATENDIMENTO"
[ -z "$(env_get COPILOTO_ATIVO)" ] || falhou "o contêiner da assinatura ficou no ar sem painel"
grep -q 'stop copiloto' "$DIR/dc.log" || falhou "o copiloto não parou"

# Na revenda a opção não existe, nem com o Codex vinculado.
env_set MODO_INSTALACAO revenda
assinatura_cabe && falhou "a assinatura coube na revenda"

echo "simula_assinatura: ok"
