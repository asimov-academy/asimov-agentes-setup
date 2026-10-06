#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2034  # Comandos falsos chamados pelas funções importadas.
# `asimov agente` com a API de mentira: referência resolvida por empresa/agente, pasta privada com
# ids, pacote guardado e ZIP aninhado aberto, prompt aplicado pela rota com histórico.
#   bash setup/testes/simula_evolucao.sh
set -Eeuo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_TESTE=$(mktemp -d)
trap 'rm -rf "$TEMP_TESTE"' EXIT
RAIZ_PROJETO="$TEMP_TESTE/projeto"
LOG="$TEMP_TESTE/teste.log"
mkdir -p "$RAIZ_PROJETO/modelos" "$RAIZ_PROJETO/deploy"
cp -a "$REPO/modelos/." "$RAIZ_PROJETO/modelos/"
touch "$LOG"
ARQ_ENV="$TEMP_TESTE/env"
: >"$ARQ_ENV"
# shellcheck source=setup/lib/ui.sh
source "$REPO/setup/lib/ui.sh"
# shellcheck source=setup/lib/estado.sh
source "$REPO/setup/lib/estado.sh"
# shellcheck source=setup/lib/agente.sh
source "$REPO/setup/lib/agente.sh"
# shellcheck source=setup/lib/evolucao.sh
source "$REPO/setup/lib/evolucao.sh"
# shellcheck source=setup/lib/final.sh
source "$REPO/setup/lib/final.sh"
PASTA_FERRAMENTAS="$TEMP_TESTE/ferramentas"
PASTA_ENVIOS="$TEMP_TESTE/envios"
PASTA_SOCKETS="$TEMP_TESTE/sock"
PASTA_TESTES_FERRAMENTAS="$TEMP_TESTE/ferramentas-teste"
# shellcheck source=setup/lib/ferramentas.sh
source "$REPO/setup/lib/ferramentas.sh"
SUDO=""
ARQ_ENV="$TEMP_TESTE/env"
printf 'ASIMOV_VERSAO=v0.37.0\n' >"$ARQ_ENV"

CLIENTES='[{"id":"c1","nome":"Loja Exemplo","slug":"loja-exemplo"},{"id":"c2","nome":"Clínica Exemplo","slug":"clinica-exemplo"}]'
AGENTES='[{"id":"a1","cliente_id":"c1","nome":"Ana","slug":"ana","canal":"nativo","situacao":"treinamento"},
{"id":"a2","cliente_id":"c2","nome":"Ana","slug":"ana","canal":"waha","situacao":"ativo"}]'
api() {
  printf '%s %s %s\n' "$1" "$2" "${3:-}" >>"$TEMP_TESTE/chamadas"
  API_STATUS=200
  case "$1 $2" in
    "GET /admin/clientes") API_RESPOSTA=$CLIENTES ;;
    "GET /admin/agentes") API_RESPOSTA=$AGENTES ;;
    "GET /admin/clientes/c1/agentes/a1/contexto") API_RESPOSTA='{"agente":{"id":"a1","nome":"Ana"},"pasta_de_evolucao":"agentes/c1/a1"}' ;;
    "PUT /admin/clientes/c1/agentes/a1/prompt") API_RESPOSTA='{"versao":2,"mudou":true}' ;;
    "GET /admin/clientes/c1/agentes/a1/prompt/versoes") API_RESPOSTA='[{"numero":2,"criado_em":"2026-09-30T20:00:00","origem":"terminal","caracteres":24,"motivo":"pacote"}]' ;;
    "POST /admin/clientes/c1/agentes/a1/prompt/versoes/1/restaurar") API_RESPOSTA='{"versao":3,"mudou":true}' ;;
    "POST /admin/clientes/c1/agentes/a1/prompt/versoes/9/restaurar") API_STATUS=404; API_RESPOSTA='{"detail":"o agente não tem a versão 9 do prompt"}' ;;
    "POST /admin/ferramentas-proprias/contrato") API_RESPOSTA=$(jq -c '{contrato: .contrato}' <<<"$3") ;;
    "GET /admin/clientes/c1/agentes/a1/ferramentas-proprias") API_RESPOSTA=${FERRAMENTAS_ATIVAS:-[]} ;;
    "POST /admin/clientes/c1/agentes/a1/ferramentas-proprias/consultar_agenda/versoes") API_STATUS=201; API_RESPOSTA='{"nome":"consultar_agenda","versao":1}' ;;
    "POST /admin/clientes/c1/agentes/a1/envios") API_RESPOSTA='{"url":"https://bot.exemplo.com.br/envio/abc","validade_minutos":30}' ;;
    "GET /admin/ferramentas-proprias/empresas") API_RESPOSTA='["11111111-2222-3333-4444-555555555555"]' ;;
    *) API_STATUS=404; API_RESPOSTA='{"detail":"rota falsa"}' ;;
  esac
}
falhou() { echo "FALHOU: $1"; exit 1; }

