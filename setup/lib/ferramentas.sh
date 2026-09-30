#!/usr/bin/env bash
# `asimov ferramenta`: construir, testar e ativar as ferramentas próprias de um agente (fase 12).
#
# O código nasce em agentes/<empresa>/<agente>/ferramentas/<nome>/ (ferramenta.py, contrato.yaml,
# requirements.txt, testes/). Ativar copia para uma versão imutável em
# /var/lib/asimov/ferramentas/<empresa>/<agente>/<nome>/v<n>/, monta o venv dela, roda os testes sem
# rede e registra o contrato na API. O atendimento chama o contêiner da empresa
# (`asimov-ferramentas-<empresa>`), que não tem rede e sai para a internet só pelo serviço `saida`.
#
# Só o host mexe no Docker: a API e o worker nunca. Quem roda aqui é o operador ou o assistente dele.

PASTA_FERRAMENTAS="${PASTA_FERRAMENTAS:-/var/lib/asimov/ferramentas}"
PASTA_SOCKETS="${PASTA_SOCKETS:-/var/lib/asimov/ferramentas-sock}"
PASTA_TESTES_FERRAMENTAS="${PASTA_TESTES_FERRAMENTAS:-/var/lib/asimov/ferramentas-teste}"
ARQ_FERRAMENTAS_COMPOSE="$RAIZ_PROJETO/deploy/ferramentas.compose.yml"
# Teto do contêiner de cada empresa: cobre umas 8 chamadas juntas, que é a rajada de 3 agentes com
# mil conversas por dia cada (spec/decisoes.md, 2026-09-30). Ajustável no .env.
FERRAMENTAS_MEMORIA_PADRAO=512m
FERRAMENTAS_CPUS_PADRAO=1.0

imagem_backend() {
  local registro versao
  registro=$(env_get ASIMOV_REGISTRO)
  versao=$(env_get ASIMOV_VERSAO)
  printf '%s/agentes-backend:%s' "${registro:-ghcr.io/asimov-academy}" "$versao"
}

# prepara_ferramentas: pastas no host com o dono dos contêineres (uid 1000) e os IPs da própria VPS,
# que o proxy de saída recusa (são públicos e levariam ao SSH e às outras aplicações da VPS).
prepara_ferramentas() {
  local ips publico
  $SUDO mkdir -p "$PASTA_FERRAMENTAS" "$PASTA_SOCKETS" "$PASTA_TESTES_FERRAMENTAS" "$PASTA_ENVIOS"
  $SUDO chown 1000:1000 "$PASTA_FERRAMENTAS" "$PASTA_SOCKETS" "$PASTA_TESTES_FERRAMENTAS" "$PASTA_ENVIOS"
  $SUDO chmod 750 "$PASTA_FERRAMENTAS" "$PASTA_SOCKETS" "$PASTA_TESTES_FERRAMENTAS" "$PASTA_ENVIOS"
  publico=$(ip_publico)
  ips=$({ hostname -I 2>/dev/null || true; } | tr ' ' '\n' | grep -v '^$' || true)
  ips=$(printf '%s\n%s\n' "$publico" "$ips" | grep -v '^$' | sort -u | paste -sd, - || true)
  [ -z "$ips" ] || env_set ASIMOV_IPS_DO_HOST "$ips"
}

