#!/usr/bin/env bash
# Simula, sem VPS, o agente respondendo pela assinatura ChatGPT pelo terminal (experimental):
# instalação retomada escolhendo a assinatura na criação do agente (que liga ali mesmo, sem token e
# sem painel), a reserva pedida na hora, a edição de um agente sem reserva, desligar e recusar.
# API e Docker são falsos; o que se confere é o .env, o `dc` e o JSON enviado à API.
#   bash setup/testes/simula_assinatura.sh
set -Eeuo pipefail
RAIZ_PROJETO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR=$(mktemp -d)
export HOME=$DIR
RESPOSTAS="$DIR/respostas.txt"
# Na ordem das perguntas:
# - criar agente: assinatura (6, depois dos cinco provedores com chave), ligar (Sim), segundo modelo (2), reserva OpenAI (1), chave, modelo 1;
# - editar a resposta de um agente sem reserva (1): assinatura (6), modelo 1, reserva OpenAI (1), modelo 1;
# - desligar (Sim);
# - criar agente de novo: assinatura (6), recusar ligar (Não), OpenAI (1), modelo 1.
printf '%s\n' 6 s 2 1 boa 1 1 6 1 1 1 s 6 n 1 1 >"$RESPOSTAS"
export ASIMOV_TTY=$RESPOSTAS
# shellcheck source=setup/lib/base.sh
source "$RAIZ_PROJETO/setup/lib/base.sh"
ARQ_ENV=$DIR/.env
estado_iniciar
clear() { :; }
dc() { echo "dc $*" >>"$DIR/dc.log"; }
espera_url() { :; }
# O token da trilha nunca pode ser pedido aqui: se alguém chamar, a simulação falha.
acesso_garante() { falhou "a assinatura pediu o token da trilha"; }

# Instalação retomada: empresa e Codex vinculado, mas a pergunta da assinatura nunca apareceu.
env_set MODO_INSTALACAO empresa
env_set AGENTE_CODIGO codex
env_set IA_VINCULADA 1

# A API de verdade só diz que a assinatura vale com as três condições; aqui, a do .env basta.
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

assinatura_vale && falhou "a assinatura valia antes de ser ligada"
assinatura_oferece || falhou "a assinatura não foi oferecida na instalação retomada"

escolhe_modelo_do_novo_agente
esperado='{"modelo_conversa":"assinatura:gpt-6-luna","modelo_fallback":"openai:gpt-6.1-sol"}'
[ "$(jq -cS . <<<"$MODELOS_NOVO_AGENTE")" = "$esperado" ] ||
  falhou "modelos do agente novo: $MODELOS_NOVO_AGENTE"
[ "$(env_get ASSINATURA_NO_ATENDIMENTO)" = 1 ] || falhou "escolher a assinatura não a ligou"
grep -q 'dc pull assinatura' "$DIR/dc.log" || falhou "a imagem da assinatura não foi baixada"
grep -q 'up -d --force-recreate assinatura' "$DIR/dc.log" || falhou "o contêiner da assinatura não subiu"
grep -q 'up -d --force-recreate api worker' "$DIR/dc.log" || falhou "API e worker não foram recriados"
grep -q 'copiloto' "$DIR/dc.log" && falhou "a assinatura mexeu no copiloto"
[ -z "$(env_get COPILOTO_ATIVO)" ] || falhou "a assinatura ligou o copiloto"

# Agente antigo, sem reserva: a troca para a assinatura já leva a reserva no mesmo PATCH.
AGENTE='{"modelo_conversa":"openai:gpt-5.5","modelo_fallback":null,"modelo_auxiliar":"openai:gpt-5-mini","modelo_visao":"openai:gpt-5-mini","modelo_transcricao":"openai:whisper-1"}'
escolhe_modelo_do_agente
esperado='{"modelo_conversa":"assinatura:gpt-6.1-sol","modelo_fallback":"openai:gpt-6.1-sol"}'
[ "$(jq -cS . <<<"$CORPO_MODELO")" = "$esperado" ] || falhou "edição para a assinatura: $CORPO_MODELO"

: >"$DIR/dc.log"
assinatura_desliga
[ -z "$(env_get ASSINATURA_NO_ATENDIMENTO)" ] || falhou "desligar não limpou ASSINATURA_NO_ATENDIMENTO"
grep -q 'dc --profile assinatura rm -sf assinatura' "$DIR/dc.log" || falhou "o contêiner da assinatura não saiu"

# Recusar ligar na hora da escolha volta para a lista só com provedores de chave.
escolhe_modelo_do_novo_agente
[ "$(jq -cS . <<<"$MODELOS_NOVO_AGENTE")" = '{"modelo_conversa":"openai:gpt-6.1-sol"}' ] ||
  falhou "recusar a assinatura: $MODELOS_NOVO_AGENTE"
[ -z "$(env_get ASSINATURA_NO_ATENDIMENTO)" ] || falhou "recusar ligou a assinatura"

# Na revenda a opção não existe, nem com o Codex vinculado.
env_set MODO_INSTALACAO revenda
assinatura_oferece && falhou "a assinatura foi oferecida na revenda"

echo "simula_assinatura: ok"