fluxo_agente listar >"$TEMP_TESTE/saida"
grep -q '^loja-exemplo/ana' "$TEMP_TESTE/saida" || falhou 'listar não mostrou a referência da loja'
grep -q '^clinica-exemplo/ana' "$TEMP_TESTE/saida" || falhou 'listar não mostrou a referência da clínica'
echo 'ok: listar mostra a referência de cada agente'

# Mesmo nome em duas empresas: a referência decide, nunca o palpite.
if (fluxo_agente contexto ana) 2>"$TEMP_TESTE/erro"; then falhou 'referência ambígua passou'; fi
grep -q 'nenhum agente' "$TEMP_TESTE/erro" || falhou 'erro de referência sem motivo'
fluxo_agente contexto loja-exemplo/ana | jq -e --arg p "$RAIZ_PROJETO/agentes/c1/a1" '.agente.id == "a1" and .pasta_de_evolucao == $p' >/dev/null ||
  falhou 'contexto do agente errado ou com a pasta relativa'
echo 'ok: nome repetido em outra empresa não confunde a referência'

pasta=$(fluxo_agente preparar loja-exemplo/ana)
[ "$pasta" = "$RAIZ_PROJETO/agentes/c1/a1" ] || falhou "pasta com caminho inesperado: $pasta"
for item in evolucao.md decisoes.md LEIAME.md recebido ferramentas testes prompt; do
  [ -e "$pasta/$item" ] || falhou "preparar não criou $item"
done
[ "$(stat -c %a "$RAIZ_PROJETO/agentes" 2>/dev/null || stat -f %Lp "$RAIZ_PROJETO/agentes")" = 700 ] ||
  falhou 'pasta agentes/ não é privada'
printf 'Fase atual: 2\n' >"$pasta/evolucao.md"
fluxo_agente preparar a1 >/dev/null
[ "$(cat "$pasta/evolucao.md")" = 'Fase atual: 2' ] || falhou 'preparar de novo apagou o estado do trabalho'
echo 'ok: preparar cria a pasta privada por ids e preserva o estado ao repetir'

# Pacote como a skill entrega: um HTML solto e um ZIP com os documentos dentro de outro ZIP.
mkdir -p "$TEMP_TESTE/pacote/interno"
printf '# System prompt\n' >"$TEMP_TESTE/pacote/interno/system-prompt.md"
printf 'versao_schema: 2.0\n' >"$TEMP_TESTE/pacote/interno/especificacao-agente.yaml"
(cd "$TEMP_TESTE/pacote/interno" && python3 -m zipfile -c ../entrega-agente.zip system-prompt.md especificacao-agente.yaml)
printf '<html></html>\n' >"$TEMP_TESTE/pacote/mapa-atendimento.html"
(cd "$TEMP_TESTE/pacote" && python3 -m zipfile -c files.zip mapa-atendimento.html entrega-agente.zip)
fluxo_agente receber loja-exemplo/ana "$TEMP_TESTE/pacote/files.zip" >"$TEMP_TESTE/saida"
recebido=$(head -1 "$TEMP_TESTE/saida")
[ -f "$recebido/original/files.zip" ] || falhou 'o original não foi guardado'
[ -f "$recebido/aberto/files/entrega-agente/system-prompt.md" ] || falhou 'ZIP aninhado não foi aberto'
grep -q 'especificacao-agente.yaml' "$TEMP_TESTE/saida" || falhou 'receber não listou os documentos'
echo 'ok: receber guarda o original e abre o ZIP dentro do ZIP'

