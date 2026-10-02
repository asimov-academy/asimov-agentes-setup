#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2034  # Comandos falsos chamados pelas funções importadas.
# Base de conhecimento pelo terminal, com a API de mentira: cada ação chama a rota certa.
#   bash setup/testes/simula_conhecimento.sh
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_TESTE=$(mktemp -d)
trap 'rm -rf "$TEMP_TESTE"' EXIT
RESPOSTAS="$TEMP_TESTE/respostas"
export ASIMOV_TTY="$RESPOSTAS"
ARQ_ENV="$TEMP_TESTE/env"
: >"$ARQ_ENV"
# shellcheck source=setup/lib/ui.sh
source "$REPO/setup/lib/ui.sh"
# shellcheck source=setup/lib/estado.sh
source "$REPO/setup/lib/estado.sh"
# shellcheck source=setup/lib/agente.sh
source "$REPO/setup/lib/agente.sh"
# shellcheck source=setup/lib/menu.sh
source "$REPO/setup/lib/menu.sh"
AGENTE='{"id": "a1", "cliente_id": "c1", "nome": "Ana"}'
api() {
  printf '%s %s\n' "$1" "$2" >>"$TEMP_TESTE/chamadas"
  API_STATUS=200
  case "$2" in
    */base/teste)
      API_RESPOSTA='{"trechos": [{"posicao": 1, "documento": "catalogo.pdf", "secao": "Planos", "texto": "Anual R$ 997", "via": "palavra", "distancia": null, "entrou": true, "motivo": ""}]}'
      ;;
    */trechos*)
      API_RESPOSTA='{"total": 1, "trechos": [{"ordem": 1, "texto": "| Plano | Preço |", "secao": "Planos", "pagina_inicio": 2, "pagina_fim": 2, "tipo": "tabela"}]}'
      ;;
    *) API_RESPOSTA='[{"id": "d1", "nome": "catalogo.pdf", "status": "pronto", "total_trechos": 3, "erro": ""}]' ;;
  esac
}
exige_api() { :; }
pausa() { :; }

# Remover um material, o primeiro da lista, e voltar.
printf '%s\n' 8 1 9 >"$RESPOSTAS"
exec 3<"$RESPOSTAS"
edita_conhecimento >"$TEMP_TESTE/saida" 2>&1
grep -qxF 'DELETE /admin/clientes/c1/agentes/a1/documentos/d1' "$TEMP_TESTE/chamadas" ||
  { echo 'FALHOU: remover material não chamou a rota do documento'; cat "$TEMP_TESTE/chamadas"; exit 1; }
grep -q 'Remover qual?' "$TEMP_TESTE/saida" ||
  { echo 'FALHOU: a lista de materiais não apareceu na tela'; exit 1; }
echo 'ok: remover material da base chama a rota do documento escolhido'

# Ler de novo o primeiro material e voltar.
: >"$TEMP_TESTE/chamadas"
printf '%s\n' 6 1 9 >"$RESPOSTAS"
exec 3<"$RESPOSTAS"
edita_conhecimento >"$TEMP_TESTE/saida" 2>&1
grep -qxF 'POST /admin/clientes/c1/agentes/a1/documentos/d1/reprocessar' "$TEMP_TESTE/chamadas" ||
  { echo 'FALHOU: ler de novo não chamou a rota do documento'; cat "$TEMP_TESTE/chamadas"; exit 1; }
grep -q 'Ler de novo qual?' "$TEMP_TESTE/saida" ||
  { echo 'FALHOU: a pergunta de qual material ler de novo não apareceu'; exit 1; }
echo 'ok: ler de novo um material chama a rota do documento escolhido'

# Ler de novo tudo e voltar.
: >"$TEMP_TESTE/chamadas"
printf '%s\n' 7 9 >"$RESPOSTAS"
exec 3<"$RESPOSTAS"
edita_conhecimento >"$TEMP_TESTE/saida" 2>&1
grep -qxF 'POST /admin/clientes/c1/agentes/a1/documentos/reprocessar' "$TEMP_TESTE/chamadas" ||
  { echo 'FALHOU: ler de novo tudo não chamou a rota da base'; cat "$TEMP_TESTE/chamadas"; exit 1; }
echo 'ok: ler de novo tudo chama a rota da base inteira'

# Ver os trechos do primeiro material e voltar.
: >"$TEMP_TESTE/chamadas"
printf '%s\n' 5 1 9 >"$RESPOSTAS"
exec 3<"$RESPOSTAS"
edita_conhecimento >"$TEMP_TESTE/saida" 2>&1
grep -qxF 'GET /admin/clientes/c1/agentes/a1/documentos/d1/trechos?pagina=1' "$TEMP_TESTE/chamadas" ||
  { echo 'FALHOU: ver trechos não chamou a rota do documento'; cat "$TEMP_TESTE/chamadas"; exit 1; }
grep -q 'Planos  p. 2  tabela' "$TEMP_TESTE/saida" ||
  { echo 'FALHOU: o trecho não apareceu com seção, página e tipo'; cat "$TEMP_TESTE/saida"; exit 1; }
echo 'ok: ver trechos chama a rota do documento escolhido'

# Testar uma pergunta e voltar.
: >"$TEMP_TESTE/chamadas"
printf '%s\n' 4 'quanto custa o anual?' 9 >"$RESPOSTAS"
exec 3<"$RESPOSTAS"
edita_conhecimento >"$TEMP_TESTE/saida" 2>&1
grep -qxF 'POST /admin/clientes/c1/agentes/a1/base/teste' "$TEMP_TESTE/chamadas" ||
  { echo 'FALHOU: testar uma pergunta não chamou a rota do teste'; cat "$TEMP_TESTE/chamadas"; exit 1; }
grep -q 'entrou.*catalogo.pdf > Planos' "$TEMP_TESTE/saida" ||
  { echo 'FALHOU: o resultado do teste não apareceu'; cat "$TEMP_TESTE/saida"; exit 1; }
echo 'ok: testar uma pergunta mostra o que a busca acharia'
