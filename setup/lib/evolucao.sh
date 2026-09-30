#!/usr/bin/env bash
# `asimov agente`: comandos que o assistente de código (Claude Code ou Codex) usa para evoluir um
# agente a partir do pacote de análise (modelos/guias/evolucao-de-agente.md). Tudo pela API; a pasta
# privada do agente fica em agentes/<empresa_id>/<agente_id>/, com ids que não mudam ao renomear.
#
# Saída pensada para quem lê é uma IA: texto curto ou JSON, erro no stderr e código de saída 1.

DIR_AGENTES="$RAIZ_PROJETO/agentes"

ev_erro() {
  printf 'erro: %s\n' "$1" >&2
  exit 1
}

ev_api() {
  api "$@"
  if [ "$API_STATUS" = 000 ]; then
    ev_erro "a API não respondeu em $API_LOCAL. Veja: source deploy/compose.sh && dc logs api"
  fi
}

# ev_resolve REF: define EV_CLIENTE, EV_AGENTE, EV_NOME e EV_EMPRESA. REF é o id do agente ou
# empresa/agente pelos identificadores de `asimov agente listar`.
ev_resolve() {
  local ref=${1:-} clientes agentes achado
  [ -n "$ref" ] || ev_erro "diga qual agente: asimov agente listar mostra as referências"
  ev_api GET /admin/clientes
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  clientes=$API_RESPOSTA
  ev_api GET /admin/agentes
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  agentes=$API_RESPOSTA
  achado=$(jq -c --arg ref "$ref" --argjson clientes "$clientes" '
    ($clientes | map({(.id): .}) | add // {}) as $c
    | map(. + {empresa: $c[.cliente_id]})
    | map(select(.id == $ref or ((.empresa.slug // "") + "/" + .slug) == $ref))
  ' <<<"$agentes")
  case "$(jq 'length' <<<"$achado")" in
    1) ;;
    0) ev_erro "nenhum agente com a referência $ref. Veja: asimov agente listar" ;;
    *) ev_erro "mais de um agente com a referência $ref; use o id" ;;
  esac
  EV_CLIENTE=$(jq -r '.[0].cliente_id' <<<"$achado")
  EV_AGENTE=$(jq -r '.[0].id' <<<"$achado")
  EV_NOME=$(jq -r '.[0].nome' <<<"$achado")
  EV_EMPRESA=$(jq -r '.[0].empresa.nome // ""' <<<"$achado")
}

ev_caminho() { printf '/admin/clientes/%s/agentes/%s' "$EV_CLIENTE" "$EV_AGENTE"; }
ev_pasta() { printf '%s/%s/%s' "$DIR_AGENTES" "$EV_CLIENTE" "$EV_AGENTE"; }

# asimov agente listar: uma linha por agente, com a referência que os outros comandos aceitam.
ev_listar() {
  local clientes
  ev_api GET /admin/clientes
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  clientes=$API_RESPOSTA
  ev_api GET /admin/agentes
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  jq -r --argjson clientes "$clientes" '
    ($clientes | map({(.id): .}) | add // {}) as $c
    | if length == 0 then "nenhum agente; crie com: asimov novo-agente" else
      (.[] | "\(($c[.cliente_id].slug // "?"))/\(.slug)\t\(.nome) (\($c[.cliente_id].nome // "?"))\t\(.situacao)\t\(.canal)\t\(.id)")
      end
  ' <<<"$API_RESPOSTA"
}

ev_contexto() {
  ev_resolve "${1:-}"
  ev_api GET "$(ev_caminho)/contexto"
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  jq . <<<"$API_RESPOSTA"
}

# ev_leiame: o LEIAME.md da pasta, reescrito a cada preparar (nome e empresa podem ter mudado).
ev_leiame() {
  local pasta=$1
  cat >"$pasta/LEIAME.md" <<EOF
# $EV_NOME ($EV_EMPRESA)

Pasta privada de evolução deste agente. Nunca vai para repositório nem sai da VPS.
Atualizado por \`asimov agente preparar\` em $(date '+%Y-%m-%d %H:%M').

- Agente: $EV_AGENTE
- Empresa: $EV_CLIENTE
- Guia: modelos/guias/evolucao-de-agente.md
- Estado do trabalho: evolucao.md · decisões: decisoes.md
- Pacotes recebidos: recebido/ · prompt adaptado: prompt/ · ferramentas: ferramentas/ · testes: testes/
EOF
}

ev_preparar() {
  local pasta modelo
  ev_resolve "${1:-}"
  pasta=$(ev_pasta)
  mkdir -p "$DIR_AGENTES"
  chmod 700 "$DIR_AGENTES"
  mkdir -p "$pasta"/{recebido,prompt,ferramentas,testes}
  for modelo in evolucao decisoes; do
    [ -e "$pasta/$modelo.md" ] || cp "$RAIZ_PROJETO/modelos/agente/$modelo.md" "$pasta/$modelo.md"
  done
  ev_leiame "$pasta"
  printf '%s\n' "${pasta#"$RAIZ_PROJETO"/}"
}

# asimov agente receber REF ARQUIVO...: guarda o original e abre os ZIPs, inclusive os de dentro.
ev_receber() {
  local ref=${1:-} destino item
  shift || true
  [ "$#" -gt 0 ] || ev_erro "diga quais arquivos: asimov agente receber <ref> <arquivo ou pasta>..."
  for item in "$@"; do
    [ -e "$item" ] || ev_erro "não achei $item"
  done
  ev_preparar "$ref" >/dev/null
  destino="$(ev_pasta)/recebido/$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$destino/original" "$destino/aberto"
  for item in "$@"; do
    cp -R "$item" "$destino/original/"
  done
  cp -R "$destino/original/." "$destino/aberto/"
  # O zipfile do Python recusa caminho absoluto e `..` ao extrair. Repete enquanto houver ZIP novo:
  # o pacote da análise costuma vir dentro de outro.
  python3 - "$destino/aberto" <<'PY' || ev_erro "não consegui abrir um dos ZIPs"
import pathlib, sys, zipfile
raiz = pathlib.Path(sys.argv[1])
abertos = set()
while True:
    novos = [z for z in raiz.rglob("*.zip") if z not in abertos]
    if not novos:
        break
    for z in novos:
        abertos.add(z)
        alvo = z.with_suffix("")
        with zipfile.ZipFile(z) as arquivo:
            arquivo.extractall(alvo)
PY
  printf '%s\n' "${destino#"$RAIZ_PROJETO"/}"
  (cd "$destino/aberto" && find . -type f ! -name '*.zip' | sed 's#^\./#  #' | sort)
}

ev_prompt() {
  local sub=${1:-} ref=${2:-} arquivo motivo="" corpo
  case "$sub" in
    ver)
      ev_resolve "$ref"
      ev_api GET "$(ev_caminho)/prompt"
      [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
      jq -r '.texto' <<<"$API_RESPOSTA"
      ;;
    aplicar)
      arquivo=${3:-}
      [ -f "$arquivo" ] || ev_erro "diga o arquivo: asimov agente prompt aplicar <ref> <arquivo> --motivo \"...\""
      [ "${4:-}" != --motivo ] || motivo=${5:-}
      ev_resolve "$ref"
      corpo=$(jq -cn --rawfile texto "$arquivo" --arg motivo "$motivo" '{texto: $texto, motivo: $motivo}')
      ev_api PUT "$(ev_caminho)/prompt" "$corpo"
      [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
      if [ "$(jq -r '.mudou' <<<"$API_RESPOSTA")" = true ]; then
        printf 'prompt aplicado em %s (%s): versão %s. Vale na próxima mensagem.\n' "$EV_NOME" "$EV_EMPRESA" "$(jq -r '.versao' <<<"$API_RESPOSTA")"
      else
        printf 'o prompt de %s já era esse texto; nada mudou.\n' "$EV_NOME"
      fi
      ;;
    historico | histórico)
      ev_resolve "$ref"
      ev_api GET "$(ev_caminho)/prompt/versoes"
      [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
      jq -r 'if length == 0 then "sem histórico: o prompt nunca foi trocado pela plataforma" else
        (.[] | "\(.numero)\t\(.criado_em[0:16])\t\(.origem)\t\(.caracteres) caracteres\t\(.motivo)") end' <<<"$API_RESPOSTA"
      ;;
    versao | versão)
      ev_resolve "$ref"
      [[ "${3:-}" =~ ^[0-9]+$ ]] || ev_erro "diga o número: asimov agente prompt versao <ref> <n>"
      ev_api GET "$(ev_caminho)/prompt/versoes/$3"
      [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
      jq -r '.texto' <<<"$API_RESPOSTA"
      ;;
    restaurar)
      ev_resolve "$ref"
      [[ "${3:-}" =~ ^[0-9]+$ ]] || ev_erro "diga o número: asimov agente prompt restaurar <ref> <n>"
      ev_api POST "$(ev_caminho)/prompt/versoes/$3/restaurar"
      [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
      printf 'prompt de %s voltou ao texto da versão %s (agora versão %s).\n' "$EV_NOME" "$3" "$(jq -r '.versao' <<<"$API_RESPOSTA")"
      ;;
    *)
      ev_erro "use: asimov agente prompt ver|aplicar|historico|versao|restaurar <ref> ..."
      ;;
  esac
}

# asimov agente conversa REF "mensagem" [--conversa ID]: uma mensagem ao agente, pelo canal do
# terminal (vale para agente de qualquer canal, sem mandar nada ao contato real). Espera a resposta e
# mostra as ferramentas que o turno chamou.
ev_conversa() {
  local ref=${1:-} texto=${2:-} conversa="" corpo lidas=0 limite
  [ "${3:-}" != --conversa ] || conversa=${4:-}
  [ -n "$texto" ] || ev_erro "use: asimov agente conversa <ref> \"mensagem\" [--conversa <id>]"
  ev_resolve "$ref"
  corpo=$(jq -cn --arg t "$texto" --arg c "$conversa" '{texto: $t} + (if $c == "" then {} else {conversa: $c} end)')
  ev_api POST "$(ev_caminho)/terminal" "$corpo"
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  conversa=$(jq -r '.conversa' <<<"$API_RESPOSTA")
  if [ "$(jq -r '.agendada' <<<"$API_RESPOSTA")" != true ]; then
    ev_erro "a conversa $conversa está com humano; o agente não responde nela. Comece outra sem --conversa"
  fi
  limite=$((SECONDS + 180))
  while [ "$SECONDS" -lt "$limite" ]; do
    sleep 2
    ev_api GET "$(ev_caminho)/terminal/$conversa?depois=$lidas"
    [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
    jq -r '.mensagens[] | "agente: " + (.texto // .conteudo // "")' <<<"$API_RESPOSTA"
    lidas=$(jq -r '.proxima' <<<"$API_RESPOSTA")
    if [ "$(jq -r '.respondendo or .digitando' <<<"$API_RESPOSTA")" = false ]; then
      jq -r '"turno: " + (if .turno == null then "sem registro" else
        "\(.turno.modelo), \(.turno.latencia_ms) ms, ferramentas: \((.turno.ferramentas // []) | if length == 0 then "nenhuma" else join(", ") end)"
        + (if .turno.erro then ", erro: \(.turno.erro)" else "" end) end)
        + (if .handoff then "\nhandoff aberto: \(.handoff.motivo // "")" else "" end)' <<<"$API_RESPOSTA"
      printf 'conversa: %s (continue com --conversa %s)\n' "$conversa" "$conversa"
      return 0
    fi
  done
  ev_erro "o agente não respondeu em 3 minutos. Conversa $conversa; veja: asimov consumo"
}

ev_ajuda() {
  cat <<'EOF'
asimov agente: evoluir um agente a partir do pacote de análise (guia: modelos/guias/evolucao-de-agente.md)

  asimov agente listar                                   referências dos agentes (empresa/agente)
  asimov agente contexto <ref>                           configuração efetiva em JSON, sem credenciais
  asimov agente preparar <ref>                           cria a pasta privada do agente e mostra o caminho
  asimov agente receber <ref> <arquivo ou pasta>...      guarda o pacote e abre os ZIPs
  asimov agente prompt ver <ref>                         prompt aplicado agora
  asimov agente prompt aplicar <ref> <arquivo> --motivo "..."
  asimov agente prompt historico <ref>                   versões guardadas
  asimov agente prompt versao <ref> <n>                  texto de uma versão
  asimov agente prompt restaurar <ref> <n>               volta ao texto de uma versão
  asimov agente conversa <ref> "mensagem" [--conversa <id>]  conversa de teste; mostra as ferramentas chamadas

Ferramentas próprias: asimov ferramenta ajuda
EOF
}

# fluxo_agente SUBCOMANDO...: entrada do `asimov agente`.
fluxo_agente() {
  local sub=${1:-ajuda}
  shift || true
  case "$sub" in
    listar) ev_listar ;;
    contexto) ev_contexto "$@" ;;
    preparar) ev_preparar "$@" ;;
    receber) ev_receber "$@" ;;
    prompt) ev_prompt "$@" ;;
    conversa) ev_conversa "$@" ;;
    *) ev_ajuda ;;
  esac
}