# Pelo link de envio: o aluno manda pelo navegador, e o receber sem arquivo pega o que chegou.
fluxo_agente envio loja-exemplo/ana >"$TEMP_TESTE/saida"
grep -q 'https://bot.exemplo.com.br/envio/abc' "$TEMP_TESTE/saida" || falhou 'envio não mostrou o link'
if (fluxo_agente receber loja-exemplo/ana) 2>"$TEMP_TESTE/erro" >/dev/null; then falhou 'receber sem nada passou'; fi
grep -q 'asimov agente envio' "$TEMP_TESTE/erro" || falhou 'receber vazio não diz como gerar o link'
mkdir -p "$PASTA_ENVIOS/c1/a1/20260930-1200-abc" "$PASTA_ENVIOS/c1/a1/20260930-1201-def.parcial"
cp "$TEMP_TESTE/pacote/files.zip" "$PASTA_ENVIOS/c1/a1/20260930-1200-abc/"
printf 'pela metade' >"$PASTA_ENVIOS/c1/a1/20260930-1201-def.parcial/files.zip"
sleep 1
fluxo_agente receber loja-exemplo/ana >"$TEMP_TESTE/saida"
recebido=$(head -1 "$TEMP_TESTE/saida")
[ -f "$recebido/aberto/files/entrega-agente/system-prompt.md" ] || falhou 'o que veio pelo link não foi aberto'
[ ! -e "$PASTA_ENVIOS/c1/a1/20260930-1200-abc" ] || falhou 'envio recebido ficou na pasta de chegada'
[ -e "$PASTA_ENVIOS/c1/a1/20260930-1201-def.parcial" ] || falhou 'envio pela metade foi mexido'
echo 'ok: link de envio mostrado e o que chegou por ele vai para a pasta do agente'

printf 'Você é a Ana, do pacote.\n' >"$TEMP_TESTE/persona.md"
fluxo_agente prompt aplicar loja-exemplo/ana "$TEMP_TESTE/persona.md" --motivo pacote >"$TEMP_TESTE/saida"
grep -q 'versão 2' "$TEMP_TESTE/saida" || falhou 'aplicar não mostrou a versão'
grep -F 'PUT /admin/clientes/c1/agentes/a1/prompt' "$TEMP_TESTE/chamadas" | grep -q '"motivo":"pacote"' ||
  falhou 'aplicar não mandou texto e motivo pela rota do agente certo'
fluxo_agente prompt historico a1 | grep -q $'^2\t' || falhou 'histórico sem a versão'
fluxo_agente prompt restaurar a1 1 | grep -q 'versão 3' || falhou 'restaurar não mostrou a versão nova'
if (fluxo_agente prompt restaurar a1 9) 2>"$TEMP_TESTE/erro"; then falhou 'restaurar versão inexistente passou'; fi
grep -q 'versão 9' "$TEMP_TESTE/erro" || falhou 'erro da API não chegou ao CLI'
echo 'ok: prompt aplicado, listado e restaurado pela API, com erro legível'

