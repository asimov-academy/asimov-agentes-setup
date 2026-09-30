#!/usr/bin/env bash
# Estado do setup em arquivo CHAVE=VALOR (sem depender de jq, que só é instalado no passo 2)
# e segredos no .env do projeto. Permite retomar de onde parou.

estado_iniciar() {
  mkdir -p "$DIR_ESTADO"
  chmod 700 "$DIR_ESTADO"
  touch "$ARQ_ESTADO" "$LOG"
  chmod 600 "$ARQ_ESTADO" "$LOG"
  # Como root (timer), devolve ao operador o que um timer de versão anterior deixou com dono root.
  mantem_dono "$DIR_ESTADO" "$ARQ_ESTADO"
  mantem_dono "$DIR_ESTADO" "$LOG"
  [ ! -f "${ARQ_ENV:-}" ] || mantem_dono "$(dirname "$ARQ_ENV")" "$ARQ_ENV"
}

# mantem_dono REFERENCIA ARQUIVO: como root, o arquivo novo fica com o dono da referência. Os timers
# do backup e da WAHA rodam como root com o HOME do operador, e o `mv` de um temporário criado por
# eles deixava o estado e o .env com dono root: numa instalação feita com sudo, o `asimov` do
# operador parava de ler os dois ("A instalação ainda não terminou", chamadas sem X-Admin-Key).
mantem_dono() {
  [ "$(id -u)" = 0 ] || return 0
  [ -e "$1" ] || return 0
  chown --reference="$1" "$2" 2>/dev/null || true
}

estado_get() {
  local linha
  linha=$(grep -m1 "^$1=" "$ARQ_ESTADO" 2>/dev/null || true)
  printf '%s' "${linha#*=}"
}

estado_set() {
  local temp
  temp=$(mktemp "$DIR_ESTADO/.estado.XXXXXX")
  grep -v "^$1=" "$ARQ_ESTADO" >"$temp" 2>/dev/null || true
  printf '%s=%s\n' "$1" "$2" >>"$temp"
  if [ -e "$ARQ_ESTADO" ]; then mantem_dono "$ARQ_ESTADO" "$temp"; else mantem_dono "$DIR_ESTADO" "$temp"; fi
  mv "$temp" "$ARQ_ESTADO"
  chmod 600 "$ARQ_ESTADO"
}

estado_remove() {
  local temp chave
  temp=$(mktemp "$DIR_ESTADO/.estado.XXXXXX")
  cp "$ARQ_ESTADO" "$temp"
  for chave in "$@"; do
    grep -v "^$chave=" "$temp" >"$temp.novo" || true
    mv "$temp.novo" "$temp"
  done
  mantem_dono "$ARQ_ESTADO" "$temp"
  mv "$temp" "$ARQ_ESTADO"
  chmod 600 "$ARQ_ESTADO"
}

# Código novo baixado com ASIMOV_ATUALIZAR=1: a plataforma precisa ser reconstruída e
# migrada, mesmo que esses passos já tenham rodado na versão anterior.
estado_nova_versao() {
  local anterior
  anterior=$(estado_get versao)
  # Versão nova do setup: imagens, migrações e serviços rodam de novo.
  if [ "$anterior" != "$VERSAO" ] && estado_tem passo_imagens; then
    estado_remove passo_imagens passo_migracoes passo_servicos passo_api_local passo_api_https
  fi
  estado_set versao "$VERSAO"
}

estado_tem() {
  grep -q "^$1=" "$ARQ_ESTADO" 2>/dev/null
}

env_get() {
  local linha
  linha=$(grep -m1 "^$1=" "$ARQ_ENV" 2>/dev/null || true)
  printf '%s' "${linha#*=}"
}