# ferramentas_gera_compose EMPRESA...: um serviço por empresa com ferramenta ligada.
ferramentas_gera_compose() {
  local empresa memoria cpus imagem
  memoria=$(env_get FERRAMENTAS_MEMORIA)
  cpus=$(env_get FERRAMENTAS_CPUS)
  # Literal de propósito: o Compose resolve pelo .env, igual aos outros serviços.
  # shellcheck disable=SC2016
  imagem='${ASIMOV_REGISTRO:-ghcr.io/asimov-academy}/agentes-backend:${ASIMOV_VERSAO:?rode o setup: falta ASIMOV_VERSAO no .env}'
  if [ "$#" -eq 0 ]; then
    rm -f "$ARQ_FERRAMENTAS_COMPOSE"
    return 0
  fi
  {
    echo "# Gerado por asimov ferramenta: não edite. Um contêiner por empresa com ferramenta ligada."
    echo "services:"
    for empresa in "$@"; do
      cat <<EOF
  ferramentas-$empresa:
    image: "$imagem"
    container_name: asimov-ferramentas-$empresa
    command: ["uvicorn", "app.ferramentas_proprias.executor:app", "--uds", "/sock/executor.sock", "--no-access-log"]
    network_mode: none
    user: "1000:1000"
    read_only: true
    tmpfs: ["/tmp:size=256m"]
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    pids_limit: 256
    mem_limit: ${memoria:-$FERRAMENTAS_MEMORIA_PADRAO}
    cpus: ${cpus:-$FERRAMENTAS_CPUS_PADRAO}
    environment:
      FERRAMENTAS_RAIZ: /ferramentas
      FERRAMENTAS_SOCK: /sock
    volumes:
      - $PASTA_FERRAMENTAS/$empresa:/ferramentas:ro
      - $PASTA_SOCKETS/$empresa:/sock
    logging:
      driver: local
      options: {max-size: "10m", max-file: "3"}
    restart: unless-stopped
EOF
    done
  } >"$ARQ_FERRAMENTAS_COMPOSE.tmp" || return 1
  mv "$ARQ_FERRAMENTAS_COMPOSE.tmp" "$ARQ_FERRAMENTAS_COMPOSE" || return 1
}