# AGENTS.md do operador ganha só a seção de entrada, uma vez, e a área do assistente é montada.
printf 'Contexto do operador\n' >"$RAIZ_PROJETO/AGENTS.md"
garante_contexto_de_evolucao
garante_contexto_de_evolucao
garante_area_do_assistente
[ "$(head -1 "$RAIZ_PROJETO/AGENTS.md")" = 'Contexto do operador' ] || falhou 'texto do operador mudou'
[ "$(grep -c 'cd agentes' "$RAIZ_PROJETO/AGENTS.md")" = 1 ] || falhou 'seção repetida ou ausente'
grep -q '../modelos/guias/evolucao-de-agente.md' "$RAIZ_PROJETO/agentes/AGENTS.md" || falhou 'área sem o guia'
contexto_de_evolucao_ok || falhou 'diagnóstico não reconhece a seção'
: >"$RAIZ_PROJETO/AGENTS.md"
if contexto_de_evolucao_ok; then falhou 'AGENTS.md vazio passou no diagnóstico'; fi
[ -f "$REPO/modelos/guias/evolucao-de-agente.md" ] || falhou 'guia ausente'
echo 'ok: AGENTS.md existente ganha a entrada sem perder o texto do operador'

# Ferramenta própria: Docker falso. Conversão do YAML, pip e pytest viram respostas fixas; o que
# importa aqui é a ordem, onde a versão fica e o que vai para a API.
CONTRATO_JSON='{"nome":"consultar_agenda","descricao":"Consulta horários livres.","quando_usar":"Antes de oferecer horário.","entrada":{"type":"object","properties":{"turno":{"type":"string"}}},"efeito":"leitura"}'
TESTES_PASSAM=1
docker() {
  printf 'docker %s\n' "$*" >>"$TEMP_TESTE/docker"
  case "$*" in
    *"yaml.safe_load"*) cat >/dev/null; printf '%s\n' "$CONTRATO_JSON" ;;
    *"pip install"*) mkdir -p "$(sed -n 's/.*-v \([^:]*\):.*/\1/p' <<<"$*")/venv" ;;
    *"pytest"*) if [ "$TESTES_PASSAM" = 1 ]; then echo '2 passed'; else echo '1 failed'; return 1; fi ;;
    "ps -a"*) printf 'asimov-ferramentas-99999999-0000-0000-0000-000000000000\n' ;;
    *"UID_DO_CODIGO"*) printf '%s\n' "${EXECUTOR_TROCA_UID:-True}" ;;
    "rm -f"*) ;;
  esac
}
dc() { printf 'dc %s\n' "$*" >>"$TEMP_TESTE/docker"; }
# Na VPS é root: aqui o dono não muda, e trava de escrita impediria a limpeza da pasta temporária.
chown() { :; }
chmod() { [ "$1" != -R ] || return 0; command chmod "$@"; }
dev="$RAIZ_PROJETO/agentes/c1/a1/ferramentas/consultar_agenda"
mkdir -p "$dev/testes"
printf 'def executa(entrada, contexto, segredos):\n    return {"horarios": []}\n' >"$dev/ferramenta.py"
printf 'nome: consultar_agenda\n' >"$dev/contrato.yaml"
printf 'def test_ok():\n    assert True\n' >"$dev/testes/test_ok.py"

TESTES_PASSAM=0
if (fluxo_ferramenta ativar loja-exemplo/ana consultar_agenda) >"$TEMP_TESTE/saida" 2>&1; then falhou 'ativou com teste falhando'; fi
[ ! -d "$PASTA_FERRAMENTAS/c1/a1/consultar_agenda/v1" ] || falhou 'versão reprovada ficou no disco'
grep -q 'ferramentas-proprias/consultar_agenda/versoes' "$TEMP_TESTE/chamadas" && falhou 'versão reprovada foi registrada'
TESTES_PASSAM=1
fluxo_ferramenta ativar loja-exemplo/ana consultar_agenda >"$TEMP_TESTE/saida" 2>&1 || { cat "$TEMP_TESTE/saida"; falhou 'ativar falhou'; }
[ -f "$PASTA_FERRAMENTAS/c1/a1/consultar_agenda/v1/ferramenta.py" ] || falhou 'código não foi para a versão imutável'
grep -F 'ferramentas-proprias/consultar_agenda/versoes' "$TEMP_TESTE/chamadas" | grep -q '"numero":1' || falhou 'versão não registrada na API'
grep -q -- '--network none' "$TEMP_TESTE/docker" || falhou 'testes rodaram com rede'
grep -q 'rm -f asimov-ferramentas-99999999' "$TEMP_TESTE/docker" || falhou 'contêiner de empresa sem ferramenta ficou no ar'
echo 'ok: ativar só registra versão com testes aprovados, e sem rede'