# env_set CHAVE VALOR: grava no .env com permissão 600, substituindo o valor anterior.
env_set() {
  local temp
  # Quebra de linha no valor viraria outra chave no .env.
  case "$2" in *$'\n'* | *$'\r'*) return 1 ;; esac
  if [ ! -f "$ARQ_ENV" ]; then
    install -m 600 /dev/null "$ARQ_ENV"
    mantem_dono "$(dirname "$ARQ_ENV")" "$ARQ_ENV"
  fi
  temp=$(mktemp "$DIR_ESTADO/.estado.XXXXXX")
  grep -v "^$1=" "$ARQ_ENV" >"$temp" || true
  printf '%s=%s\n' "$1" "$2" >>"$temp"
  local destino
  destino=$(mktemp "${ARQ_ENV}.XXXXXX") || return 1
  install -m 600 "$temp" "$destino" || return 1
  mantem_dono "$ARQ_ENV" "$destino"
  mv -f "$destino" "$ARQ_ENV" || return 1
  rm -f "$temp"
}

# O .env guarda as chaves da instalação e as credenciais cifradas dos canais. O setup sempre grava
# com 600, mas nada impede alguém afrouxar depois: qualquer usuário da VPS passaria a ler tudo.
# Conferido a cada execução, e corrigido em vez de recusar (auditoria de 2026-09-18, A22 e spec).
confere_permissao_env() {
  [ -f "$ARQ_ENV" ] || return 0
  local modo
  modo=$(stat -c '%a' "$ARQ_ENV" 2>/dev/null || stat -f '%OLp' "$ARQ_ENV" 2>/dev/null || true)
  [ -n "$modo" ] || return 0
  if [ "$modo" != "600" ]; then
    chmod 600 "$ARQ_ENV"
    aviso "O .env estava com permissão $modo e voltou para 600: ele guarda as chaves da instalação."
  fi
}

# env_set_se_vazio CHAVE VALOR: não troca segredo já gerado numa execução anterior.
env_set_se_vazio() {
  [ -n "$(env_get "$1")" ] || env_set "$1" "$2"
}

# tentar comando...: 1 tentativa e até 3 repetições (5, 15 e 45 s). Saída vai para o log.
tentar() {
  local espera
  for espera in 5 15 45 fim; do
    if "$@" >>"$LOG" 2>&1; then
      return 0
    fi
    [ "$espera" = fim ] && return 1
    printf '\n[repetindo em %s s] %s\n' "$espera" "$*" >>"$LOG"
    sleep "$espera"
  done
}

PASSO_ATUAL=0
PASSO_TOTAL=0

# passo ID "descrição" "o que fazer se falhar" [--sem-repetir] comando...
passo() {
  local id=$1 descricao=$2 dica=$3 repetir=1
  shift 3
  if [ "${1:-}" = "--sem-repetir" ]; then
    repetir=0
    shift
  fi
  PASSO_ATUAL=$((PASSO_ATUAL + 1))

  if estado_tem "passo_$id"; then
    if confere_passo "$id" >>"$LOG" 2>&1; then
      linha_ok "$PASSO_ATUAL" "$PASSO_TOTAL" "$descricao (conferido)"
      return 0
    fi
    estado_remove "passo_$id"
    printf '\nRevalidando passo %s: estado salvo não basta.\n' "$id" >>"$LOG"
  fi

  linha_rodando "$PASSO_ATUAL" "$PASSO_TOTAL" "$descricao"
  printf '\n===== %s: %s =====\n' "$(date -Is)" "$descricao" >>"$LOG"
  local ok=1
  if [ "$repetir" -eq 1 ]; then
    tentar "$@" || ok=0
  else
    "$@" >>"$LOG" 2>&1 || ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    estado_set "passo_$id" "$(date -Is)"
    linha_ok "$PASSO_ATUAL" "$PASSO_TOTAL" "$descricao"
  else
    linha_erro "$PASSO_ATUAL" "$PASSO_TOTAL" "$descricao"
    erro_fatal "$descricao" "$dica"
  fi
}