# ferramentas_sobe: um contêiner para cada empresa com ferramenta ligada, e só para elas.
ferramentas_sobe() {
  local empresa nome
  local -a empresas=() servicos=()
  api GET /admin/ferramentas-proprias/empresas
  [ "$API_STATUS" = 200 ] || return 1
  while IFS= read -r empresa; do
    [[ "$empresa" =~ ^[0-9a-f-]{36}$ ]] || continue
    empresas+=("$empresa")
    servicos+=("ferramentas-$empresa")
    $SUDO mkdir -p "$PASTA_FERRAMENTAS/$empresa" "$PASTA_SOCKETS/$empresa"
    $SUDO chown 1000:1000 "$PASTA_FERRAMENTAS/$empresa" "$PASTA_SOCKETS/$empresa"
    $SUDO chmod 750 "$PASTA_FERRAMENTAS/$empresa" "$PASTA_SOCKETS/$empresa"
  done < <(jq -r '.[]' <<<"$API_RESPOSTA")
  ferramentas_gera_compose "${empresas[@]}" || return 1
  # Empresa que ficou sem ferramenta ligada perde o contêiner.
  while IFS= read -r nome; do
    [ -n "$nome" ] || continue
    empresa=${nome#asimov-ferramentas-}
    printf '%s\n' "${empresas[@]}" | grep -qxF "$empresa" || $SUDO docker rm -f "$nome" >/dev/null 2>&1 || true
  done < <($SUDO docker ps -a --filter 'name=^asimov-ferramentas-' --format '{{.Names}}' 2>/dev/null || true)
  [ "${#servicos[@]}" -eq 0 ] || dc up -d saida "${servicos[@]}"
}

# ev_ferramenta_dev REF NOME: define FE_DEV (pasta de desenvolvimento) e confere o que precisa ter.
ev_ferramenta_dev() {
  local nome=${2:-}
  ev_resolve "${1:-}"
  [[ "$nome" =~ ^[a-z][a-z0-9_]{2,47}$ ]] || ev_erro "nome da ferramenta em minúsculas com _, como consultar_agenda"
  FE_NOME=$nome
  FE_DEV="$(ev_pasta)/ferramentas/$nome"
  [ -f "$FE_DEV/ferramenta.py" ] || ev_erro "falta ${FE_DEV#"$RAIZ_PROJETO"/}/ferramenta.py (função executa(entrada, contexto, segredos))"
  [ -f "$FE_DEV/contrato.yaml" ] || ev_erro "falta ${FE_DEV#"$RAIZ_PROJETO"/}/contrato.yaml"
  [ -d "$FE_DEV/testes" ] || ev_erro "falta ${FE_DEV#"$RAIZ_PROJETO"/}/testes/ com pelo menos um test_*.py"
}

# ev_ferramenta_contrato: contrato.yaml em JSON, conferido pela API. Define FE_CONTRATO.
ev_ferramenta_contrato() {
  local json
  json=$($SUDO docker run --rm -i --network none "$(imagem_backend)" \
    python -c 'import json, sys, yaml; print(json.dumps(yaml.safe_load(sys.stdin)))' <"$FE_DEV/contrato.yaml" 2>&1) ||
    ev_erro "contrato.yaml não é YAML válido: ${json:0:300}"
  ev_api POST /admin/ferramentas-proprias/contrato "$(jq -c '{contrato: .}' <<<"$json")"
  [ "$API_STATUS" = 200 ] || ev_erro "contrato recusado: $(detalhe_erro "$API_RESPOSTA")"
  FE_CONTRATO=$(jq -c '.contrato' <<<"$API_RESPOSTA")
  [ "$(jq -r '.nome' <<<"$FE_CONTRATO")" = "$FE_NOME" ] ||
    ev_erro "o contrato diz $(jq -r '.nome' <<<"$FE_CONTRATO"), mas a pasta é $FE_NOME"
}

# ev_ferramenta_constroi PASTA_NO_HOST CAMINHO_NO_CONTEINER: copia o código, monta o venv (a única
# etapa com internet, para o pip) e roda os testes sem rede. Mesmo caminho dentro e fora: o venv
# guarda caminhos absolutos.
ev_ferramenta_constroi() {
  local destino=$1 caminho=$2 imagem
  imagem=$(imagem_backend)
  $SUDO rm -rf "$destino"
  $SUDO mkdir -p "$destino"
  (cd "$FE_DEV" && tar --exclude=venv --exclude=__pycache__ --exclude='*.pyc' -cf - .) | $SUDO tar -xf - -C "$destino"
  [ -f "$destino/requirements.txt" ] || $SUDO touch "$destino/requirements.txt"
  $SUDO chown -R 1000:1000 "$destino"
  printf 'instalando dependências...\n'
  $SUDO docker run --rm --user 1000:1000 -v "$destino:$caminho" "$imagem" \
    sh -c "python -m venv $caminho/venv && $caminho/venv/bin/pip install -q --disable-pip-version-check --no-cache-dir -r $caminho/requirements.txt pytest" ||
    return 1
  printf 'rodando os testes sem rede...\n'
  FE_TESTES=$($SUDO docker run --rm --network none --read-only --tmpfs /tmp --user 1000:1000 \
    -e PYTHONDONTWRITEBYTECODE=1 -v "$destino:$caminho:ro" -w "$caminho" "$imagem" \
    "$caminho/venv/bin/python" -m pytest -q -p no:cacheprovider testes 2>&1)
  local status=$?
  printf '%s\n' "$FE_TESTES"
  FE_TESTES=$(tail -n 3 <<<"$FE_TESTES")
  return "$status"
}

ev_ferramenta_hash() {
  (cd "$1" && find . -type f ! -path './venv/*' ! -name '*.pyc' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
}

# ev_confirma_operador "pergunta" PALAVRA: só com terminal. O assistente de código não tem terminal
# aqui, e é isso que garante que ação que muda sistema de fora passa pelo operador.
ev_confirma_operador() {
  local resposta
  if ! { : </dev/tty; } 2>/dev/null; then
    ev_erro "isto precisa da confirmação do operador. Peça para ele rodar no terminal: $3"
  fi
  printf '%s\nDigite %s para confirmar: ' "$1" "$2" >/dev/tty
  IFS= read -r resposta </dev/tty || true
  [ "$resposta" = "$2" ] || ev_erro "não confirmado; nada mudou"
}

ev_ferramenta_testar() {
  ev_ferramenta_dev "$@"
  ev_ferramenta_contrato
  local destino="$PASTA_TESTES_FERRAMENTAS/$EV_AGENTE/$FE_NOME"
  if ev_ferramenta_constroi "$destino" "/teste/$FE_NOME"; then
    printf 'testes aprovados: %s. Contrato válido. Para usar no atendimento: asimov ferramenta ativar %s %s\n' \
      "$FE_NOME" "$1" "$FE_NOME"
  else
    ev_erro "testes de $FE_NOME falharam; corrija antes de ativar"
  fi
}

ev_ferramenta_ativar() {
  local ref=${1:-} numero destino caminho corpo efeito
  ev_ferramenta_dev "$@"
  ev_ferramenta_contrato
  efeito=$(jq -r '.efeito' <<<"$FE_CONTRATO")
  if [ "$efeito" = altera ]; then
    ev_confirma_operador "$FE_NOME muda um sistema de fora (reserva, cobrança, envio) quando o agente $EV_NOME ($EV_EMPRESA) conversar com contatos reais." \
      ATIVAR "asimov ferramenta ativar $ref $FE_NOME"
  fi
  ev_api GET "$(ev_caminho)/ferramentas-proprias"
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  numero=$(jq --arg n "$FE_NOME" '[.[] | select(.nome == $n) | .versoes[].numero] | max // 0 | . + 1' <<<"$API_RESPOSTA")
  caminho="/ferramentas/$EV_AGENTE/$FE_NOME/v$numero"
  destino="$PASTA_FERRAMENTAS/$EV_CLIENTE/$EV_AGENTE/$FE_NOME/v$numero"
  $SUDO mkdir -p "$PASTA_FERRAMENTAS/$EV_CLIENTE"
  if ! ev_ferramenta_constroi "$destino" "$caminho"; then
    $SUDO rm -rf "$destino"
    ev_erro "testes de $FE_NOME falharam; nada foi ativado"
  fi
  corpo=$(jq -cn --argjson contrato "$FE_CONTRATO" --arg hash "$(ev_ferramenta_hash "$destino")" \
    --arg testes "$FE_TESTES" --argjson numero "$numero" \
    '{numero: $numero, contrato: $contrato, hash_codigo: $hash, testes: $testes}')
  ev_api POST "$(ev_caminho)/ferramentas-proprias/$FE_NOME/versoes" "$corpo"
  if [ "$API_STATUS" != 201 ]; then
    $SUDO rm -rf "$destino"
    ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  fi
  $SUDO chown -R root:1000 "$destino"
  $SUDO chmod -R a-w "$destino"
  ferramentas_sobe >>"$LOG" 2>&1 || ev_erro "versão registrada, mas o contêiner da empresa não subiu. Veja: $LOG"
  printf '%s v%s ativa em %s (%s). Vale na próxima mensagem.\n' "$FE_NOME" "$numero" "$EV_NOME" "$EV_EMPRESA"
  jq -r '"segredos que ela usa: " + (if (.segredos | length) == 0 then "nenhum" else (.segredos | join(", ")) end)' <<<"$FE_CONTRATO"
}

ev_ferramenta_listar() {
  local segredos
  ev_resolve "${1:-}"
  ev_api GET "$(ev_caminho)/segredos"
  segredos=$API_RESPOSTA
  ev_api GET "$(ev_caminho)/ferramentas-proprias"
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  jq -r --argjson segredos "${segredos:-[]}" '
    if length == 0 then "nenhuma ferramenta própria ativada" else
    (.[] | "\(.nome)\tv\(.versao_ativa)\t\(if .ligada then "ligada" else "desligada" end)\t\(.contrato.efeito // "?")\tversões: \([.versoes[].numero] | join(","))\tsegredos: \((.contrato.segredos // []) | map(. + (if . as $s | $segredos | index($s) then "" else " (falta)" end)) | join(", "))") end
  ' <<<"$API_RESPOSTA"
}

ev_ferramenta_restaurar() {
  ev_resolve "${1:-}"
  [[ "${2:-}" =~ ^[a-z][a-z0-9_]{2,47}$ ]] && [[ "${3:-}" =~ ^[0-9]+$ ]] ||
    ev_erro "use: asimov ferramenta restaurar <ref> <nome> <versão>"
  ev_api POST "$(ev_caminho)/ferramentas-proprias/$2/restaurar" "$(jq -cn --argjson n "$3" '{numero: $n}')"
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  ferramentas_sobe >>"$LOG" 2>&1 || true
  printf '%s voltou para a v%s em %s.\n' "$2" "$3" "$EV_NOME"
}

ev_ferramenta_liga() {
  local ligada=$1
  shift
  ev_resolve "${1:-}"
  [[ "${2:-}" =~ ^[a-z][a-z0-9_]{2,47}$ ]] || ev_erro "diga o nome da ferramenta"
  ev_api POST "$(ev_caminho)/ferramentas-proprias/$2/ligada" "{\"ligada\": $ligada}"
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  ferramentas_sobe >>"$LOG" 2>&1 || true
  printf '%s %s em %s.\n' "$2" "$([ "$ligada" = true ] && echo ligada || echo desligada)" "$EV_NOME"
}

ev_ferramenta_segredo() {
  local ref=${1:-} nome=${2:-} valor
  ev_resolve "$ref"
  [[ "$nome" =~ ^[A-Z][A-Z0-9_]{1,47}$ ]] || ev_erro "nome do segredo em MAIÚSCULAS, como AGENDA_TOKEN"
  if [ "${3:-}" = --apagar ]; then
    ev_api DELETE "$(ev_caminho)/segredos/$nome"
    [ "$API_STATUS" = 204 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
    printf 'segredo %s apagado de %s.\n' "$nome" "$EV_NOME"
    return 0
  fi
  if ! { : </dev/tty; } 2>/dev/null; then
    ev_erro "segredo é digitado pelo operador, nunca passado pelo assistente. Peça para ele rodar: asimov ferramenta segredo $ref $nome"
  fi
  printf 'Valor de %s para %s (não aparece na tela): ' "$nome" "$EV_NOME" >/dev/tty
  IFS= read -rs valor </dev/tty || true
  printf '\n' >/dev/tty
  [ -n "$valor" ] || ev_erro "segredo vazio; nada mudou"
  ev_api PUT "$(ev_caminho)/segredos/$nome" "$(jq -cn --arg v "$valor" '{valor: $v}')"
  valor=""
  [ "$API_STATUS" = 204 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  printf 'segredo %s guardado cifrado para %s.\n' "$nome" "$EV_NOME"
}

ev_ferramenta_executar() {
  local ref=${1:-} nome=${2:-} entrada=${3:-'{}'} efeito
  ev_resolve "$ref"
  [[ "$nome" =~ ^[a-z][a-z0-9_]{2,47}$ ]] || ev_erro "use: asimov ferramenta executar <ref> <nome> '<entrada em JSON>'"
  jq -e 'type == "object"' <<<"$entrada" >/dev/null 2>&1 || ev_erro "a entrada precisa ser um objeto JSON, como '{\"turno\": \"manha\"}'"
  ev_api GET "$(ev_caminho)/ferramentas-proprias"
  efeito=$(jq -r --arg n "$nome" '.[] | select(.nome == $n) | .contrato.efeito' <<<"$API_RESPOSTA")
  if [ "$efeito" = altera ]; then
    ev_confirma_operador "Isto executa $nome de verdade, fora de conversa, e muda o sistema de fora." EXECUTAR \
      "asimov ferramenta executar $ref $nome '$entrada'"
  fi
  ev_api POST "$(ev_caminho)/ferramentas-proprias/$nome/executar" "$(jq -cn --argjson e "$entrada" '{entrada: $e}')"
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  jq . <<<"$API_RESPOSTA"
}

ev_ferramenta_execucoes() {
  ev_resolve "${1:-}"
  ev_api GET "$(ev_caminho)/execucoes"
  [ "$API_STATUS" = 200 ] || ev_erro "$(detalhe_erro "$API_RESPOSTA")"
  jq -r 'if length == 0 then "nenhuma ação registrada" else
    (.[] | "\(.quando[0:16])\t\(.ferramenta) v\(.versao)\t\(.estado)\t\(.entrada | tojson)") end' <<<"$API_RESPOSTA"
}

# asimov ferramenta diagnostico <ref>: sondas de dentro do contêiner da empresa. Tudo que não é
# internet pública precisa falhar; HTTPS público pelo proxy precisa funcionar.
ev_ferramenta_diagnostico() {
  ev_resolve "${1:-}"
  local nome="asimov-ferramentas-$EV_CLIENTE"
  $SUDO docker inspect -f '{{.HostConfig.NetworkMode}}' "$nome" 2>/dev/null | grep -qx none ||
    ev_erro "o contêiner $nome não está no ar ou tem rede. Ative uma ferramenta ou rode: asimov atualizar"
  $SUDO docker exec -i "$nome" python - <<'PY'
import socket
def direto(host, porta):
    try:
        socket.create_connection((host, porta), timeout=3).close()
        return "ALCANÇOU (ruim)"
    except OSError:
        return "bloqueado"
def pelo_proxy(destino):
    try:
        s = socket.create_connection(("127.0.0.1", 3128), timeout=5)
        s.sendall(f"CONNECT {destino} HTTP/1.1\r\nHost: {destino}\r\n\r\n".encode())
        linha = s.recv(200).split(b"\r\n")[0].decode(errors="replace")
        s.close()
        return linha
    except OSError as erro:
        return f"erro: {erro}"
print("direto redis:6379", direto("redis", 6379))
print("direto postgres:5432", direto("postgres", 5432))
print("direto 1.1.1.1:443", direto("1.1.1.1", 443))
for destino in ["127.0.0.1:8000", "169.254.169.254:443", "10.0.0.1:443", "redis:6379", "example.com:25"]:
    print("proxy", destino, pelo_proxy(destino))
print("proxy example.com:443 (deve ser 200)", pelo_proxy("example.com:443"))
PY
}

ev_ferramenta_ajuda() {
  cat <<'EOF'
asimov ferramenta: ferramentas próprias de um agente (guia: modelos/guias/evolucao-de-agente.md)

  asimov ferramenta listar <ref>                        ativas, versões e segredos que faltam
  asimov ferramenta testar <ref> <nome>                 contrato + dependências + testes sem rede
  asimov ferramenta ativar <ref> <nome>                 versão nova no atendimento (ação: o operador confirma)
  asimov ferramenta restaurar <ref> <nome> <versão>     volta a uma versão anterior
  asimov ferramenta desligar|ligar <ref> <nome>
  asimov ferramenta segredo <ref> <NOME> [--apagar]     o operador digita; o valor nunca aparece
  asimov ferramenta executar <ref> <nome> '<json>'      chamada de verdade, fora de conversa
  asimov ferramenta execucoes <ref>                     ações registradas (idempotência)
  asimov ferramenta diagnostico <ref>                   confere o isolamento do contêiner da empresa
EOF
}

fluxo_ferramenta() {
  local sub=${1:-ajuda}
  shift || true
  case "$sub" in
    listar) ev_ferramenta_listar "$@" ;;
    testar) ev_ferramenta_testar "$@" ;;
    ativar) ev_ferramenta_ativar "$@" ;;
    restaurar) ev_ferramenta_restaurar "$@" ;;
    desligar) ev_ferramenta_liga false "$@" ;;
    ligar) ev_ferramenta_liga true "$@" ;;
    segredo) ev_ferramenta_segredo "$@" ;;
    executar) ev_ferramenta_executar "$@" ;;
    execucoes | execuções) ev_ferramenta_execucoes "$@" ;;
    diagnostico | diagnóstico) ev_ferramenta_diagnostico "$@" ;;
    *) ev_ferramenta_ajuda ;;
  esac
}