compose="$RAIZ_PROJETO/deploy/ferramentas.compose.yml"
for trecho in 'network_mode: none' 'read_only: true' 'cap_drop: [ALL]' 'no-new-privileges' 'mem_limit: 512m' \
  'cap_add: [CHOWN, DAC_OVERRIDE, SETUID, SETGID, KILL]' 'FERRAMENTAS_UID_DO_CODIGO: "1001"' 'user: "0:1000"' \
  "$PASTA_FERRAMENTAS/11111111-2222-3333-4444-555555555555:/ferramentas:ro" "$PASTA_SOCKETS/11111111-2222-3333-4444-555555555555:/sock"; do
  grep -qF -- "$trecho" "$compose" || falhou "contêiner da empresa sem: $trecho"
done
grep -q 'env_file' "$compose" && falhou 'contêiner da empresa recebe o .env'
echo 'ok: contêiner da empresa sem rede, sem .env, só leitura e com teto'

# Ação que muda sistema de fora: sem terminal (o assistente de código), não ativa.
CONTRATO_JSON='{"nome":"consultar_agenda","descricao":"Reserva.","quando_usar":"Depois do aceite.","entrada":{"type":"object","properties":{"slot":{"type":"string"}}},"efeito":"altera","idempotencia":["slot"]}'
if (fluxo_ferramenta ativar loja-exemplo/ana consultar_agenda </dev/null) 2>"$TEMP_TESTE/erro" >/dev/null; then
  if { : </dev/tty; } 2>/dev/null; then echo 'aviso: há terminal aqui; confirmação não testada'; else falhou 'ação ativada sem o operador'; fi
fi
if ! { : </dev/tty; } 2>/dev/null; then
  grep -q 'confirmação do operador' "$TEMP_TESTE/erro" || falhou 'recusa sem dizer que o operador precisa rodar'
  if (fluxo_ferramenta segredo loja-exemplo/ana AGENDA_TOKEN) 2>"$TEMP_TESTE/erro"; then falhou 'segredo aceito sem o operador digitar'; fi
  grep -q 'digitado pelo operador' "$TEMP_TESTE/erro" || falhou 'segredo recusado sem motivo'
  echo 'ok: ação e segredo exigem o operador no terminal'
fi

# Ligar ou restaurar ferramenta que altera também exige o operador: sem terminal, recusa.
FERRAMENTAS_ATIVAS='[{"nome":"consultar_agenda","contrato":{"efeito":"altera"},"versoes":[{"numero":1}]}]'
if ! { : </dev/tty; } 2>/dev/null; then
  if (fluxo_ferramenta ligar loja-exemplo/ana consultar_agenda) 2>"$TEMP_TESTE/erro" >/dev/null; then falhou 'ligou ação sem o operador'; fi
  grep -q 'confirmação do operador' "$TEMP_TESTE/erro" || falhou 'ligar recusou sem motivo'
  if (fluxo_ferramenta restaurar loja-exemplo/ana consultar_agenda 1) 2>/dev/null >/dev/null; then falhou 'restaurou ação sem o operador'; fi
  grep -q 'ferramentas-proprias/consultar_agenda/ligada' "$TEMP_TESTE/chamadas" && falhou 'ligar chamou a API sem confirmação'
  echo 'ok: ligar e restaurar ação exigem o operador'
fi

# ZIP que se expande demais ou se aninha sem fim não enche o disco.
python3 - "$TEMP_TESTE/bomba.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("grande.bin", b"\0" * (520 * 1024 * 1024))
PY
if (fluxo_agente receber loja-exemplo/ana "$TEMP_TESTE/bomba.zip") 2>"$TEMP_TESTE/erro" >/dev/null; then falhou 'bomba de ZIP aberta'; fi
grep -q '500 MB' "$TEMP_TESTE/erro" || falhou 'bomba recusada sem motivo'
[ -z "$(find "$RAIZ_PROJETO/agentes" -name grande.bin)" ] || falhou 'bomba deixou o arquivo expandido'
mkdir -p "$TEMP_TESTE/fundo" && printf x >"$TEMP_TESTE/fundo/a.txt"
(cd "$TEMP_TESTE/fundo" && anterior=a.txt && for n in 1 2 3 4 5; do python3 -m zipfile -c "z$n.zip" "$anterior"; anterior="z$n.zip"; done)
if (fluxo_agente receber loja-exemplo/ana "$TEMP_TESTE/fundo/z5.zip") 2>"$TEMP_TESTE/erro" >/dev/null; then falhou 'ZIP aninhado sem fim aberto'; fi
grep -q 'níveis' "$TEMP_TESTE/erro" || falhou 'aninhamento recusado sem motivo'
echo 'ok: receber recusa ZIP que expande demais ou se aninha sem fim'

# receber com arquivo roda sem aprovação: só o pacote entra, nunca o .env ou credencial.
printf 'CHAVE_API_ADMIN=segredo\n' >"$RAIZ_PROJETO/.env"
mkdir -p "$TEMP_TESTE/casa/.claude" && printf '{}' >"$TEMP_TESTE/casa/.claude/.credentials.json"
cp "$TEMP_TESTE/pacote/files.zip" "$RAIZ_PROJETO/deploy/copia.zip"
for proibido in "$RAIZ_PROJETO/.env" "$TEMP_TESTE/casa/.claude/.credentials.json" "$RAIZ_PROJETO/deploy/copia.zip" "$TEMP_TESTE/pacote"; do
  if (HOME="$TEMP_TESTE/casa" fluxo_agente receber loja-exemplo/ana "$proibido") 2>/dev/null >/dev/null; then
    falhou "receber aceitou $proibido"
  fi
done
if grep -rq 'CHAVE_API_ADMIN' "$RAIZ_PROJETO/agentes"; then falhou 'o .env foi parar na área do assistente'; fi
echo 'ok: receber com arquivo aceita só o pacote, nunca .env, credencial ou pasta da instalação'

# Restaurar vale pelo efeito da versão de destino, não da ativa.
FERRAMENTAS_ATIVAS='[{"nome":"consultar_agenda","contrato":{"efeito":"leitura"},"versoes":[{"numero":1,"efeito":"altera"},{"numero":2,"efeito":"leitura"}]}]'
if ! { : </dev/tty; } 2>/dev/null; then
  if (fluxo_ferramenta restaurar loja-exemplo/ana consultar_agenda 1) 2>/dev/null >/dev/null; then
    falhou 'restaurou a versão que altera porque a ativa só lê'
  fi
  echo 'ok: restaurar confere o efeito da versão de destino'
fi

# Testes da ferramenta rodam com o uid do atendimento.
grep 'pytest' "$TEMP_TESTE/docker" | grep -q -- '--user 1001:1001' || falhou 'testes da ferramenta não rodam com o uid do atendimento'
echo 'ok: testes da ferramenta com o uid 1001'

# Imagem antiga (volta de versão): o contêiner da empresa não ganha root nem capacidade.
EXECUTOR_TROCA_UID=False ferramentas_gera_compose 11111111-2222-3333-4444-555555555555
grep -q 'user: "1000:1000"' "$compose" || falhou 'imagem antiga ganhou outro usuário'
if grep -q 'cap_add\|FERRAMENTAS_UID_DO_CODIGO' "$compose"; then falhou 'imagem antiga ganhou capacidades'; fi
echo 'ok: executor antigo continua com o uid 1000 e sem capacidade'
